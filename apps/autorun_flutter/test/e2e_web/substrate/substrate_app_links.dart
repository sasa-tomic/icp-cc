// ignore_for_file: lines_longer_than_80_chars

/// `app_links` noise silencer for the Web e2e harness.
///
/// `_KeypairAppState._initDeepLinks` is guarded by
/// `if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return;`.
/// Under `flutter test -d chrome`, `kIsWeb` is false (test compiles for VM)
/// and `defaultTargetPlatform` is `TargetPlatform.linux` (Linux host VM) — so
/// the guard SHOULD early-return.
///
/// Empirically it does NOT, because the `DeepLinkService.instance` singleton
/// constructs an `AppLinks()` whose EventChannel starts listening on a
/// background isolate BEFORE the guard fires. The result is a noisy
/// `MissingPluginException` from `com.llfbandit.app_links/events` that
/// surfaces as a framework-test failure even when the wizard renders fine.
///
/// Fix: register an empty method-channel mock for `app_links/events` so the
/// `listen` invocation returns `null` instead of throwing. Pure noise
/// suppression at the platform boundary — no app code touched.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Install a no-op handler for the `com.llfbandit.app_links/events` channel
/// so `app_links` does not throw `MissingPluginException` during the Web
/// harness boot.
void installSubstrateAppLinksSilencer() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.app_links'),
    (MethodCall call) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.app_links/events'),
    (MethodCall call) async => null,
  );
}
