import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/utils/tech_terms.dart';
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

  group('Profile Menu Terminology Clarity', () {
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

    group('Clear terminology for Account management (unified)', () {
      testWidgets(
          'shows unified "Manage Account" for users with account with @username subtitle',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Manage Account'), findsOneWidget,
            reason:
                'Unified "Manage Account" item should be visible for users with account');

        expect(find.text('@testuser'), findsOneWidget,
            reason: 'Should show @username as subtitle');
      });

      testWidgets(
          'shows unified "Register @username" for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Register @username'), findsOneWidget,
            reason:
                'Unified "Register @username" item should be visible for users without account');
      });

      testWidgets(
          'shows helpful subtitle explaining registration is for publishing',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Get a username to publish scripts'), findsOneWidget,
            reason:
                'Subtitle should explain username is for publishing scripts');
      });
    });

    group('Legacy terminology removed', () {
      testWidgets('does NOT show separate "My Identity" item',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Identity'), findsNothing,
            reason: '"My Identity" should be merged into unified Account item');
      });

      testWidgets('does NOT show separate "Register Username" item',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Register Username'), findsNothing,
            reason:
                '"Register Username" should be replaced by "Register @username"');
      });
    });

    group('Other menu items remain unchanged', () {
      testWidgets('Passkeys label remains the same',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsOneWidget);
      });

      testWidgets('Passkeys menu item has explanatory tooltip',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        final passkeysTile = find.widgetWithText(ListTile, 'Passkeys');
        expect(passkeysTile, findsOneWidget);

        final tooltip = tester.widget<Tooltip>(
          find
              .ancestor(
                of: passkeysTile,
                matching: find.byType(Tooltip),
              )
              .first,
        );
        expect(tooltip.message, TechTerm.passkey.fullExplanation,
            reason:
                'Passkeys menu item should have tooltip explaining what passkeys are');
      });

      testWidgets('Settings label remains the same',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('Manage Profiles replaces individual profile options',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // "Manage Profiles" combines switch + create profile functionality
        expect(find.text('Manage Profiles'), findsOneWidget);
      });
    });
  });
}
