// ignore_for_file: lines_longer_than_80_chars

/// `flutter_secure_storage` substrate for the Web e2e harness.
///
/// On native targets `flutter_secure_storage` is backed by libsecret/iOS
/// Keychain/Android Keystore — none of which exist under
/// `flutter test -d chrome`. The SDK provides a built-in in-memory mock via
/// [FlutterSecureStorage.setMockInitialValues]; on Web the plugin's real
/// IndexedDB impl is swapped for this in-memory store the moment the mock is
/// registered. Used by `ProfileRepository` (private keys + mnemonics) and
/// `SecureStorageReadiness` (the WU-S2 round-trip probe).
///
/// Direct SDK call; no app code touched. The Web pure-Dart crypto path
/// (Ed25519 / secp256k1 / Argon2id / AES-256-GCM via
/// `lib/rust/native_bridge_web.dart`) runs for real — we never mock crypto.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Install (or reset) the FlutterSecureStorage in-memory mock with optional
/// [initialValues]. Idempotent; safe to call from `setUpAll` / `setUp`.
void installSubstrateSecureStorage(
    [Map<String, String> initialValues = const {}]) {
  FlutterSecureStorage.setMockInitialValues(
      Map<String, String>.from(initialValues));
}
