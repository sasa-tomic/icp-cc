import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/utils/passkey_platform.dart';

import 'account_profile_test_helpers.dart';
import '../../test_helpers/test_keypair_factory.dart';

void main() {
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Security Section (Unified)', () {
    late MockAccountController accountController;
    late MockProfileController profileController;
    late Account account;
    late Profile profile;

    setUp(() async {
      accountController = MockAccountController();
      profileController = MockProfileController();

      final keypair = await TestKeypairFactory.getEd25519Keypair();

      account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
          ),
        ],
      );

      profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => account);
      when(() => profileController.findById(any())).thenReturn(profile);
    });

    testWidgets(
        'shows single SECURITY section header instead of separate PASSKEYS and PUBLIC KEYS',
        (tester) async {
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('Passkeys not supported on Linux desktop');
        return;
      }

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('PASSKEYS'), findsNothing);
      expect(find.text('PUBLIC KEYS'), findsNothing);
    });

    testWidgets(
        'shows Passkeys row with icon, name, description, and manage button',
        (tester) async {
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('Passkeys not supported on Linux desktop');
        return;
      }

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Passkeys'), findsOneWidget);
      expect(find.textContaining('Biometric'), findsOneWidget);
      expect(find.text('Manage'), findsWidgets);
    });

    testWidgets(
        'shows Public Keys row with icon, name, description, and manage button',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Public Keys'), findsOneWidget);
      expect(find.textContaining('Cryptographic keys'), findsOneWidget);
    });

    testWidgets('shows key count in Public Keys row', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);
      final keypair3 = await TestKeypairFactory.fromSeed(3);

      final accountMulti = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-3',
            publicKey: keypair3.publicKey,
            icPrincipal: keypair3.principal ?? 'principal-3',
          ),
        ],
      );

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => accountMulti);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: accountMulti,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('3/10'), findsOneWidget);
    });

    testWidgets('shows Backup/Export row with description', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Backup'), findsOneWidget);
      expect(find.textContaining('Export'), findsWidgets);
    });

    testWidgets('Passkeys row shows fingerprint icon', (tester) async {
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('Passkeys not supported on Linux desktop');
        return;
      }

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });

    testWidgets('Public Keys row shows key icon', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
    });

    testWidgets('Backup row shows save/download icon', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.byIcon(Icons.download), findsWidgets);
    });

    testWidgets(
        'tapping Passkeys row Manage button navigates to PasskeyManagementScreen',
        (tester) async {
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('Passkeys not supported on Linux desktop');
        return;
      }

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.dragUntilVisible(
        find.text('Passkeys'),
        find.byType(SingleChildScrollView),
        const Offset(0, -50),
      );

      final manageButton = find.widgetWithText(OutlinedButton, 'Manage');
      await tester.tap(manageButton.first);
      await tester.pumpAndSettle();

      expect(find.text('Manage Passkeys'), findsWidgets);
    });

    testWidgets('Public Keys row is expandable to show key list',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.dragUntilVisible(
        find.text('Public Keys'),
        find.byType(SingleChildScrollView),
        const Offset(0, -50),
      );

      final publicKeysRow = find.ancestor(
        of: find.text('Public Keys'),
        matching: find.byType(ExpansionTile),
      );

      expect(publicKeysRow, findsOneWidget);
    });

    testWidgets('expanding Public Keys shows key count and actions',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.dragUntilVisible(
        find.text('Public Keys'),
        find.byType(SingleChildScrollView),
        const Offset(0, -50),
      );

      final expansionTile = find.ancestor(
        of: find.text('Public Keys'),
        matching: find.byType(ExpansionTile),
      );

      await tester.tap(expansionTile);
      await tester.pumpAndSettle();

      expect(find.text('1/10'), findsOneWidget);
      expect(find.text('Import Keys'), findsOneWidget);
      expect(find.text('Export Keys'), findsOneWidget);
    });

    testWidgets('existing functionality - Add Key FAB still works',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Add Key'), findsOneWidget);
    });

    testWidgets('existing functionality - key list shows after expansion',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.dragUntilVisible(
        find.text('Public Keys'),
        find.byType(SingleChildScrollView),
        const Offset(0, -50),
      );

      final expansionTile = find.ancestor(
        of: find.text('Public Keys'),
        matching: find.byType(ExpansionTile),
      );

      await tester.tap(expansionTile);
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('SIGNING KEY'), findsOneWidget);
    });
  });

  group('AccountProfileScreen - Security Section (Linux Desktop)', () {
    testWidgets(
        'shows Linux-specific message for Passkeys on unsupported platform',
        (tester) async {
      if (!PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test is for Linux desktop only');
        return;
      }

      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
          ),
        ],
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final accountController = MockAccountController();
      final profileController = MockProfileController();

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => account);
      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.textContaining('browser'), findsOneWidget);
    });
  });
}
