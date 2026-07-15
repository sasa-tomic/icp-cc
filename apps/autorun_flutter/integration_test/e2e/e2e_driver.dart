// ignore_for_file: lines_longer_than_80_chars

/// The platform-agnostic driver for the unified e2e harness.
///
/// Flows are written against a [WidgetTester] + this driver, so the SAME flow
/// body runs on both surfaces:
///   - **desktop**: `IntegrationTestWidgetsFlutterBinding` + real FFI
///     (`libicp_core.so`) under Xvfb; booted via `app.main()`.
///   - **web**: `flutter_test` binding against Playwright Chromium (Tier 1) or
///     `flutter drive` integration boot (Tier 2); booted via `pumpWidget`.
///
/// CRITICAL — never `pumpAndSettle` under the real FFI: the Argon2id spinner
/// animates forever and the call never returns. Every wait goes through
/// bounded [pump] loops via [waitUntil].
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart' as app;

/// Which surface the driver is running on.
enum E2ESurface { desktop, web }

/// Desktop render surface (matches the Xvfb screen used for real-bundle shots).
const Size kDesktopSize = Size(1440, 900);
const double kDesktopDpr = 1.0;

/// Per-phase wall-clock budgets. Integration-test pumps use real wall-clock
/// time, so background-isolate crypto completes during the pumps.
const Duration _kWaitDefault = Duration(seconds: 30);
const Duration _kWaitStep = Duration(milliseconds: 200);

/// Bounded multi-frame settle for cold boot. Processes many frames (so the
/// first-run gate's multi-hop async chain — ensureLoaded → script load →
/// onboarding → showFirstRunSetupIfNeeded — can complete) WITHOUT relying on
/// `pumpAndSettle`, which never returns once a real-FFI spinner or a pending
/// marketplace fetch is on screen. Safe at boot: no crypto is running yet.
Future<void> _settle(WidgetTester tester,
    {Duration budget = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(budget);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Drives the REAL app on either surface.
///
/// Construct once per suite, then [boot] once, run many phases (resetAppState
/// + [remount] between them). The driver never rebuilds the native bundle —
/// [remount] is a cheap in-process `pumpWidget(KeypairApp())` reboot (~1–2s).
class E2EDriver {
  E2EDriver({
    required this.surface,
    this.shotDir = '/code/icp-cc/docs/specs/ux_screenshots/e2e',
  });

  final E2ESurface surface;
  final String shotDir;

  /// Boot the real app for the first time in this process.
  ///
  /// Desktop: mounts the production widget tree via `app.main()` under
  /// `runAsync` (real FFI load + service-locator + profile/theme load).
  /// Web: mounts the production tree via `pumpWidget(KeypairApp())` — the
  /// conditional-import split selects [native_bridge_web.dart] (real pure-Dart
  /// Ed25519/secp256k1/Argon2id/AES-256-GCM), so NO FFI is touched. The benign
  /// `libicp_core.so open failed` line is the IO-side residual import being
  /// loaded by the analyzer and is ignored on Web at runtime.
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopSize * kDesktopDpr;
    tester.view.devicePixelRatio = kDesktopDpr;
    switch (surface) {
      case E2ESurface.desktop:
        await tester.runAsync(() => app.main());
        await _settle(tester);
      case E2ESurface.web:
        await tester.pumpWidget(const app.KeypairApp());
        // NOTE: deliberately NOT `runAsync`. Under `flutter test -d chrome`
        // (TestWidgetsFlutterBinding) there are no real plugins registered, so
        // letting the unawaited ensureLoaded() reach real platform channels
        // (shared_preferences/path_provider) throws a FATAL
        // MissingPluginException. Keeping the async work on the fake clock means
        // the production widget tree mounts (MaterialApp renders) WITHOUT
        // triggering unreachable channel calls — enough to assert the
        // cross-surface boot contract. Loading real state needs plugin
        // substrate fakes (Phase 2). See suite_web_smoke_test.dart header.
        await _settle(tester);
    }
  }

  /// Re-mount the shell after a state wipe. Cheap in-process reboot: a UNIQUE
  /// key forces Flutter to recreate `_KeypairAppState` (fresh controllers →
  /// `ensureLoaded` re-runs → the changed on-disk store is re-loaded → the
  /// first-run gate re-evaluates). A plain `pumpWidget(const KeypairApp())`
  /// would RECONCILE the existing element and reuse the stale state — so the
  /// key is load-bearing here. Does NOT rebuild the native bundle.
  Future<void> remount(WidgetTester tester) async {
    await tester.pumpWidget(app.KeypairApp(key: UniqueKey()));
    await _settle(tester);
  }

  /// Dismiss the first-run wizard by tapping its close (X) button. Bounded —
  /// never pumpAndSettle (the Scripts screen kicks off marketplace fetches).
  Future<void> dismissWizard(WidgetTester tester) async {
    var guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    if (present(find.byIcon(Icons.close), tester)) {
      await tester.tap(find.byIcon(Icons.close).first);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Bounded-pump until [ready] returns true. Returns the final value of
  /// [ready]. NEVER pumpAndSettle (real-FFI spinners animate forever).
  Future<bool> waitUntil(
    WidgetTester tester,
    bool Function() ready, {
    Duration timeout = _kWaitDefault,
    Duration step = _kWaitStep,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(step);
      if (ready()) return true;
    }
    return ready();
  }

  /// Whether ANY widget matching [f] is present.
  bool present(Finder f, WidgetTester tester) => tester.any(f);

  /// Tap [f] only if present; returns whether a tap happened (no-op + false
  /// otherwise). Avoids flaky "at least one" assertion failures.
  Future<bool> tapIfPresent(WidgetTester tester, Finder f) async {
    if (present(f, tester)) {
      await tester.tap(f.first);
      await tester.pump();
      return true;
    }
    return false;
  }

  /// Capture the live render tree to `<shotDir>/<name>.png`. Captures straight
  /// from the layer tree because the integration_test takeScreenshot channel
  /// is unserviced without a flutter_driver. Works on both bindings.
  Future<void> screenshot(WidgetTester tester, String name) async {
    await Directory(shotDir).create(recursive: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final RenderView view = tester.binding.renderViews.first;
    final Size size = view.size.isEmpty ? kDesktopSize : view.size;
    // Direct layer-tree access is a legitimate test-only use of the protected
    // member (mirrors the proven ux_probe / h_vault pattern).
    // ignore: invalid_use_of_protected_member
    final OffsetLayer layer = view.layer! as OffsetLayer;
    final ui.Image image =
        await layer.toImage(Offset.zero & size, pixelRatio: kDesktopDpr);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode screenshot $name to PNG.');
    }
    await File('$shotDir/$name.png')
        .writeAsBytes(byteData.buffer.asUint8List());
    image.dispose();
  }

  /// Emit a grep-able per-phase marker so the suite log shows exactly which
  /// phase reached what — even when a later phase aborts the single
  /// testWidgets body.
  void phase(String label, [String? detail]) {
    // ignore: avoid_print
    print('E2E PHASE: $label${detail == null ? '' : ' — $detail'}');
  }
}
