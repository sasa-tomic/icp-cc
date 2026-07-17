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

/// Resolve the repo workspace root by walking up from the running entrypoint.
///
/// `Platform.script` under `flutter test -d linux` is the APP entrypoint
/// (`apps/autorun_flutter/main.dart`), NOT the suite .dart file. Hard-coded
/// segment math breaks the moment the entrypoint changes (unit-test mode uses
/// the test file; integration mode uses main.dart; a future refactor may move
/// main.dart). Instead, walk up the directory tree from the entrypoint's
/// directory until we find the repo's `AGENTS.md` marker — that's the
/// authoritative repo root regardless of which entrypoint launched the test.
String _resolveRepoRoot() {
  var dir = Directory(
      File(Platform.script.toFilePath()).parent.path).absolute;
  for (var i = 0; i < 12; i++) {
    if (File('${dir.path}/AGENTS.md').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break; // filesystem root
    dir = parent;
  }
  throw StateError(
    'E2EDriver: could not find AGENTS.md walking up from '
    '"${File(Platform.script.toFilePath()).parent.path}". '
    'The e2e harness must run inside the icp-cc repo checkout.',
  );
}

/// Drives the REAL app on either surface.
///
/// Construct once per suite, then [boot] once, run many phases (resetAppState
/// + [remount] between them). The driver never rebuilds the native bundle —
/// [remount] is a cheap in-process `pumpWidget(KeypairApp())` reboot (~1–2s).
class E2EDriver {
  E2EDriver({
    required this.surface,
    String? shotDir,
  }) : shotDir = shotDir ??
            '${_resolveRepoRoot()}/docs/specs/ux_screenshots/e2e';

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
    // Make off-target taps FATAL. The Flutter default is to emit a warning
    // then keep going — which silently passes a test whose `tap()` missed the
    // widget (real UX bug). For e2e we want every tap to actually hit the
    // intended target; otherwise the assertion that follows is meaningless.
    WidgetController.hitTestWarningShouldBeFatal = true;
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
  ///
  /// Matches the wizard's close button by its `Close setup` tooltip — NOT by
  /// `Icons.close`, because `Icons.close` is also used by other on-screen
  /// widgets (getting-started card, contextual tips, search bars) and the
  /// `.first` of those is off-target when the wizard overlays them.
  Future<void> dismissWizard(WidgetTester tester) async {
    final closeBtn = find.byTooltip('Close setup');
    var guard = 0;
    while (!present(closeBtn, tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    if (present(closeBtn, tester)) {
      await tester.tap(closeBtn);
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

  /// Dismiss any transient overlays (SnackBar, open dialogs/menus) that would
  /// absorb taps meant for the underlying widget tree (AppBar actions, the
  /// back button, FABs, etc.).
  ///
  /// SnackBars from a prior phase often linger across flow boundaries and sit
  /// in the Material Overlay — `tester.tap(find.byTooltip(...))` then derives
  /// an offset whose hit-test is intercepted by the overlay's
  /// AbsorbPointer/IgnorePointer chain, surfacing as a `hitTestWarning` /
  /// `warnIfMissed` failure now that the harness makes those fatal.
  ///
  /// SnackBars with an action button (e.g. the download-flow "Run" action)
  /// stay open MUCH longer than the default 4s — the action button holds
  /// them on screen until tapped. So we explicitly tap any SnackBar action
  /// first, then pump past the dismiss animation.
  ///
  /// NOTE: deliberately bounded pumps (NOT `pumpAndSettle`) — the real FFI's
  /// Argon2id spinner and pending marketplace fetches animate forever, so
  /// `pumpAndSettle` would never return.
  /// Dismiss any SnackBar-with-action that would otherwise absorb taps meant
  /// for the underlying widget tree.
  ///
  /// SnackBars from a prior phase often linger across flow boundaries and sit
  /// in the Material Overlay — `tester.tap(find.byTooltip(...))` then derives
  /// an offset whose hit-test is intercepted by the overlay's
  /// AbsorbPointer/IgnorePointer chain, surfacing as a `hitTestWarning` /
  /// `warnIfMissed` failure now that the harness makes those fatal.
  ///
  /// SnackBars with an action button (e.g. the download-flow "Run" action)
  /// stay open MUCH longer than the default 4s — the action button holds
  /// them on screen until tapped. We tap the action to dismiss immediately.
  ///
  /// IMPLEMENTATION NOTES:
  /// - We use `warnIfMissed: false` because the matched `SnackBarAction` may
  ///   be mid-animation (fading out) and have no on-stage geometry. Treating
  ///   "the dismiss tap didn't land" as fatal here is wrong: it's a best-effort
  ///   cleanup, not a behavioral assertion.
  /// - We prefer `ScaffoldMessenger.removeCurrentSnackBar()` (the explicit
  ///   Material API) when a Scaffold context is available — it's atomic and
  ///   doesn't depend on hit-testing at all. The tap path is the fallback.
  ///
  /// IMPORTANT: this helper is intentionally MINIMAL. It does NOT close
  /// modal bottom sheets, dialogs, or routes — those have to be closed by
  /// the suite that opened them (the suite knows the right gesture:
  /// drag-down for a sheet, Esc for a popup menu, `pageBack` for a route).
  /// A blanket "dismiss everything" helper that auto-closes routes is a
  /// footgun: it pops the actual navigation stack and breaks later
  /// `pageBack` calls (we hit this exact regression in the mock-keyring
  /// suite).
  ///
  /// NOTE: deliberately NOT `pumpAndSettle` — the real FFI's Argon2id
  /// spinner and pending marketplace fetches animate forever.
  Future<void> dismissOverlays(WidgetTester tester) async {
    // Preferred path: atomic, no hit-test dependency. Scaffold always provides
    // a ScaffoldMessenger ancestor, so .of() resolves without throwing when a
    // Scaffold is on stage.
    final scaffoldEl = find.byType(Scaffold).evaluate().firstOrNull;
    if (scaffoldEl != null) {
      ScaffoldMessenger.of(scaffoldEl).removeCurrentSnackBar();
    }
    await tester.pump(const Duration(milliseconds: 200));

    // Fallback: tap the SnackBarAction's Text to dismiss (best-effort).
    final sbAction = find.byType(SnackBarAction);
    if (present(sbAction, tester)) {
      final actionLabel = find.descendant(
          of: sbAction, matching: find.byType(Text));
      if (present(actionLabel, tester)) {
        await tester.tap(actionLabel.first, warnIfMissed: false);
      } else {
        await tester.tap(sbAction.first, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Real-time wait so any timer-based SnackBar (no action) can clear on
    // its own wall-clock schedule — `pump(Duration)` advances the binding
    // clock only, which doesn't fire SnackBar's dart:async Timer.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 200));
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
