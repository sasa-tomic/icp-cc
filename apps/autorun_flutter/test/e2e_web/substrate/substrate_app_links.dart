// ignore_for_file: lines_longer_than_80_chars

/// `app_links` substrate for the Web e2e harness.
///
/// Two responsibilities:
/// 1. **Silence** the `MissingPluginException` that fires when `_KeypairAppState
///    ._initDeepLinks` constructs `AppLinks()` whose EventChannel starts
///    listening before the early-return guard fires. [installSubstrateAppLinksSilencer]
///    installs a no-op method-channel handler so the channel returns `null`
///    instead of throwing.
/// 2. **Emit** synthetic deep-link events into the real `DeepLinkService`
///    singleton — so Phase L deeplink flows can drive the parsing/dispatch
///    layer without a real OS launcher (see [emitSubstrateDeepLink]).
///
/// `_KeypairAppState._initDeepLinks` is guarded by
/// `if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return;`.
/// Under `flutter test -d chrome`, `kIsWeb` is false (test compiles for VM)
/// and `defaultTargetPlatform` is `TargetPlatform.linux` (Linux host VM) — so
/// the guard early-returns and `_handleDeepLink` is never wired to
/// `linkStream`. To exercise the parsing layer we therefore pump events
/// DIRECTLY into `DeepLinkService.instance.handleLink` — the public API the
/// app's listener would normally subscribe to. Tests that need to verify
/// dispatch subscribe to `DeepLinkService.instance.linkStream` themselves
/// (the stream is a broadcast `StreamController`, multi-subscriber-safe).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/deep_link_service.dart';

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

/// Pump a synthetic deep-link event through the REAL `DeepLinkService`
/// singleton (the same one `_KeypairAppState._initDeepLinks` subscribes to
/// on non-linux surfaces). On `flutter test -d chrome` the app's listener is
/// not registered (the guard early-returns), so this only reaches listeners
/// the test itself wires via `DeepLinkService.instance.linkStream.listen(...)`.
///
/// The real `DeepLinkService.handleLink` parses the URI and adds a
/// `DeepLinkData` to its broadcast stream when (and only when) the URI is a
/// recognised scheme + host. Invalid URIs are silently dropped — exactly
/// the contract the deeplink.invalid_scheme + deeplink.purchase_unavailable
/// flows assert.
void emitSubstrateDeepLink(Uri uri) {
  DeepLinkService.instance.handleLink(uri);
}

/// Convenience: subscribe to the real `DeepLinkService` link stream for the
/// duration of [body], returning every `DeepLinkData` [body] emitted.
///
/// [body] runs inside `tester.runAsync(...)` so any `Future.delayed` /
/// `Timer` it creates fires in wall-clock time (under `flutter test -d
/// chrome` the binding's fake clock never advances real Timers, so
/// `Future.delayed` outside `runAsync` hangs forever). The subscription
/// is cancelled (fire-and-forget — broadcast controllers don't block on
/// cancel) after [body] returns.
Future<List<DeepLinkData>> collectSubstrateDeepLinks(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final collected = <DeepLinkData>[];
  final sub = DeepLinkService.instance.linkStream.listen(collected.add);
  try {
    await tester.runAsync(body);
  } finally {
    unawaited(sub.cancel());
  }
  return collected;
}
