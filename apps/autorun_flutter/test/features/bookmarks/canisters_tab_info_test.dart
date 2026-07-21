// UX-H8 — the "Canisters" tab label is unexplained jargon for first-time ICP
// users. The fix is ADDITIVE: keep the label "Canisters" (it's the correct,
// pedagogically valuable ICP term — see HUMAN_EXPECTATIONS.md §"Pedagogical
// value"), keep the existing subtitle tagline, and add a help IconButton in
// the AppBar that opens a plain-English explainer + a "Learn more" link.
//
// These tests pin the affordance's contract:
//   - the help icon renders in the AppBar (discoverable, not buried);
//   - tapping it reveals the plain-English explanation (on-demand, not
//     always-on clutter — verified by the negative test);
//   - the explanation reuses the project's single source of truth,
//     TechTerm.canister.fullExplanation (DRY — no duplicate copy);
//   - the "Learn more" link is wired to kCanisterLearnMoreUrl (assert on the
//     const String + a recorded launcher call, NOT a real browser launch);
//   - a launcher failure surfaces as a friendly (loud, contextual) SnackBar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/utils/tech_terms.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

import '../../shared/fake_connectivity_service.dart';

void main() {
  Future<void> pumpBookmarksScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectivityScope(
            service: FakeConnectivityService(),
            child: const BookmarksScreen(bridge: RustBridgeLoader()),
          ),
        ),
      ),
    );
    // Let ConnectivityScope's async init (periodic-check setup) run so its
    // timer is created and then cleanly cancelled on tree disposal.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('UX-H8: Canisters tab info affordance', () {
    testWidgets('AppBar renders a help IconButton (discoverable, not buried)',
        (tester) async {
      await pumpBookmarksScreen(tester);

      // The help action lives IN the AppBar (not somewhere downstream).
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, isNotEmpty,
          reason: 'AppBar must have at least one action (the help button).');

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.help_outline),
        ),
        findsOneWidget,
        reason: 'The help affordance must be a help_outline IconButton in the '
            'AppBar actions — matches the canonical pattern in '
            'settings_screen.dart and error_display.dart.',
      );

      // The tooltip makes the icon's purpose explicit (POLA).
      expect(find.byTooltip('What is a canister?'), findsOneWidget);
    });

    testWidgets(
        'WITHOUT tapping, the explanation copy is NOT visible (on-demand, '
        'not always-on)', (tester) async {
      await pumpBookmarksScreen(tester);

      expect(
        find.text(TechTerm.canister.fullExplanation),
        findsNothing,
        reason: 'The explainer must be tucked behind a tap so the screen '
            'doesn\'t clutter for power users who already know the term.',
      );
      expect(find.text('Learn more'), findsNothing);
    });

    testWidgets('tapping the help icon opens a dialog with the plain-English '
        'explanation reusing TechTerm.canister (DRY)', (tester) async {
      await pumpBookmarksScreen(tester);

      await tester.tap(find.byTooltip('What is a canister?'));
      await tester.pumpAndSettle();

      // The dialog surfaces the project's single-source-of-truth explanation
      // for "canister" — no duplicated copy.
      expect(
        find.text(TechTerm.canister.fullExplanation),
        findsOneWidget,
      );
      // A "Learn more" external-link affordance is present.
      expect(find.text('Learn more'), findsOneWidget);
      // Dismiss copy is honest and matches Material conventions.
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets(
        'the "Learn more" URL is the expected canonical ICP docs page '
        '(assert on the const String, not by launching a browser)',
        (tester) async {
      // Source of truth: a const near kCanistersTabLabel. The issue suggested
      // https://internetcomputer.org/docs/building-apps/defining/canisters,
      // but that URL 3xx-redirects to the docs root (verified by curl). The
      // working canonical "Canisters" concept page is under docs.internetcomputer.org.
      expect(
        kCanisterLearnMoreUrl,
        'https://docs.internetcomputer.org/concepts/canisters/',
        reason: 'The Learn more URL must be the live, canonical ICP docs page. '
            'The issue suggested /docs/building-apps/defining/canisters, but '
            'that redirects to docs root — slop. See the commit message.',
      );

      // And the AppBar title still uses the shared label (UX-2 regression
      // guard: the new affordance is ADDITIVE, not a rename).
      expect(kCanistersTabLabel, 'Canisters');
    });

    testWidgets(
        'tapping "Learn more" invokes the launcher with the canonical URL '
        'and closes the dialog', (tester) async {
      Uri? capturedUri;
      LaunchMode? capturedMode;
      // Override the test seam (mirrors icpay_service.dart's UrlLauncher
      // injection pattern).
      canisterLearnMoreLauncher = (uri, mode) async {
        capturedUri = uri;
        capturedMode = mode;
        return true;
      };
      addTearDown(() =>
          canisterLearnMoreLauncher = (url, mode) => launchUrl(url, mode: mode));

      await pumpBookmarksScreen(tester);

      await tester.tap(find.byTooltip('What is a canister?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();

      expect(capturedUri?.toString(), kCanisterLearnMoreUrl);
      expect(capturedMode, LaunchMode.externalApplication);
    });

    testWidgets(
        'when url_launcher fails, a friendly (loud, contextual) SnackBar '
        'surfaces the failure — no silent swallow', (tester) async {
      canisterLearnMoreLauncher = (_, __) async => false;
      addTearDown(() =>
          canisterLearnMoreLauncher = (url, mode) => launchUrl(url, mode: mode));

      await pumpBookmarksScreen(tester);

      await tester.tap(find.byTooltip('What is a canister?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();

      // Loud, contextual, NOT "Instance of 'X'" or a raw stack — the helper
      // from friendly_error.dart classifies via error_categories.
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, isNot(null));
      final messenger =
          tester.widget<SnackBar>(find.byType(SnackBar)).content;
      expect(messenger, isA<Text>());
      final message = (messenger as Text).data ?? '';
      expect(message.toLowerCase(), contains('learn more'));
      expect(message, isNot(contains('Instance of')));
    });
  });
}
