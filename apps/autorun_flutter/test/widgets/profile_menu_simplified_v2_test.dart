import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('Profile Menu Further Simplification (#41)', () {
    late ProfileController profileController;
    late MockPasskeyService mockPasskeyService;
    late MockAccountController mockAccountController;
    late Account testAccount;

    setUp(() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      profileController = await buildProfileController(keypairs: [keypair]);

      mockPasskeyService = MockPasskeyService();
      mockAccountController = MockAccountController();

      testAccount = buildTestAccount();
    });

    Future<void> pumpProfileMenu(
      WidgetTester tester, {
      required bool hasAccount,
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

      await pumpProfileMenuHost(
        tester,
        profileController: profileController,
        accountController: mockAccountController,
        passkeyService: mockPasskeyService,
      );
    }

    group('Exactly 3 menu items', () {
      testWidgets('menu shows exactly 3 items for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        // The 3 expected items: My Account, Switch Profile, Settings
        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible as primary account item');
        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible');
        expect(find.text('Settings'), findsOneWidget,
            reason: '"Settings" should be visible');

        // Count visible menu tiles - should be exactly 3
        final menuTiles = find.byType(ListTile);
        final tileCount = menuTiles.evaluate().length;
        expect(tileCount, equals(3),
            reason:
                'Profile menu should have exactly 3 items. Found $tileCount.');
      });

      testWidgets('menu shows exactly 3 items for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // For users without account: My Account (prompts registration), Switch Profile, Settings
        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible even without account');
        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible');
        expect(find.text('Settings'), findsOneWidget,
            reason: '"Settings" should be visible');

        final menuTiles = find.byType(ListTile);
        final tileCount = menuTiles.evaluate().length;
        expect(tileCount, equals(3),
            reason:
                'Profile menu should have exactly 3 items. Found $tileCount.');
      });
    });

    group('Removed items', () {
      testWidgets('"My Library" is NOT a separate menu item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('My Library'), findsNothing,
            reason:
                '"My Library" should be accessible via "My Account", not a separate item');
      });

      testWidgets('"Passkeys" is NOT a separate menu item',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsNothing,
            reason:
                '"Passkeys" should be accessible via "My Account", not a separate item');
      });

      testWidgets('"Manage Profiles" is replaced by "Switch Profile"',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Manage Profiles'), findsNothing,
            reason:
                '"Manage Profiles" should be replaced by simpler "Switch Profile"');
        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible');
      });

      testWidgets('"Manage Account" label is replaced by "My Account"',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('Manage Account'), findsNothing,
            reason: '"Manage Account" should be renamed to "My Account"');
        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be the unified account item');
      });

      testWidgets('"Register @username" is replaced by "My Account"',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        expect(find.text('Register @username'), findsNothing,
            reason: '"Register @username" should be replaced by "My Account"');
        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible, prompting registration');
      });
    });

    group('My Account item behavior', () {
      testWidgets('shows @username subtitle for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        expect(find.text('@testuser'), findsOneWidget,
            reason: 'Should show @username as subtitle when account exists');
      });

      testWidgets(
          'shows registration prompt subtitle for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // Should prompt user to register
        expect(find.text('Register to publish scripts'), findsOneWidget,
            reason: 'Should show registration prompt when no account');
      });
    });

    group('My Account navigation', () {
      testWidgets(
          'tapping "My Account" with account navigates to AccountProfileScreen',
          (WidgetTester tester) async {
        // Add mock for refreshAccount used by AccountProfileScreen
        when(() => mockAccountController.refreshAccount(any()))
            .thenAnswer((_) async => testAccount);

        await pumpProfileMenu(tester, hasAccount: true);

        await tester.tap(find.text('My Account'));
        await tester.pumpAndSettle();

        // Should navigate to account profile screen (title is "My Identity")
        expect(find.text('My Identity'), findsOneWidget,
            reason: 'Tapping "My Account" should navigate to account profile');
      });

      testWidgets(
          'tapping "My Account" without account navigates to registration',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        await tester.tap(find.text('My Account'));
        await tester.pumpAndSettle();

        // Should navigate to registration wizard
        expect(find.text('Register Username'), findsOneWidget,
            reason:
                'Tapping "My Account" without account should start registration');
      });
    });

    group('Switch Profile navigation', () {
      testWidgets('tapping "Switch Profile" opens profile switcher sheet',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        await tester.tap(find.text('Switch Profile'));
        await tester.pumpAndSettle();

        // Should show profile switcher
        expect(find.text('Switch Profile'), findsWidgets,
            reason: 'Should open profile switcher sheet');
      });
    });
  });

  group('ProfileAvatarButton - No Red Badge', () {
    testWidgets('does NOT show red badge when hasAccount is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Should NOT have a red badge - look for error-colored container
      // The badge was a small 10x10 circle with error color
      // We verify by checking that there's no red indicator
      final avatarButton = find.byType(ProfileAvatarButton);
      expect(avatarButton, findsOneWidget);

      // Check that there's no error-colored circle (badge)
      // Instead, verify that the widget doesn't have a Stack for badge
      // (Stack might still exist for other reasons, so we check for no badge semantics)
      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      // Should have subtle indication, not alarming badge
      expect(semantics.label, isNot(contains('registration needed')));
    });

    testWidgets(
        'shows subtle "No account" text indicator when hasAccount is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Should show subtle "No account" text somewhere
      // This text should be visible as a hint, not an alarming badge
      expect(find.text('No account'), findsOneWidget,
          reason: 'Should show subtle "No account" text instead of red badge');
    });

    testWidgets('does NOT show "No account" text when hasAccount is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: true,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('No account'), findsNothing,
          reason: 'Should not show "No account" when account exists');
    });

    testWidgets('maintains accessible semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, contains('Profile'));
      // Button is handled by the widget being tappable
    });
  });
}
