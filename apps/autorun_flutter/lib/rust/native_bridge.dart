/// Public facade for the Rust-core FFI bridge (R-1 — conditional-import split).
///
/// On IO platforms this re-exports the real FFI implementation
/// ([native_bridge_io.dart]); on Web the honest stub
/// ([native_bridge_web.dart]). This file itself imports NO `dart:ffi`, so the
/// package compiles cleanly under `flutter build web`.
///
/// Shared pure-Dart types live here and are imported by both implementations.
library;

export 'native_bridge_io.dart' if (dart.library.html) 'native_bridge_web.dart';

/// Keypair material returned by `RustBridgeLoader.generateKeypair`.
class RustKeypairResult {
  RustKeypairResult({
    required this.publicKeyB64,
    required this.privateKeyB64,
    required this.principalText,
  });
  final String publicKeyB64;
  final String privateKeyB64;
  final String principalText;
}

/// Vault-encryption output returned by `RustBridgeLoader.encryptVault`.
class EncryptedVaultResult {
  EncryptedVaultResult({
    required this.encryptedDataB64,
    required this.saltB64,
    required this.nonceB64,
  });
  final String encryptedDataB64;
  final String saltB64;
  final String nonceB64;
}

/// Thrown when vault encryption fails.
class VaultEncryptionException implements Exception {
  VaultEncryptionException(this.message);
  final String message;
  @override
  String toString() => 'VaultEncryptionException: $message';
}

/// Thrown when vault decryption fails.
class VaultDecryptionException implements Exception {
  VaultDecryptionException(this.message);
  final String message;
  @override
  String toString() => 'VaultDecryptionException: $message';
}
