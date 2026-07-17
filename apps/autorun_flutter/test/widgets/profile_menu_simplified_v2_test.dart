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

    group('Core menu items', () {
      testWidgets('menu shows the core items for users with account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        // My Account, Vault (account-scoped), Switch Profile, Settings.
        expect(find.text('My Account'), findsOneWidget,
            reason: '"My Account" should be visible as primary account item');
        expect(find.text('Vault'), findsOneWidget,
            reason: '"Vault" should be visible for registered users');
        expect(find.text('Switch Profile'), findsOneWidget,
            reason: '"Switch Profile" should be visible');
        expect(find.text('Settings'), findsOneWidget,
            reason: '"Settings" should be visible');

        // Count visible menu tiles - should be exactly 4 for a registered
        // user with a single profile (My Account + Vault + Switch + Settings).
        final menuTiles = find.byType(ListTile);
        final tileCount = menuTiles.evaluate().length;
        expect(tileCount, equals(4),
            reason:
                'Profile menu should have exactly 4 items for a registered user. '
                'Found $tileCount.');
      });

      testWidgets(
          'menu hides the Vault tile for users without account (still 3 items)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // No Vault tile: the vault blob is keyed by the backend account id,
        // so a local-only profile cannot reach it.
        expect(find.text('Vault'), findsNothing,
            reason: 'Vault must be hidden for local-only profiles');
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
                'Profile menu should have exactly 3 items without an account. '
                'Found $tileCount.');
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

      testWidgets('shows local-keys subtitle for users without account',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        // UX-7: the menu now routes a local-only profile to Account & Keys
        // (where keys are visible AND a register CTA lives), so the subtitle
        // must point at that surface — not promise a direct registration jump.
        expect(
            find.text('Local profile — view keys or register'), findsOneWidget,
            reason: 'Should advertise the local-keys surface when no account');
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
          'tapping "My Account" without account navigates to Account & Keys '
          '(UX-7: local keys are reachable without backend registration)',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: false);

        await tester.tap(find.text('My Account'));
        await tester.pumpAndSettle();

        // Lands on AccountProfileScreen in local-only mode — NOT the
        // registration wizard. The screen title is "My Identity" and the
        // local-only branch renders an honest "not registered" badge.
        expect(find.text('My Identity'), findsOneWidget,
            reason: 'Local-only tap must open AccountProfileScreen');
        expect(find.text('Local profile — not registered'), findsOneWidget,
            reason: 'AccountProfileScreen must be in its local-only branch');
        expect(find.text('Register Username'), findsNothing,
            reason:
                'UX-7: must NOT jump straight into the registration wizard');

        // The profile's local keypair is reachable from this screen — proving
        // the menu no longer hides keys behind registration. Uses real crypto
        // via TestKeypairFactory (seeded in setUp). The "Local key" caption is
        // unique to the local key card, so it unambiguously proves the key
        // surface rendered (the fixture happens to reuse the keypair label as
        // the profile name, so the label itself appears twice).
        final activeProfile = profileController.activeProfile;
        expect(activeProfile, isNotNull);
        expect(find.text(activeProfile!.primaryKeypair.label), findsWidgets,
            reason: 'The local keypair label must be visible from the menu');
        expect(find.text('Local key'), findsOneWidget,
            reason: 'The local key card must be rendered on the screen');
      });
    });

    group('Switch Profile navigation', () {
      testWidgets('tapping "Switch Profile" opens manage profiles sheet',
          (WidgetTester tester) async {
        await pumpProfileMenu(tester, hasAccount: true);

        await tester.tap(find.text('Switch Profile'));
        await tester.pumpAndSettle();

        // With a single profile, "Switch Profile" opens the full manage sheet
        // (create / rename / delete) — there is nothing to switch TO. The
        // sheet's title is "Manage Profiles". Asserting that title appears
        // is the correct post-condition (not "Switch Profile" re-appearing).
        expect(find.text('Manage Profiles'), findsWidgets,
            reason: 'Should open manage profiles sheet for single-profile case.');
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
