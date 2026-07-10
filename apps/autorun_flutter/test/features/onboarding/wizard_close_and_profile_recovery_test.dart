import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/main.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/profile_setup_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

/// IH-9 / UXR-8: the first-run wizard's close button must be accessible (have a
/// tooltip), and dismissing it without creating a profile must NOT strand the
/// user — the wizard must not force-reappear on every restart, and profile
/// creation must stay reachable via a persistent affordance.
///
/// Every test pushes the wizard through the same `presentSetupWizard` /
/// `showFirstRunSetupIfNeeded` entry points the shell uses (the proven gate-test
/// seam), backed by a real [ProfileController] over an in-memory repository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The first-run gate now reads SharedPreferences (to honor a remembered
  // dismissal). Every test must initialize the mock plugin, otherwise the
  // `SharedPreferences.getInstance()` platform-channel call hangs forever.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Builds an empty real [ProfileController] (no profiles) backed by the
  /// shared in-memory fake repository — real keypairs, no crypto mocked.
  Future<ProfileController> buildEmptyController() async {
    final repository = FakeSecureKeypairRepository(<ProfileKeypair>[]);
    final controller =
        ProfileController(profileRepository: repository.profileRepository);
    await controller.ensureLoaded();
    return controller;
  }

  group('IH-9 wizard close a11y', () {
    testWidgets('the close button exposes an accessible tooltip',
        (tester) async {
      final profileController = await buildEmptyController();
      final accountController = AccountController();

      // Push the wizard via the shell's own entry point (the gate-test seam).
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showFirstRunSetupIfNeeded(
                    context: context,
                    profileController: profileController,
                    accountController: accountController,
                  ),
                  child: const Text('Start App'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start App'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedSetupWizard), findsOneWidget);
      // The close IconButton now carries a tooltip → it is no longer an empty
      // `button ""` in the semantics tree.
      expect(find.byTooltip('Close setup'), findsOneWidget);
    });
  });

  group('IH-9 no-profile recovery', () {
    late ProfileController profileController;

    setUp(() async {
      // Real keypair (unused for creation here, but kept honest — see
      // test/shared/AGENTS.md: never seed fake keys).
      await TestKeypairFactory.getEd25519Keypair();
      profileController = await buildEmptyController();
    });

    testWidgets(
        'dismissing the wizard once suppresses it on the next first-run '
        'gate check (no restart wizard loop)', (tester) async {
      final accountController = AccountController();
      expect(profileController.profiles, isEmpty);

      // --- First launch: the wizard is presented. ---
      bool? firstShown;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showFirstRunSetupIfNeeded(
                      context: context,
                      profileController: profileController,
                      accountController: accountController,
                    ).then((shown) => firstShown = shown);
                  },
                  child: const Text('Start App'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start App'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedSetupWizard), findsOneWidget);
      // Dismiss without creating a profile (the "browse as guest" choice).
      await tester.tap(find.byTooltip('Close setup'));
      await tester.pumpAndSettle();
      expect(firstShown, isTrue);

      // --- Second launch: the gate must respect the dismissal. ---
      final secondContext = tester.element(find.text('Start App'));
      final secondShown = await showFirstRunSetupIfNeeded(
        context: secondContext,
        profileController: profileController,
        accountController: accountController,
      );

      expect(secondShown, isFalse,
          reason: 'a dismissed wizard must not force-reappear on relaunch');
      expect(find.byType(UnifiedSetupWizard), findsNothing);

      // Root-cause proof: the dismissal was persisted to SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('first_run_wizard_dismissed'), isTrue);
    });

    testWidgets(
        'the persistent "Set up profile" affordance is present and re-opens '
        'the wizard when tapped', (tester) async {
      final accountController = AccountController();
      expect(profileController.profiles, isEmpty);

      // Host mimicking the shell: the chip is wired to the real
      // presentSetupWizard entry point (the same one the shell uses).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ProfileSetupChip(
                  onSetUp: () => presentSetupWizard(
                    context: context,
                    profileController: profileController,
                    accountController: accountController,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The affordance is present and labelled (discoverable, not stranded).
      expect(find.byType(ProfileSetupChip), findsOneWidget);
      expect(find.text('Set up profile'), findsOneWidget);

      // Tapping it re-enters setup — the full wizard comes back.
      await tester.tap(find.byType(ProfileSetupChip));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedSetupWizard), findsOneWidget);
      expect(find.text('Create Your Profile'), findsOneWidget);
    });
  });
}
