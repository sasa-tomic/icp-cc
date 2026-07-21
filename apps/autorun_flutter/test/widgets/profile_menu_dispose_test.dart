import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

/// Regression coverage for **UX-PMD-1** — use-after-dispose in
/// `ProfileMenuWidget._showManageProfilesSheet`'s `onCreateProfile` closure.
///
/// The closure captures `_ProfileMenuWidgetState.this` and dereferences
/// `context` AFTER the State has been disposed. Repro path:
///
///   1. Open profile menu (a `showModalBottomSheet` route).
///   2. Tap "Switch Profile" → `_handleAction(manageProfiles)`:
///      `Navigator.of(context).pop()` closes the menu, then
///      `_showManageProfilesSheet()` opens a second sheet (capturing the
///      now-closing State's `this` in the `onCreateProfile` closure).
///   3. Pump past the menu's exit animation → `_ProfileMenuWidgetState` is
///      disposed (the menu route is removed from the navigator).
///   4. Tap "Create New Profile" inside the manage sheet → fires
///      `onCreateProfile`, which does `Navigator.of(context).pop()` +
///      `await _showCreateProfileDialog()` (also `Navigator.of(context)`).
///      The disposed State's `context` is deactivated → assertion error
///      "Looking up a deactivated widget's ancestor is unsafe."
///
/// Before the fix: this test fails with that assertion error. After the
/// fix (capture `NavigatorState` before the await boundary, route through
/// it from the closure): the wizard pushes cleanly with no exception.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('UX-PMD-1: create profile via manage sheet', () {
    late ProfileController profileController;
    late MockPasskeyService mockPasskeyService;
    late MockAccountController mockAccountController;

    setUp(() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      profileController = await buildProfileController(keypairs: [keypair]);
      mockPasskeyService = MockPasskeyService();
      mockAccountController = MockAccountController();

      // An active account tile makes "Switch Profile" route to the manage
      // sheet (single-profile branch).
      await profileController.updateProfileUsername(
        profileId: profileController.profiles.first.id,
        username: 'testuser',
      );
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => buildTestAccount());
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
    });

    testWidgets(
        'tapping "Create New Profile" after the menu has finished closing '
        'does NOT throw use-after-dispose', (WidgetTester tester) async {
      // Force the wizard's readiness probe to "ready" so it can mount
      // without a real Secret Service (we don't actually complete the
      // wizard — we only need it to push without throwing).
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await pumpProfileMenuHost(
        tester,
        profileController: profileController,
        accountController: mockAccountController,
        passkeyService: mockPasskeyService,
      );

      // 1. Tap "Switch Profile" — opens the manage sheet. The menu's
      //    pop is scheduled; the manage sheet is pushed on top.
      await tester.tap(find.text('Switch Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Create New Profile'), findsOneWidget,
          reason: 'Manage sheet must be open with the Create New Profile '
              'tile visible.');

      // 2. Pump past the menu's exit animation so the original
      //    `_ProfileMenuWidgetState` is definitely disposed. The default
      //    Material bottom-sheet transition is ~250ms; pump 1s to be safe.
      //    Repeating pumps also drains any pending microtasks queued by the
      //    closure's `Navigator.of(context).pop()` + `_showCreateProfileDialog`.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));

      // 3. Tap "Create New Profile" — fires the onCreateProfile closure.
      //    The closure captures the (now-disposed) State's `this`. Without
      //    the fix, `Navigator.of(context)` inside the closure throws.
      await tester.tap(find.text('Create New Profile'));

      // Drive the post-tap async chain: the closure awaits
      // `_showCreateProfileDialog`, which pushes the wizard. Settle so
      // the wizard route reaches the tree. (No FFI is involved at this
      // stage — `_handleCreate` hasn't fired.)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // 4. Assert the wizard pushed cleanly. Before the fix, this fails
      //    because the closure threw on the disposed context.
      expect(find.byType(UnifiedSetupWizard), findsOneWidget,
          reason: 'The UnifiedSetupWizard must push from the manage sheet '
              'without throwing use-after-dispose.');

      // 5. Drain any pending exception so the test reds on a real error.
      //    `takeException()` returns null if nothing was captured, which we
      //    then ignore; otherwise we rethrow to surface the failure.
      // ignore: avoid_catches_without_on_clauses
      final dynamic exception = tester.takeException();
      expect(exception, isNull,
          reason: 'No FlutterError should be raised when the manage sheet '
              'opens the create-profile wizard. UX-PMD-1 regression.');
    });
  });
}
