import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';

import 'account_profile_test_helpers.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Keypair Mismatch Recovery', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => null);
    });

    testWidgets('shows warning when signing key not registered with account',
        (tester) async {
      // Create two different keypairs
      final profileKeypair =
          await TestKeypairFactory.fromSeed(1); // Profile's signing key
      final accountKeypair =
          await TestKeypairFactory.fromSeed(2); // Key in account

      // Account has only accountKeypair
      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: accountKeypair.publicKey,
            icPrincipal: accountKeypair.principal ?? 'principal-1',
            isActive: true,
          ),
        ],
      );

      // Profile uses profileKeypair (which is NOT in account)
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [profileKeypair],
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

      // Should show warning
      expect(find.text('Signing Key Not Registered'), findsOneWidget);
    });

    testWidgets('does not show warning when signing key matches account key',
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

      // Should NOT show warning
      expect(find.text('Signing Key Not Registered'), findsNothing);
    });

    testWidgets('shows Switch to Registered Key button when recovery possible',
        (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      // Account has keypair1
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
        ],
      );

      // Profile has keypair2 as signing key, but also has keypair1
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2, keypair1], // keypair2 is primary (first in list)
        username: 'testuser',
        activeKeypairId: keypair2.id,
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

      // Should show recovery button
      expect(find.text('Switch to Registered Key'), findsOneWidget);
    });

    testWidgets('switch to registered key works correctly', (tester) async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      // Account has keypair1
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
        ],
      );

      // Profile has keypair2 as signing key, but also has keypair1
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2, keypair1],
        username: 'testuser',
        activeKeypairId: keypair2.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Updated profile after switching
      final updatedProfile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2, keypair1],
        username: 'testuser',
        activeKeypairId: keypair1.id, // Now keypair1 is active
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(updatedProfile);
      when(() => profileController.setActiveKeypair(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
          )).thenAnswer((_) async {});

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Tap switch button
      await tester.tap(find.text('Switch to Registered Key'));
      await tester.pumpAndSettle();

      // Verify setActiveKeypair was called with the registered key's ID
      verify(() => profileController.setActiveKeypair(
            profileId: 'profile-1',
            keypairId: keypair1.id,
          )).called(1);

      // Should show success snackbar
      expect(find.text('Switched to registered signing key'), findsOneWidget);
    });

    testWidgets('shows recovery message when registered key available',
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
        ],
      );

      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2, keypair1],
        username: 'testuser',
        activeKeypairId: keypair2.id,
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

      expect(
        find.textContaining('another key in your profile is'),
        findsOneWidget,
      );
    });

    testWidgets('shows no recovery message when no registered key available',
        (tester) async {
      final profileKeypair = await TestKeypairFactory.fromSeed(1);
      final accountKeypair = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: accountKeypair.publicKey,
            icPrincipal: accountKeypair.principal ?? 'principal-1',
            isActive: true,
          ),
        ],
      );

      // Profile only has profileKeypair (no match)
      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [profileKeypair],
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

      // Should show no recovery message
      expect(
        find.textContaining('recover the original signing key'),
        findsOneWidget,
      );
      // Should NOT show switch button
      expect(find.text('Switch to Registered Key'), findsNothing);
    });

    testWidgets('switch to registered key error handling', (tester) async {
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
        ],
      );

      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [keypair2, keypair1],
        username: 'testuser',
        activeKeypairId: keypair2.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => profileController.findById(any())).thenReturn(profile);
      when(() => profileController.setActiveKeypair(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
          )).thenThrow(Exception('Failed to switch key'));

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.tap(find.text('Switch to Registered Key'));
      await tester.pumpAndSettle();

      // Should show error snackbar
      expect(find.textContaining('Failed to switch key'), findsOneWidget);
    });

    testWidgets('warning shows warning icon', (tester) async {
      final profileKeypair = await TestKeypairFactory.fromSeed(1);
      final accountKeypair = await TestKeypairFactory.fromSeed(2);

      final account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: accountKeypair.publicKey,
            icPrincipal: accountKeypair.principal ?? 'principal-1',
            isActive: true,
          ),
        ],
      );

      final profile = Profile(
        id: 'profile-1',
        name: 'Test',
        keypairs: [profileKeypair],
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

      // Should show warning icon
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
