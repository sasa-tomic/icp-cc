import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'dart:io' show Platform;

/// Platform support flags for the passkey surface.
///
/// The boolean surface (`isSupported` / `isLinuxDesktop` / `isWeb`) is
/// platform-derived in production — but the Web e2e harness runs under
/// `flutter test -d chrome`, where the test compiles for the Dart VM (so
/// `kIsWeb` is FALSE) on a Linux host (so `Platform.isLinux` is TRUE). That
/// would gate every Web-only passkey flow behind the Linux-desktop
/// unsupported panel, leaving them untestable. [isSupportedOverrideForTesting]
/// is the smallest seam that lets the harness pretend to be the Web surface:
/// set it once in `setUpAll`, clear it in `tearDownAll`.
class PasskeyPlatform {
  /// Test-only override for [isSupported]. When non-null, [isSupported]
  /// returns its value and [isLinuxDesktop] returns `false` (matching the
  /// semantics of the Web surface). MUST be cleared in `tearDownAll`.
  @visibleForTesting
  static bool? isSupportedOverrideForTesting;

  static bool get isSupported {
    final override = isSupportedOverrideForTesting;
    if (override != null) return override;
    if (kIsWeb) return true;
    if (Platform.isLinux) return false;
    return true;
  }

  /// When the test pretends to be the Web surface (override == true), the
  /// desktop-linux branch must NOT fire either — otherwise the Account &
  /// Keys screen renders the Linux passkey warning row and the Manage button
  /// is unreachable.
  static bool get isLinuxDesktop {
    if (isSupportedOverrideForTesting == true) return false;
    return !kIsWeb && Platform.isLinux;
  }

  static bool get isWeb => kIsWeb;
}
