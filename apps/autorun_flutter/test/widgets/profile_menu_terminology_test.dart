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

  group('Profile Menu Terminology Clarity - Simplified V2', () {
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

    Future<void> pumpProfileMenuWithAccount(
      WidgetTester tester, {
      required bool hasAccount,
    }) async {
      if (hasAccount) {
        // Update profile with username to simulate having an account
        await profileController.updateProfileUsername(
          profileId: profileController.profiles.first.id,
          username: 'testuser',
        );
        when(() => mockAccountController.getAccountForProfile(any()))
            .thenAnswer((_) async => testAccount);
      }
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);

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

    group('Clear terminology for Account management', () {
      testWidgets(
          'shows "My Account" for users with account with @username subtitle',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Account'), findsOneWidget,
            reason:
                '"My Account" item should be visible for users with account');

        expect(find.text('@testuser'), findsOneWidget,
            reason: 'Should show @username as subtitle');
      });

      testWidgets(
          'shows "My Account" for users without account with registration prompt',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('My Account'), findsOneWidget,
            reason:
                '"My Account" item should be visible for users without account');
      });

      testWidgets(
          'shows helpful subtitle explaining registration is for publishing',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Register to publish scripts'), findsOneWidget,
            reason:
                'Subtitle should explain username is for publishing scripts');
      });
    });

    group('Legacy terminology removed', () {
      testWidgets('does NOT show "Manage Account" (replaced by "My Account")',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Manage Account'), findsNothing,
            reason: '"Manage Account" should be replaced by "My Account"');
      });

      testWidgets(
          'does NOT show "Register @username" (replaced by "My Account")',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Register @username'), findsNothing,
            reason: '"Register @username" should be replaced by "My Account"');
      });

      testWidgets('does NOT show separate "My Identity" item',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Identity'), findsNothing,
            reason: '"My Identity" should be merged into "My Account"');
      });

      testWidgets(
          'does NOT show "Manage Profiles" (replaced by "Switch Profile")',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Manage Profiles'), findsNothing,
            reason: '"Manage Profiles" should be replaced by "Switch Profile"');
      });
    });

    group('Simplified 3-item menu structure', () {
      testWidgets('has exactly 3 menu items', (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Account'), findsOneWidget);
        expect(find.text('Switch Profile'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets(
          'Passkeys are NOT a separate menu item (accessible via My Account)',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsNothing,
            reason:
                'Passkeys should be accessible via AccountProfileScreen, not a separate menu item');
      });

      testWidgets(
          'My Library is NOT a separate menu item (accessible via My Account)',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Library'), findsNothing,
            reason:
                'My Library should be accessible via other means, not a separate menu item');
      });

      testWidgets('Settings label remains the same',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('Switch Profile replaces Manage Profiles',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Switch Profile'), findsOneWidget);
      });
    });
  });
}
