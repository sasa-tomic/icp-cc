// ignore_for_file: lines_longer_than_80_chars

/// `package_info_plus` substrate for the Web e2e harness.
///
/// `SettingsScreen` shows a spinner until `PackageInfo.fromPlatform()`
/// resolves, then renders the "ICP Autorun" heading + version row. Under
/// `flutter test -d chrome` no real platform channel is registered, so the
/// call hangs / returns Unknown — and the heading never renders. The SDK
/// provides [PackageInfo.setMockInitialValues] for exactly this case; call
/// it once during substrate setup so every screen that reads `PackageInfo`
/// gets a stable, deterministic value.
library;

import 'package:package_info_plus/package_info_plus.dart';

/// Install a stable fake [PackageInfo]. Idempotent.
void installSubstratePackageInfo() {
  PackageInfo.setMockInitialValues(
    appName: 'ICP Autorun',
    packageName: 'com.example.icp_autorun',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
    installerStore: null,
  );
}
