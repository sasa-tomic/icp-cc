// ignore_for_file: lines_longer_than_80_chars

/// Smoke test: the substrate fakes let the REAL app boot on Web and exercise
/// the smallest end-to-end path (boot → first-run wizard appears → dismiss).
///
/// Phase C Tier A gate. FAILS LOUDLY if the substrate is incomplete — this
/// is the canary for the full `suite_web_flows_test.dart` harness.
///
/// Run: `just e2e-web file=test/e2e_web/substrate_smoke_test.dart`
@TestOn('browser')
@Tags(['web'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart' as app;
import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import 'substrate/substrate.dart';

void main() {
  setUpAll(() {
    installSubstratePrefs();
    installSubstrateSecureStorage();
    installSubstrateHttp(defaultServer());
    installSubstratePathProvider();
    installSubstrateAppLinksSilencer();
    installSubstratePackageInfo();
  });

  testWidgets('substrate boots app + first-run wizard appears', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    // Make off-target taps FATAL (matches E2EDriver contract).
    WidgetController.hitTestWarningShouldBeFatal = true;

    await tester.pumpWidget(const app.KeypairApp());

    // Drive the unawaited async chain (ensureLoaded → first-run gate →
    // wizard) via runAsync. The substrate makes plugin round-trips succeed.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync<void>(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      if (find.byType(UnifiedSetupWizard).evaluate().isNotEmpty) break;
    }

    expect(find.byType(MaterialApp), findsOneWidget,
        reason: 'KeypairApp must mount a MaterialApp root on Web.');
    expect(find.byType(UnifiedSetupWizard), findsOneWidget,
        reason: 'Clean prefs + working secure storage must show the wizard.');

    // Dismiss the wizard by tapping its close button. This also unmounts the
    // CachedNetworkImage widgets (the wizard's example screenshots), stopping
    // flutter_cache_manager from scheduling further cleanup timers.
    final close = find.byTooltip('Close setup');
    for (var i = 0; i < 10 && find.byTooltip('Close setup').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(close, findsOneWidget,
        reason: 'Wizard must have a "Close setup" affordance.');
    await tester.tap(close);
    await tester.pump(const Duration(milliseconds: 500));

    // Verify the wizard actually went away — proves the dismiss path works
    // on the Web surface (cross-surface contract: same close affordance as
    // desktop).
    expect(find.byType(UnifiedSetupWizard), findsNothing,
        reason: 'Tapping "Close setup" must dismiss the wizard.');

    // Drain remaining animations so the binding's `_verifyInvariants` doesn't
    // trip on a pending frame callback.
    await tester.pump(const Duration(seconds: 1));
    // Fire flutter_cache_manager's `_scheduleCleanup` one-shot timer
    // (`cleanupRunMinInterval = Duration(seconds: 10)`). It's created when
    // the wizard mounts CachedNetworkImage for example screenshots;
    // without this the binding's `timersPending` invariant trips after the
    // test body.
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
