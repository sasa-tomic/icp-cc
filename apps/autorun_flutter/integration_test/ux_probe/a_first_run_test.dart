// Flow A — First-run (NEW USER).  (round-2 empirical probes)
//
// Asserts:
//  - UnifiedSetupWizard is presented when no profile exists (B3 first-run gate).
//  - Dismissing it lands on an empty Scripts screen as Guest (WU-1 dead-end).
//  - Completing the wizard on a bare Linux desktop SURFACES a secure-storage
//    error (NEW-2): FlutterSecureStorage -> libsecret -> PlatformException
//    "Failed to unlock the keyring" (no secret service running).
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/a_first_run_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A1: first-run presents UnifiedSetupWizard (B3 gate)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    int guard = 0;
    while (!present(find.text('Get Started'), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    await shot(binding, '01_first_run_wizard', tester);

    expect(present(find.text('Get Started'), tester), isTrue,
        reason: 'B3 first-run gate: UnifiedSetupWizard must show when no profile.');
    expect(present(find.text('How should we call you?'), tester), isTrue,
        reason: 'Wizard display-name field present.');
    expect(present(find.text('Create Your Profile'), tester), isTrue,
        reason: 'Wizard heading present.');
  });

  testWidgets('A2: dismissing wizard -> empty state, NO identity (WU-1 dead-end)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    int guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    // Wizard AppBar leading is an Icons.close IconButton.
    await tester.tap(find.byIcon(Icons.close).first);
    // Bounded pumps only: pumpAndSettle never returns here because the Scripts
    // screen kicks off marketplace fetches against the (unreachable) prod URL.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot(binding, '02_empty_state_no_profile', tester);

    // We now sit on the Scripts screen with NO profile (the avatar has no
    // identity). WU-1: the surface still offers identity-dependent CTAs
    // (New Script) even though no keypair exists — a dead-end.
    final guestShown = present(find.text('Guest'), tester);
    final hasNewScriptCta = present(find.text('New Script'), tester) ||
        present(find.widgetWithIcon(FloatingActionButton, Icons.add), tester) ||
        present(find.byTooltip('New Script'), tester);
    // ignore: avoid_print
    print('A2_WU1: guestShown=$guestShown hasNewScriptCta=$hasNewScriptCta');
    expect(hasNewScriptCta, isTrue,
        reason: 'WU-1: empty Scripts screen offers "New Script" (and other '
            'identity-dependent CTAs) even though no profile/keypair exists.');
    expect(guestShown, isFalse,
        reason: 'Avatar has no identity text yet (no profile was ever created).');
  });

  testWidgets('A3: complete wizard -> secure-storage ERROR on bare Linux (NEW-2)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    int guard = 0;
    while (!present(find.text('How should we call you?'), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    await tester.enterText(find.byType(TextFormField).first, 'UX Tester');
    await tester.pump();
    // The form's submit button is the FilledButton labelled 'Get Started'
    // (the AppBar title is a Text, not a FilledButton, so this is unique).
    final submit = find.widgetWithText(FilledButton, 'Get Started');
    expect(present(submit, tester), isTrue);
    await tester.ensureVisible(submit);
    await tester.tap(submit);

    // Wait for the secure-storage error banner (Icons.error_outline) OR an
    // unexpected success ('Start Exploring'). NEW-2 predicts the error.
    bool sawError = false;
    bool sawSuccess = false;
    String? bannerText;
    for (int i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (present(find.byIcon(Icons.error_outline), tester)) {
        sawError = true;
        final t = find.descendant(
            of: find.byIcon(Icons.error_outline),
            matching: find.byType(Text));
        // The banner Text is a sibling, not a descendant; fall back to scanning.
        bannerText = _scanForBanner(tester);
        break;
      }
      if (present(find.text('Start Exploring'), tester) ||
          present(find.text('Success!'), tester)) {
        sawSuccess = true;
        break;
      }
    }
    await shot(binding, '03_wizard_success', tester);

    // ignore: avoid_print
    print('A3_NEW2_RESULT: sawError=$sawError sawSuccess=$sawSuccess bannerText=$bannerText');

    // NEW-2 expectation: on this bare Linux box the wizard MUST error.
    expect(sawError, isTrue,
        reason: 'NEW-2: profile create must surface the libsecret error on a '
            'minimal Linux desktop (no secret service).');
    expect(sawSuccess, isFalse,
        reason: 'Profile creation cannot succeed without a secret service.');
  });
}

String? _scanForBanner(WidgetTester tester) {
  String? found;
  tester.widgetList(find.byType(Text)).forEach((w) {
    final data = (w as Text).data ?? '';
    if (data.toLowerCase().contains('keyring') ||
        data.toLowerCase().contains('libsecret') ||
        data.toLowerCase().contains('unlock')) {
      found = data;
    }
  });
  return found;
}
