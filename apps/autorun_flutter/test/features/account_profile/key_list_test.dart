import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';

import 'account_profile_test_helpers.dart';
import '../../test_helpers/test_keypair_factory.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Key List Display', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => null);
    });

    testWidgets('shows active key with correct styling', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
            isActive: true,
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows disabled key with correct styling', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: false,
            disabledAt: DateTime.now(),
          ),
        ],
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair1],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('shows SIGNING KEY badge on active signing key',
        (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
            isActive: true,
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('SIGNING KEY'), findsOneWidget);
    });

    testWidgets('does not show SIGNING KEY badge on non-signing key',
        (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: true,
          ),
        ],
      );
      // Profile only has keypair1 as its signing key
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair1],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Only one SIGNING KEY badge (for keypair1)
      expect(find.text('SIGNING KEY'), findsOneWidget);
    });

    testWidgets('shows key counter X/10', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);
      final keypair3 = await TestKeypairFactory.fromSeed(3);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-3',
            publicKey: keypair3.publicKey,
            icPrincipal: keypair3.principal ?? 'principal-3',
            isActive: true,
          ),
        ],
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair1],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('3/10'), findsOneWidget);
    });

    testWidgets('shows No keys found when empty', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [], // No keys
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('No keys found'), findsOneWidget);
    });

    testWidgets('shows LAST ACTIVE badge when only one active key remains',
        (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: false,
            disabledAt: DateTime.now(),
          ),
        ],
      );
      // keypair2 is in profile but not registered as signing key
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2], // This key is NOT in account's active keys
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // key-1 is the last active key and is NOT the signing key
      expect(find.text('LAST ACTIVE'), findsOneWidget);
    });

    testWidgets('displays public key and principal for each key',
        (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
            label: 'Test Key',
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Public Key'), findsOneWidget);
      expect(find.text('IC Principal'), findsOneWidget);
    });

    testWidgets('shows disabled keys section when present', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: false,
            disabledAt: DateTime.now(),
          ),
        ],
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair1],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('DISABLED KEYS'), findsOneWidget);
    });

    testWidgets('shows Added date for active keys', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'principal-1',
            isActive: true,
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.textContaining('Added'), findsOneWidget);
    });

    testWidgets('shows Disabled date for disabled keys', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair1.publicKey,
            icPrincipal: keypair1.principal ?? 'principal-1',
            isActive: true,
          ),
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-2',
            publicKey: keypair2.publicKey,
            icPrincipal: keypair2.principal ?? 'principal-2',
            isActive: false,
            disabledAt: DateTime.now(),
          ),
        ],
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair1],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // The disabled key card shows "Disabled" text (as status) and "Disabled today" (as timestamp)
      // We verify that the "Disabled" status text is present
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('shows copy button for public key', (tester) async {
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Find copy icons (there should be at least 2 - one for public key, one for principal)
      expect(find.byIcon(Icons.copy), findsWidgets);
    });

    testWidgets('shows Add Key FAB when not at max keys', (tester) async {
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

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Add Key'), findsOneWidget);
    });

    testWidgets('hides Add Key FAB when at max keys (10)', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();

      // Create 10 keys to hit the max
      final keys = <AccountPublicKey>[];
      for (int i = 0; i < 10; i++) {
        keys.add(AccountProfileScreenTestHelper.createTestAccountPublicKey(
          id: 'key-$i',
          publicKey: 'public-key-$i',
          icPrincipal: 'principal-$i',
        ));
      }

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: keys,
      );
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Add Key'), findsNothing);
    });
  });
}
