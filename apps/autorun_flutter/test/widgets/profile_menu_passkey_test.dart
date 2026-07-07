import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('ProfileMenuWidget - Passkeys accessible via My Account', () {
    late ProfileController profileController;
    late MockPasskeyService mockPasskeyService;
    late MockAccountController mockAccountController;
    late Account testAccount;

    setUp(() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      profileController = await buildProfileController(keypairs: [keypair]);
      await profileController.updateProfileUsername(
        profileId: profileController.profiles.first.id,
        username: 'testuser',
      );

      mockPasskeyService = MockPasskeyService();
      mockAccountController = MockAccountController();

      testAccount = buildTestAccount();
    });

    Future<void> pumpProfileMenu(
      WidgetTester tester, {
      PasskeyService? passkeyService,
    }) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);
      when(() => mockAccountController.refreshAccount(any()))
          .thenAnswer((_) async => testAccount);

      await pumpProfileMenuHost(
        tester,
        profileController: profileController,
        accountController: mockAccountController,
        passkeyService: passkeyService ?? mockPasskeyService,
      );
    }

    testWidgets('passkeys are NOT a separate menu item',
        (WidgetTester tester) async {
      await pumpProfileMenu(tester);

      // Passkeys should NOT be visible as a separate menu item
      expect(find.text('Passkeys'), findsNothing,
          reason:
              'Passkeys should be accessible via My Account > AccountProfileScreen, not a separate menu item');
    });

    testWidgets('menu has the core items (simplified structure)',
        (WidgetTester tester) async {
      await pumpProfileMenu(tester);

      // The core items: My Account, Vault (account-scoped), Switch Profile, Settings.
      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget,
          reason: 'Vault is an account-scoped menu tile for registered users');
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
