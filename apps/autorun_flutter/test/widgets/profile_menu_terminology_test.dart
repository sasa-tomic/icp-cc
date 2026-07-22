import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('Profile Menu Terminology Clarity - Simplified V2', () {
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

    Future<void> pumpProfileMenuWithAccount(
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
          'shows helpful subtitle advertising the local-keys surface (UX-7)',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // UX-7: subtitle now points to Account & Keys (where local keys live
        // and registration is offered as a CTA), instead of promising a
        // direct jump into the registration wizard.
        expect(
            find.text('Local profile — view keys or register'), findsOneWidget,
            reason:
                'Subtitle should advertise the local-keys surface for a local-only profile');
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
          'shows direct "Register @username" tile for local-only profiles',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        expect(find.text('Register @username'), findsOneWidget,
            reason:
                'Local-only profiles get a direct registration tile (UX click-reduction)');
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

    group('Core menu structure', () {
      testWidgets('has the core menu items for a registered user',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('My Account'), findsOneWidget);
        expect(find.text('Vault'), findsOneWidget,
            reason: 'Vault is an account-scoped tile for registered users');
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
