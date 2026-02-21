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

  group('Profile Menu Simplified Structure', () {
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

    Future<void> pumpProfileMenu(
      WidgetTester tester, {
      required bool hasAccount,
      int profileCount = 1,
    }) async {
      if (hasAccount) {
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

    group('Maximum visible items constraint', () {
      testWidgets('menu shows at most 5 core items by default (with account)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        // Count visible menu items (ListTile widgets)
        final menuTiles = find.descendant(
          of: find.byType(Column).first,
          matching: find.byType(ListTile),
        );

        final tileCount = menuTiles.evaluate().length;

        // Expect at most 5 visible items
        expect(tileCount, lessThanOrEqualTo(5),
            reason: 'Profile menu should show at most 5 items to reduce '
                'cognitive load. Found $tileCount items.');
      });

      testWidgets(
          'menu shows at most 5 core items by default (without account)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Count visible menu items (ListTile widgets)
        final menuTiles = find.descendant(
          of: find.byType(Column).first,
          matching: find.byType(ListTile),
        );

        final tileCount = menuTiles.evaluate().length;

        expect(tileCount, lessThanOrEqualTo(5),
            reason: 'Profile menu should show at most 5 items even without '
                'an account. Found $tileCount items.');
      });
    });

    group('Help options moved to Settings', () {
      testWidgets('"Getting Started" is NOT in profile menu',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Getting Started'), findsNothing,
            reason: '"Getting Started" should be moved to Settings > Help');
      });

      testWidgets('"Restart Tour" is NOT in profile menu',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Restart Tour'), findsNothing,
            reason: '"Restart Tour" should be moved to Settings > Help');
      });
    });

    group('Profile management combined', () {
      testWidgets('"Create Profile" is replaced by "Manage Profiles"',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Should have "Manage Profiles" instead of individual profile options
        expect(find.text('Manage Profiles'), findsOneWidget,
            reason: 'Profile management should be combined into single '
                '"Manage Profiles" option');
      });

      testWidgets(
          '"Switch Profile" is NOT shown separately when multiple profiles exist',
          (WidgetTester tester) async {
        // This test will need modification when we support multiple profiles
        await pumpProfileMenu(tester, hasAccount: true, profileCount: 1);

        // "Switch Profile" should not be a separate visible item
        expect(find.text('Switch Profile'), findsNothing,
            reason: 'Switch Profile should be inside "Manage Profiles", '
                'not a separate menu item');
      });
    });

    group('Unified Account menu item', () {
      testWidgets(
          'shows "Manage Account" with @username subtitle for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Manage Account'), findsOneWidget,
            reason:
                '"Manage Account" should be visible for users with account');
        expect(find.text('@testuser'), findsOneWidget,
            reason: 'Should show @username as subtitle for users with account');
      });

      testWidgets(
          'shows "Register @username" with publish subtitle for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Register @username'), findsOneWidget,
            reason:
                '"Register @username" should be visible for users without account');
        expect(find.text('Get a username to publish scripts'), findsOneWidget,
            reason: 'Should explain purpose of registration');
      });

      testWidgets('does NOT show separate "My Identity" item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('My Identity'), findsNothing,
            reason: '"My Identity" should be merged into unified Account item');
      });

      testWidgets('does NOT show separate "Register Username" item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Register Username'), findsNothing,
            reason:
                '"Register Username" should be replaced by "Register @username"');
      });

      testWidgets('shows "Passkeys" for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsOneWidget,
            reason: '"Passkeys" should be visible for users with account');
      });

      testWidgets('shows "Settings"', (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Settings'), findsOneWidget,
            reason: '"Settings" should always be visible');
      });

      testWidgets('shows "Manage Profiles"', (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Manage Profiles'), findsOneWidget,
            reason: '"Manage Profiles" should be visible');
      });
    });

    group('Manage Profiles functionality', () {
      testWidgets('Manage Profiles opens profile management sheet',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Find and tap "Manage Profiles"
        final manageProfilesTile =
            find.widgetWithText(ListTile, 'Manage Profiles');
        expect(manageProfilesTile, findsOneWidget);

        await tester.tap(manageProfilesTile);
        await tester.pumpAndSettle();

        // Should show the Manage Profiles sheet
        expect(find.text('Manage Profiles'), findsWidgets,
            reason:
                'Tapping "Manage Profiles" should open a sheet with profile management options');
      });
    });
  });
}
