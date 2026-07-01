import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/fake_secure_keypair_repository.dart';
import '../shared/test_keypair_factory.dart';

class _MockPasskeyService extends Mock implements PasskeyService {}

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('Profile menu first-run (UX-B1)', () {
    late ProfileKeypair keypair;
    late _MockAccountController mockAccountController;
    late _MockPasskeyService mockPasskeyService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      mockAccountController = _MockAccountController();
      mockPasskeyService = _MockPasskeyService();
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
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

    Future<void> pumpMenu(
      WidgetTester tester,
      ProfileController profileController,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (_) => ProfileMenuWidget(
                        profileController: profileController,
                        accountController: mockAccountController,
                        passkeyService: mockPasskeyService,
                      ),
                    );
                  },
                  child: const Text('Open Menu'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'first-run: the My Account tile is rendered and routes to profile '
        'creation instead of being a silent no-op', (tester) async {
      final profileController = await buildEmptyController();
      expect(profileController.profiles, isEmpty);
      expect(profileController.activeProfile, isNull);

      await pumpMenu(tester, profileController);

      // The tile is present even with no active profile ...
      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('Create a profile to get started'), findsOneWidget);

      // ... and tapping it opens the creation surface (no longer a no-op).
      await tester.tap(find.text('My Account'));
      await tester.pumpAndSettle();

      expect(find.text('Create Profile'), findsOneWidget,
          reason: 'first-run My Account tap must open profile creation');
    });

    testWidgets(
        'with an active profile the first-run CTA is not shown '
        '(first-run path is correctly scoped)', (tester) async {
      final profileController = await buildControllerWithProfile();
      expect(profileController.profiles, isNotEmpty);
      expect(profileController.activeProfile, isNotNull);

      await pumpMenu(tester, profileController);

      // With an active profile present, the first-run CTA is not shown.
      expect(find.text('Create a profile to get started'), findsNothing);
      expect(find.text('My Account'), findsOneWidget);
    });
  });
}
