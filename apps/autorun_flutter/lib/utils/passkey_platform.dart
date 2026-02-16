import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class PasskeyPlatform {
  static bool get isSupported {
    if (kIsWeb) return true;
    if (Platform.isLinux) return false;
    return true;
  }

  static bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;
  static bool get isWeb => kIsWeb;
}
