/// VaultCryptoService — the SINGLE Dart entry point for vault crypto (A-4 W1).
///
/// Wraps the existing FFI bridge (`RustBridgeLoader.encryptVault` /
/// `decryptVault` in `lib/rust/native_bridge_io.dart`) behind a clean
/// off-the-UI-isolate async API. This is the only place Dart code calls the
/// vault-crypto FFI; both vault screens and `PasskeyService` go through here
/// (DRY).
///
/// ## Why an isolate
/// Argon2id key derivation (64 MiB, time=3, parallelism=4) + AES-256-GCM is a
/// BLOCKING synchronous FFI call that takes ~0.1–1 s. Running it on the UI
/// isolate would freeze the app (the unlock spinner would not animate). We
/// therefore run encrypt/decrypt inside a background Dart isolate via
/// `FlutterFoundation.compute()` (`Isolate.run`). The plaintext + password
/// are plain `String`s and the FFI returns plain base64 `String`s, so every
/// value that crosses the isolate boundary is trivially sendable. Each
/// background isolate re-opens `libicp_core` independently (the cached
/// `DynamicLibrary` static in `RustBridgeLoader` does NOT cross isolate
/// boundaries — this is correct; fresh load per isolate, and the load is
/// cheap).
///
/// ## Single source of truth for crypto params
/// The Argon2id + AES-GCM parameters live in ONE place:
/// `crates/icp_core/src/vault.rs:18-24`. This service NEVER re-declares or
/// mutates them; it forwards only the password and base64-encoded plaintext
/// to the FFI. There are no magic numbers here.
///
/// ## Zero-knowledge property
/// The password passed to [encrypt]/[decrypt] NEVER leaves this device. It is
/// consumed only inside the local FFI call below; it is never serialised into
/// an HTTP body, never logged, never persisted. The opaque blob returned by
/// [encrypt] is the only thing ever sent to the server.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../rust/native_bridge.dart';

/// Thrown when the native vault crypto library (`libicp_core`) cannot be
/// loaded on the current platform.
///
/// Vault crypto MUST fail loud (AGENTS.md: no silent `null`, no swallowed
/// error). The UI surfaces this to the user with a clear "vault unavailable"
/// message instead of silently no-op'ing.
class VaultUnavailableException implements Exception {
  const VaultUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'VaultUnavailableException: $message';
}

/// Isolate message for [_isolateEncrypt]. Plain `Map` (trivially sendable).
const _kArgPassword = 'password';
const _kArgPlaintextB64 = 'plaintext_b64';
const _kArgEncryptedDataB64 = 'encrypted_data_b64';
const _kArgSaltB64 = 'salt_b64';
const _kArgNonceB64 = 'nonce_b64';

const _kResEncryptedData = 'encrypted_data';
const _kResSalt = 'salt';
const _kResNonce = 'nonce';
const _kResPlaintextB64 = 'plaintext_b64';

const String _kLibMissingMessage =
    'libicp_core could not be loaded on this platform — vault crypto is '
    'unavailable. On Linux desktop install/run a Secret Service per '
    'AGENTS.md; on Web the vault is not supported (see R-1).';

/// Top-level isolate entry: encrypts in the background isolate.
///
/// `compute()` requires a top-level or static function. We exchange plain
/// `Map<String, String>` values to stay maximally sendable-portable.
@pragma('vm:entry-point')
Map<String, String> _isolateEncrypt(Map<String, String> args) {
  final res = const RustBridgeLoader().encryptVault(
    password: args[_kArgPassword]!,
    plaintextB64: args[_kArgPlaintextB64]!,
  );
  if (res == null) {
    throw VaultUnavailableException(_kLibMissingMessage);
  }
  return <String, String>{
    _kResEncryptedData: res.encryptedDataB64,
    _kResSalt: res.saltB64,
    _kResNonce: res.nonceB64,
  };
}

/// Top-level isolate entry: decrypts in the background isolate.
@pragma('vm:entry-point')
Map<String, String> _isolateDecrypt(Map<String, String> args) {
  final res = const RustBridgeLoader().decryptVault(
    password: args[_kArgPassword]!,
    encryptedDataB64: args[_kArgEncryptedDataB64]!,
    saltB64: args[_kArgSaltB64]!,
    nonceB64: args[_kArgNonceB64]!,
  );
  if (res == null) {
    throw VaultUnavailableException(_kLibMissingMessage);
  }
  return <String, String>{_kResPlaintextB64: res};
}

class VaultCryptoService {
  const VaultCryptoService();

  /// Encrypts [plaintext] (UTF-8) under [password], returning the opaque
  /// blob that is safe to send to `/api/v1/vault`.
  ///
  /// The password is consumed ONLY by the local FFI call; it is never sent
  /// over the network by this service (zero-knowledge).
  ///
  /// Throws [VaultUnavailableException] if `libicp_core` cannot be loaded.
  /// Throws [VaultEncryptionException] on crypto failure (FFI is fail-fast).
  Future<EncryptedVaultResult> encrypt({
    required String password,
    required String plaintext,
  }) async {
    final plaintextB64 = base64.encode(utf8.encode(plaintext));
    final out = await compute(
      _isolateEncrypt,
      <String, String>{
        _kArgPassword: password,
        _kArgPlaintextB64: plaintextB64,
      },
      debugLabel: 'vault.encrypt',
    );
    return EncryptedVaultResult(
      encryptedDataB64: out[_kResEncryptedData]!,
      saltB64: out[_kResSalt]!,
      nonceB64: out[_kResNonce]!,
    );
  }

  /// Decrypts [blob] under [password], returning the original UTF-8 plaintext.
  ///
  /// Throws [VaultUnavailableException] if `libicp_core` cannot be loaded.
  /// Throws [VaultDecryptionException] on a wrong password or tampered
  /// ciphertext (AES-256-GCM auth-tag failure — fail-fast, never returns
  /// garbage plaintext).
  Future<String> decrypt({
    required String password,
    required EncryptedVaultResult blob,
  }) async {
    final out = await compute(
      _isolateDecrypt,
      <String, String>{
        _kArgPassword: password,
        _kArgEncryptedDataB64: blob.encryptedDataB64,
        _kArgSaltB64: blob.saltB64,
        _kArgNonceB64: blob.nonceB64,
      },
      debugLabel: 'vault.decrypt',
    );
    final plaintextB64 = out[_kResPlaintextB64]!;
    return utf8.decode(base64.decode(plaintextB64));
  }

  /// Cheap probe used by tests/screens to decide whether to skip vault UI.
  /// Runs a trivial FFI call on the CALLING isolate (NOT the heavy Argon2id
  /// path) — safe to call from the UI thread.
  static bool nativeLibAvailable() {
    return const RustBridgeLoader().jsExec(script: '1', jsonArg: null) != null;
  }
}
