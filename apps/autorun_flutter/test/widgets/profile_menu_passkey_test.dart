import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_keypair_repository.dart';
import '../test_helpers/test_keypair_factory.dart';

class _MockPasskeyService extends Mock implements PasskeyService {}

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('ProfileMenuWidget - Passkeys accessible via My Account', () {
    late ProfileKeypair keypair;
    late ProfileController profileController;
    late _MockPasskeyService mockPasskeyService;
    late _MockAccountController mockAccountController;
    late Account testAccount;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      if (profileController.profiles.isNotEmpty) {
        await profileController
            .setActiveProfile(profileController.profiles.first.id);
        await profileController.updateProfileUsername(
          profileId: profileController.profiles.first.id,
          username: 'testuser',
        );
      }

      mockPasskeyService = _MockPasskeyService();
      mockAccountController = _MockAccountController();

      testAccount = Account(
        id: 'account-123',
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    Future<void> pumpProfileMenu(
      WidgetTester tester, {
      PasskeyService? passkeyService,
    }) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);
      when(() => mockAccountController.refreshAccount(any()))
          .thenAnswer((_) async => testAccount);

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
                        passkeyService: passkeyService ?? mockPasskeyService,
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

    testWidgets('passkeys are NOT a separate menu item',
        (WidgetTester tester) async {
      await pumpProfileMenu(tester);

      // Passkeys should NOT be visible as a separate menu item
      expect(find.text('Passkeys'), findsNothing,
          reason:
              'Passkeys should be accessible via My Account > AccountProfileScreen, not a separate menu item');
    });

    testWidgets('menu has exactly 3 items (simplified structure)',
        (WidgetTester tester) async {
      await pumpProfileMenu(tester);

      // Should have exactly 3 menu items
      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('Switch Profile'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
        'tapping "My Account" navigates to AccountProfileScreen where passkeys are accessible',
        (WidgetTester tester) async {
      await pumpProfileMenu(tester);

      await tester.tap(find.text('My Account'));
      await tester.pumpAndSettle();

      // Should navigate to account profile screen (title is "My Identity")
      expect(find.text('My Identity'), findsOneWidget,
          reason:
              'Tapping "My Account" should navigate to AccountProfileScreen where passkeys section is visible');
    });
  });
}
