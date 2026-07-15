import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/main.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('First-run setup gate (UX-B3)', () {
    late ProfileKeypair keypair;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
    });

    Future<ProfileController> buildEmptyController() async {
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[]);
      final controller =
          ProfileController(profileRepository: repository.profileRepository);
      await controller.ensureLoaded();
      return controller;
    }

    Future<ProfileController> buildControllerWithProfile() async {
      final repository =
          FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      final controller =
          ProfileController(profileRepository: repository.profileRepository);
      await controller.ensureLoaded();
      if (controller.profiles.isNotEmpty) {
        await controller.setActiveProfile(controller.profiles.first.id);
      }
      return controller;
    }

    testWidgets(
        'first run (no profiles) shows the UnifiedSetupWizard before the app',
        (tester) async {
      final profileController = await buildEmptyController();
      expect(profileController.profiles, isEmpty);
      final accountController = AccountController();

      bool? gateShowed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  // Await the gate (W7-L5) instead of fire-and-forget `.then`:
                  // the gate Future only resolves when the wizard is popped, so
                  // awaiting removes the latent microtask-drain flake where the
                  // `gateShowed` assertion raced the Navigator-pop Future.
                  onPressed: () async {
                    gateShowed = await showFirstRunSetupIfNeeded(
                      context: context,
                      profileController: profileController,
                      accountController: accountController,
                    );
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

      // The orphaned wizard is now wired as the first-run gate.
      expect(find.byType(UnifiedSetupWizard), findsOneWidget);
      // The wizard's signature elements are visible to a first-run user.
      expect(find.text('Create Your Profile'), findsOneWidget);
      expect(find.text('Get Started'), findsWidgets);

      // Dismissing the wizard resolves the gate as "shown".
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(gateShowed, isTrue);
    });

    testWidgets(
        'returning user (profiles present) skips the wizard and proceeds '
        'straight to the app', (tester) async {
      final profileController = await buildControllerWithProfile();
      expect(profileController.profiles, isNotEmpty);
      final accountController = AccountController();

      bool? gateShowed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    gateShowed = await showFirstRunSetupIfNeeded(
                      context: context,
                      profileController: profileController,
                      accountController: accountController,
                    );
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

      expect(find.byType(UnifiedSetupWizard), findsNothing,
          reason: 'returning users must not see the first-run wizard');
      expect(gateShowed, isFalse);
    });
  });
}
