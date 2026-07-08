// R-4 Web runtime — vault crypto (Argon2id KDF + AES-256-GCM).
//
// Proves the PURE-DART Web vault implementation
// (`lib/rust/native_bridge_web.dart`) is bit-for-bit cross-compatible with the
// native `libicp_core`:
//   1. The Argon2id KDF reproduces a Rust reference vector (the authoritative
//      cross-compat guarantee — same password+salt → same 32-byte key).
//   2. A blob encrypted by Rust decrypts cleanly on Web (hardcoded capture).
//   3. Live native ↔ Web round-trips (when libicp_core loads).
//   4. Web → Web round-trip + wrong-password failure (fail-fast).
//
// These tests are SLOW: each Argon2id derivation is ~1 min of pure-Dart CPU
// (64 MiB memory cost, 3 iterations) in the checked-mode test VM. Generous
// timeouts are set deliberately.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart'
    show VaultDecryptionException;
import 'package:icp_autorun/rust/native_bridge.dart' as native;
import 'package:icp_autorun/rust/native_bridge_web.dart' as web;

// ── Argon2id reference vector (captured from Rust icp_core::vault::derive_key)
//    password="test-password", salt=16×0x01, m=65536, t=3, p=4, outLen=32 ────
const _kArgonPassword = 'test-password';
final _kArgonSalt = List<int>.filled(16, 1);
const _kArgonKeyHex =
    'd01d66842417f2c272d92e15e46a23e2b351b2c52ae42d1c59c1c8a7c3486a63';

// ── Vault blob captured from Rust `encrypt_vault("test-password", b"hello vault cross-compat")`
//    Proves Web can decrypt a blob produced by the native core. ───────────────
const _kNativeBlobPassword = 'test-password';
const _kNativeBlobPlaintext = 'hello vault cross-compat';
const _kNativeBlobCiphertextB64 = 'cgKSiUZ182w59MdpeAVwkZlxtHXwXAttSMP4GovzZ8LY9ur+XyG6Zg==';
const _kNativeBlobSaltB64 = 'rDsfVnmId9BefA62OiQK5Q==';
const _kNativeBlobNonceB64 = 'd5m/Bh6x3itdWKwr';

/// Generous timeout for any test that runs Argon2id (memory-hard, slow in
/// pure-Dart checked mode).
const _argonTimeout = Timeout(Duration(minutes: 6));

bool get _nativeAvailable {
  try {
    return const native.RustBridgeLoader().jsExec(script: '1', jsonArg: null) !=
        null;
  } catch (_) {
    return false;
  }
}

