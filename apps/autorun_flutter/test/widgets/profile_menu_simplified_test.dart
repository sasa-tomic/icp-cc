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
      testWidgets('menu shows exactly 3 core items (with account)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        // Count visible menu items (ListTile widgets)
        final menuTiles = find.descendant(
          of: find.byType(Column).first,
          matching: find.byType(ListTile),
        );

        final tileCount = menuTiles.evaluate().length;

        // Expect exactly 3 items
        expect(tileCount, equals(3),
            reason:
                'Profile menu should show exactly 3 items for simplified UX. '
                'Found $tileCount items.');
      });

      testWidgets('menu shows exactly 3 core items (without account)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Count visible menu items (ListTile widgets)
        final menuTiles = find.descendant(
          of: find.byType(Column).first,
          matching: find.byType(ListTile),
        );

        final tileCount = menuTiles.evaluate().length;

        expect(tileCount, equals(3),
            reason: 'Profile menu should show exactly 3 items even without '
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
      testWidgets('"Switch Profile" is now a menu item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Should have "Switch Profile" as a menu item
        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible as a menu item');
      });
    });

    group('Unified Account menu item', () {
      testWidgets(
          'shows "My Account" with @username subtitle for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible for users with account');
        expect(find.text('@testuser'), findsOneWidget,
            reason: 'Should show @username as subtitle for users with account');
      });

      testWidgets(
          'shows "My Account" with registration prompt subtitle for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible for users without account');
        expect(find.text('Register to publish scripts'), findsOneWidget,
            reason: 'Should explain purpose of registration');
      });

      testWidgets('does NOT show separate "My Identity" item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('My Identity'), findsNothing,
            reason: '"My Identity" should be merged into "My Account"');
      });

      testWidgets('does NOT show separate "Register Username" item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Register Username'), findsNothing,
            reason: '"Register Username" should be replaced by "My Account"');
      });

      testWidgets(
          'does NOT show separate "Passkeys" item (accessible via My Account)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsNothing,
            reason:
                '"Passkeys" should be accessible via AccountProfileScreen, not a separate menu item');
      });

      testWidgets('shows "Settings"', (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Settings'), findsOneWidget,
            reason: '"Settings" should always be visible');
      });

      testWidgets('shows "Switch Profile"', (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible');
      });
    });

    group('Switch Profile functionality', () {
      testWidgets('Switch Profile opens profile switcher sheet',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Find and tap "Switch Profile"
        final switchProfileTile =
            find.widgetWithText(ListTile, 'Switch Profile');
        expect(switchProfileTile, findsOneWidget);

        await tester.tap(switchProfileTile);
        await tester.pumpAndSettle();

        // Should show the Switch Profile sheet
        expect(find.text('Switch Profile'), findsWidgets,
            reason:
                'Tapping "Switch Profile" should open a sheet with profile switching options');
      });
    });
  });
}
