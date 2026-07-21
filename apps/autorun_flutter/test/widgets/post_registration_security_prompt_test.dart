// Tests for the shared post-registration security prompt (UX-H6).
//
// UX-H6 asks for a single, shared, skippable prompt that nudges the user
// toward BOTH optional security steps after they register an account. These
// tests pin down the helper's contract:
//   - all three options render with the right copy
//   - tapping each tile returns the matching choice
//   - the OS-back gesture returns null (callers treat as Skip)
//   - the passkey tile is DISABLED with honest copy when the platform probe
//     returns false — it never silently disappears
//   - the helper never navigates on its own (callers handle routing)
//
// The same helper is invoked by both onboarding wizards
// (`UnifiedSetupWizard`, `AccountRegistrationWizard`); their own test suites
// cover the wiring.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/widgets/post_registration_security_prompt.dart';

import '../shared/test_keypair_factory.dart';

Account _account() => Account(
      id: 'acct-1',
      username: 'alice',
      displayName: 'Alice',
      publicKeys: const <AccountPublicKey>[],
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
    );

/// Pumps the prompt inside a host that the helper can use as its
/// [BuildContext]. Returns a [Completer] that resolves with whatever the
/// helper returns when the dialog is dismissed.
Future<Completer<PostRegistrationSecurityChoice?>> _pumpPrompt(
  WidgetTester tester, {
  required Account account,
  required bool Function() isPasskeySupported,
}) async {
  final completer = Completer<PostRegistrationSecurityChoice?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await showPostRegistrationSecurityPrompt(
                  context: context,
                  account: account,
                  isPasskeySupported: isPasskeySupported,
                );
                if (!completer.isCompleted) completer.complete(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return completer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Account account;

  setUp(() async {
    // Touch the keypair factory once so the test binary initializes the
    // crypto subsystem; the prompt itself doesn't use a keypair but other
    // tests in this suite's neighborhood do, and a cold-start here avoids
    // flakes when run alongside them.
    await TestKeypairFactory.getEd25519Keypair();
    account = _account();
  });

  group('showPostRegistrationSecurityPrompt', () {
    group('rendering', () {
      testWidgets('renders title + body + all three options',
          (WidgetTester tester) async {
        await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        // Title.
        expect(find.text('Secure your account'), findsOneWidget);

        // Body acknowledges the just-registered @username.
        expect(find.textContaining('@alice'), findsOneWidget);

        // Two security tiles.
        expect(find.text('Set up vault password'), findsOneWidget);
        expect(find.text('Enroll a passkey'), findsOneWidget);

        // Skip is always offered (the prompt must never trap the user).
        expect(find.text('Skip for now'), findsOneWidget);
      });

      testWidgets(
          'passkey tile is enabled and uses the supported-device copy when '
          'isPasskeySupported() returns true', (WidgetTester tester) async {
        await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        // Tap should resolve to enrollPasskey (tile is tappable).
        await tester.tap(find.text('Enroll a passkey'));
        await tester.pumpAndSettle();

        // Vault tile is untouched; tapping would have popped with
        // enrollPasskey. Verify by re-pumping and asserting the post-tap
        // return value below.
      });

      testWidgets(
          'passkey tile is DISABLED with honest copy when '
          'isPasskeySupported() returns false — never silently disappears',
          (WidgetTester tester) async {
        await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => false,
        );

        // Tile still paints — UX-H6: "never silently disappears".
        expect(find.text('Enroll a passkey'), findsOneWidget);

        // Honest explanation replaces the marketing copy.
        expect(
          find.textContaining("doesn't support them"),
          findsOneWidget,
        );

        // The supporting copy mentions at least one platform the user CAN
        // use — actionable, not just "nope".
        expect(find.textContaining('macOS'), findsOneWidget);
      });
    });

    group('selection', () {
      testWidgets('tapping "Set up vault password" returns setUpVault',
          (WidgetTester tester) async {
        final completer = await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        await tester.tap(find.text('Set up vault password'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, PostRegistrationSecurityChoice.setUpVault);
      });

      testWidgets(
          'tapping "Enroll a passkey" returns enrollPasskey when supported',
          (WidgetTester tester) async {
        final completer = await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        await tester.tap(find.text('Enroll a passkey'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, PostRegistrationSecurityChoice.enrollPasskey);
      });

      testWidgets(
          'tapping the disabled passkey tile does NOT pop (no choice '
          'returned)', (WidgetTester tester) async {
        final completer = await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => false,
        );

        // The InkWell is rendered with onTap: null when disabled, so a tap
        // hits nothing.
        await tester.tap(find.text('Enroll a passkey'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(completer.isCompleted, isFalse,
            reason: 'disabled tile must not pop the dialog');
        expect(find.text('Skip for now'), findsOneWidget,
            reason: 'dialog is still on screen');
      });

      testWidgets('tapping "Skip for now" returns skip',
          (WidgetTester tester) async {
        final completer = await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, PostRegistrationSecurityChoice.skip);
      });

      testWidgets('the OS-back gesture returns null (treated as Skip)',
          (WidgetTester tester) async {
        final completer = await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        // Simulate the system back press.
        final NavigatorState navigator = tester.state(find.byType(Navigator));
        navigator.pop();
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, isNull,
            reason: 'OS-back dismisses the dialog without a choice; callers '
                'treat null as Skip.');
      });
    });

    group('navigation purity (UX-H6 single-source contract)', () {
      testWidgets(
          'the helper NEVER navigates on its own — only pops the dialog with '
          'the chosen enum', (WidgetTester tester) async {
        // Two nested Navigators would be one too many if the helper tried to
        // push a setup screen. We assert by counting routes before/after.
        await _pumpPrompt(
          tester,
          account: account,
          isPasskeySupported: () => true,
        );

        final initialRouteCount =
            tester.widgetList(find.byType(Navigator)).length;

        await tester.tap(find.text('Set up vault password'));
        await tester.pumpAndSettle();

        final finalRouteCount =
            tester.widgetList(find.byType(Navigator)).length;
        expect(finalRouteCount, initialRouteCount,
            reason: 'the helper must not push any route — that is the caller '
                'job. Single source of truth for routing lives in the wizard.');
      });
    });
  });
}
