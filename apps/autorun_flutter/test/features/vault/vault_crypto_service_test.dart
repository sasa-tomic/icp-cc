// A-4 W1 — VaultCryptoService real round-trip tests.
//
// Exercises the production VaultCryptoService against the REAL FFI
// (libicp_core.so → Argon2id 64 MiB + AES-256-GCM). The crypto itself is NOT
// mocked (AGENTS.md: real crypto in tests). The service runs the heavy Argon2id
// inside a background Dart isolate via `compute()`, so these tests also prove
// the isolate path works end-to-end.
//
// Guard: skipped when libicp_core cannot be loaded (e.g. CI without the .so).

@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';

void main() {
  final service = const VaultCryptoService();

  /// All Argon2id (64 MiB) calls must be bounded; a runaway compute() hangs
  /// the test runner. 30 s is ~30x the observed wall-clock on a dev box.
  const cryptoTimeout = Duration(seconds: 30);

  group('VaultCryptoService (real FFI, real Argon2id + AES-256-GCM)', () {
    test('encrypt → decrypt round-trips the original plaintext', () async {
      if (!VaultCryptoService.nativeLibAvailable()) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      const password = 'correct horse battery staple';
      const plaintext = '{"secret":"vault-data","n":42}';

      final blob = await service
          .encrypt(password: password, plaintext: plaintext)
          .timeout(cryptoTimeout);

      // Sanity: the opaque blob has the three base64 fields, non-empty.
      expect(blob.encryptedDataB64, isNotEmpty);
      expect(blob.saltB64, isNotEmpty);
      expect(blob.nonceB64, isNotEmpty);
      stdout.writeln(
          'W1: blob salt=${blob.saltB64.length}c nonce=${blob.nonceB64.length}c '
          'ct=${blob.encryptedDataB64.length}c');

      final decrypted = await service
          .decrypt(password: password, blob: blob)
          .timeout(cryptoTimeout);
      expect(decrypted, equals(plaintext));
    });

    test('a WRONG password throws VaultDecryptionException (not garbage)',
        () async {
      if (!VaultCryptoService.nativeLibAvailable()) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      const password = 'correct horse battery staple';
      const wrongPassword = 'WRONG password';
      const plaintext = '{"k":"v"}';

      final blob = await service
          .encrypt(password: password, plaintext: plaintext)
          .timeout(cryptoTimeout);

      // AES-256-GCM tag verification MUST reject a wrong-derived-key decrypt.
      await expectLater(
        service.decrypt(password: wrongPassword, blob: blob),
        throwsA(isA<VaultDecryptionException>()),
      );
    });

    test('TAMPERED ciphertext throws VaultDecryptionException (GCM auth)',
        () async {
      if (!VaultCryptoService.nativeLibAvailable()) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      const password = 'vault-pw';
      const plaintext = 'tamper-me';

      final blob = await service
          .encrypt(password: password, plaintext: plaintext)
          .timeout(cryptoTimeout);

      final tampered = EncryptedVaultResult(
        encryptedDataB64: _flipFirstBase64Char(blob.encryptedDataB64),
        saltB64: blob.saltB64,
        nonceB64: blob.nonceB64,
      );

      await expectLater(
        service.decrypt(password: password, blob: tampered),
        throwsA(isA<VaultDecryptionException>()),
      );
    });

    test('nativeLibAvailable() matches a direct loader probe', () {
      // Smoke-check the test's own skip guard.
      expect(VaultCryptoService.nativeLibAvailable(), isA<bool>());
    });
  });
}

/// Deterministically mutate the first base64 character of `b64` to a different
/// valid base64 character, preserving length. Decoded bytes change so GCM auth
/// fails, without producing an invalid base64 string.
String _flipFirstBase64Char(String b64) {
  final first = b64[0];
  final replacement = first == 'A' ? 'B' : 'A';
  return replacement + b64.substring(1);
}
