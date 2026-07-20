import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

/// Native WebAuthn authenticator bridge.
///
/// The real impl (`package:passkeys`) calls into the platform's WebAuthn
/// surface — `navigator.credentials.create` on Web, the Play Services
/// FIDO API on Android, the LAContext on macOS, etc. Under `flutter test
/// -d chrome` there is no platform WebAuthn available (the test compiles
/// for the Dart VM, not the browser), so the [registerOverrideForTesting]
/// / [authenticateOverrideForTesting] seams let the substrate harness
/// substitute a deterministic in-process response. The PasskeyService
/// Dart code (challenge fetch, canonical signing, response parsing) runs
/// unchanged — only the literal browser-API call is faked, matching the
/// Phase C "substrate at the smallest boundary" rule.
class NativePasskeyAuthenticator {
  final PasskeyAuthenticator _auth = PasskeyAuthenticator();

  /// Test-only override for [register]. Set once in `setUpAll`, cleared in
  /// `tearDownAll`. When set, [register] dispatches to it instead of the
  /// real platform call.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      registerOverrideForTesting;

  /// Test-only override for [authenticate].
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      authenticateOverrideForTesting;

  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final override = registerOverrideForTesting;
    if (override != null) return override(options);
    final credential =
        await _auth.register(RegisterRequestType.fromJson(options));
    return credential.toJson();
  }

  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    final override = authenticateOverrideForTesting;
    if (override != null) return override(options);
    final credential =
        await _auth.authenticate(AuthenticateRequestType.fromJson(options));
    return credential.toJson();
  }
}