void main() {
  group('R-4 Argon2id KDF (Web matches Rust)', () {
    test('deriveKey reproduces the Rust reference vector', () async {
      // This is THE cross-compat guarantee: if Web Argon2id(password, salt)
      // produces the same 32-byte key as Rust's `argon2` crate, then any
      // native-encrypted blob is decryptable on Web (and vice-versa), because
      // AES-256-GCM is a deterministic standard given (key, nonce).
      final algorithm = const DartArgon2id(
        parallelism: 4,
        memory: 65536,
        iterations: 3,
        hashLength: 32,
      );
      final sk = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(_kArgonPassword)),
        nonce: _kArgonSalt,
      );
      final bytes = await sk.extractBytes();
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, equals(_kArgonKeyHex));
    }, timeout: _argonTimeout);
  });

  group('R-4 vault native→Web cross-compat', () {
    test('Web decrypts a blob encrypted by the native Rust core', () async {
      // Uses the SAME Argon2id + AES-256-GCM the production Web build uses
      // (the web loader's encryptVault/decryptVault), exercised through the
      // public bridge API. A successful decrypt proves the Web key derivation
      // AND the ciphertext||tag layout both match the native core.
      final plaintextB64 = await const web.RustBridgeLoader().decryptVault(
        password: _kNativeBlobPassword,
        encryptedDataB64: _kNativeBlobCiphertextB64,
        saltB64: _kNativeBlobSaltB64,
        nonceB64: _kNativeBlobNonceB64,
      );
      expect(plaintextB64, isNotNull);
      final plaintext = utf8.decode(base64.decode(plaintextB64!));
      expect(plaintext, equals(_kNativeBlobPlaintext));
    }, timeout: _argonTimeout);
  });

  group('R-4 vault Web↔native live cross-compat', () {
    test('Web-encrypted blob decrypts on the native FFI', () async {
      if (!_nativeAvailable) {
        // ignore: avoid_print
        print('SKIP: libicp_core not loaded');
        return;
      }
      const plaintext = 'live web->native roundtrip';
      final ptB64 = base64.encode(utf8.encode(plaintext));

      final blob = await const web.RustBridgeLoader()
          .encryptVault(password: 'live-pw', plaintextB64: ptB64);
      expect(blob, isNotNull);

      final nativeOut = await const native.RustBridgeLoader().decryptVault(
        password: 'live-pw',
        encryptedDataB64: blob!.encryptedDataB64,
        saltB64: blob.saltB64,
        nonceB64: blob.nonceB64,
      );
      expect(utf8.decode(base64.decode(nativeOut!)), equals(plaintext));
    }, timeout: _argonTimeout, skip: !_nativeAvailable ? 'libicp_core not loaded' : false);

    test('native-encrypted blob decrypts on Web', () async {
      if (!_nativeAvailable) {
        // ignore: avoid_print
        print('SKIP: libicp_core not loaded');
        return;
      }
      const plaintext = 'live native->web roundtrip';
      final ptB64 = base64.encode(utf8.encode(plaintext));

      final blob = await const native.RustBridgeLoader()
          .encryptVault(password: 'live-pw2', plaintextB64: ptB64);
      expect(blob, isNotNull);

      final webOut = await const web.RustBridgeLoader().decryptVault(
        password: 'live-pw2',
        encryptedDataB64: blob!.encryptedDataB64,
        saltB64: blob.saltB64,
        nonceB64: blob.nonceB64,
      );
      expect(utf8.decode(base64.decode(webOut!)), equals(plaintext));
    }, timeout: _argonTimeout, skip: !_nativeAvailable ? 'libicp_core not loaded' : false);
  });

  group('R-4 vault Web→Web round-trip + negative paths', () {
    test('encrypt then decrypt returns the original plaintext', () async {
      const plaintext = 'web roundtrip secret 🦀';
      final ptB64 = base64.encode(utf8.encode(plaintext));

      final blob = await const web.RustBridgeLoader()
          .encryptVault(password: 'roundtrip-pw', plaintextB64: ptB64);
      expect(blob, isNotNull);
      // Sanity: opaque blob, all three fields non-empty.
      expect(blob!.encryptedDataB64, isNotEmpty);
      expect(blob.saltB64, isNotEmpty);
      expect(blob.nonceB64, isNotEmpty);

      final out = await const web.RustBridgeLoader().decryptVault(
        password: 'roundtrip-pw',
        encryptedDataB64: blob.encryptedDataB64,
        saltB64: blob.saltB64,
        nonceB64: blob.nonceB64,
      );
      expect(utf8.decode(base64.decode(out!)), equals(plaintext));
    }, timeout: _argonTimeout);

    test('a WRONG password throws VaultDecryptionException (fail-fast)',
        () async {
      const plaintext = 'cannot decrypt me';
      final ptB64 = base64.encode(utf8.encode(plaintext));
      final blob = await const web.RustBridgeLoader()
          .encryptVault(password: 'correct', plaintextB64: ptB64);

      // AES-256-GCM auth-tag MUST reject the wrong-derived-key decrypt.
      await expectLater(
        const web.RustBridgeLoader().decryptVault(
          password: 'WRONG',
          encryptedDataB64: blob!.encryptedDataB64,
          saltB64: blob.saltB64,
          nonceB64: blob.nonceB64,
        ),
        throwsA(isA<VaultDecryptionException>()),
      );
    }, timeout: _argonTimeout);

    test('each encryption uses a fresh random salt (non-deterministic)',
        () async {
      final ptB64 = base64.encode(utf8.encode('same plaintext'));
      final a = await const web.RustBridgeLoader()
          .encryptVault(password: 'same', plaintextB64: ptB64);
      final b = await const web.RustBridgeLoader()
          .encryptVault(password: 'same', plaintextB64: ptB64);
      expect(a!.saltB64, isNot(equals(b!.saltB64)));
      expect(a.nonceB64, isNot(equals(b.nonceB64)));
      expect(a.encryptedDataB64, isNot(equals(b.encryptedDataB64)));
    }, timeout: _argonTimeout);
  });
}
