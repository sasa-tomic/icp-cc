import 'package:flutter/foundation.dart' show visibleForTesting;

/// Stub `NativePasskeyAuthenticator` selected when neither `dart:io` nor
/// `dart:html` is available — the no-platform case.
///
/// The override seams mirror [NativePasskeyAuthenticator] in
/// `passkey_authenticator_native.dart` so the substrate harness can install
/// the same test-only response generator regardless of which conditional
/// branch is selected at compile time.
class NativePasskeyAuthenticator {
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      registerOverrideForTesting;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      authenticateOverrideForTesting;

  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final override = registerOverrideForTesting;
    if (override != null) return override(options);
    throw UnsupportedError(
        'Passkeys are not available on this platform. Use the app on macOS, Windows, or Android.');
  }

  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    final override = authenticateOverrideForTesting;
    if (override != null) return override(options);
    throw UnsupportedError(
        'Passkeys are not available on this platform. Use the app on macOS, Windows, or Android.');
  }
}
