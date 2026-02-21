import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';

import 'account_profile_test_helpers.dart';
import '../../test_helpers/test_keypair_factory.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Key Actions', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();

      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => null);
    });

    group('Set as Signing Key', () {
      testWidgets('shows Use for signing button for non-signing active key',
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
        // Profile has both keypairs, keypair1 is the signing key
        final profile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1, keypair2],
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

        // Scroll to find the button
        await tester.ensureVisible(find.text('Use for signing').last);
        await tester.pumpAndSettle();

        expect(find.text('Use for signing'), findsOneWidget);
      });

      testWidgets('set as signing key works correctly', (tester) async {
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

        // Initial profile has keypair1 as signing key
        final profile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1, keypair2],
          username: 'testuser',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Updated profile with keypair2 as signing key
        final updatedProfile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1, keypair2],
          username: 'testuser',
          activeKeypairId: keypair2.id,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(() => profileController.findById(any()))
            .thenReturn(updatedProfile);
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

        // Scroll until "Use for signing" button is visible
        await tester.ensureVisible(find.text('Use for signing').last);
        await tester.pumpAndSettle();

        // Tap "Use for signing" button
        await tester.tap(find.text('Use for signing').last);
        await tester.pumpAndSettle();

        // Verify setActiveKeypair was called
        verify(() => profileController.setActiveKeypair(
              profileId: 'profile-1',
              keypairId: keypair2.id,
            )).called(1);

        // Should show success snackbar
        expect(find.text('Signing key updated'), findsOneWidget);
      });

      testWidgets('does not show Use for signing for key without local keypair',
          (tester) async {
        final keypair1 = await TestKeypairFactory.fromSeed(1);
        // Create an account key that doesn't match any local keypair
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
              publicKey: 'different-public-key-no-match',
              icPrincipal: 'different-principal',
              isActive: true,
            ),
          ],
        );
        // Profile only has keypair1
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

        // Should only have one "Use for signing" button (for key-1 which has matching keypair)
        // key-2 doesn't have a matching local keypair, so no button
        expect(find.text('Use for signing'), findsNothing);
      });
    });

    group('Remove Key', () {
      testWidgets('shows delete button for non-last active key',
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

        // Find delete icons - there should be at least one for key-2
        expect(find.byIcon(Icons.delete_outline), findsWidgets);
      });

      testWidgets('remove key shows confirmation dialog', (tester) async {
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

        // Tap delete button (the last one should be for key-2)
        final deleteButtons = find.byIcon(Icons.delete_outline);
        await tester.ensureVisible(deleteButtons.last);
        await tester.pumpAndSettle();
        await tester.tap(deleteButtons.last);
        await tester.pumpAndSettle();

        // Should show confirmation dialog
        expect(find.text('Remove Key?'), findsOneWidget);
        expect(
            find.textContaining('This will disable the key'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });

      testWidgets('remove key cancellation does not remove key',
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

        // Tap delete button
        final deleteButtons = find.byIcon(Icons.delete_outline);
        await tester.ensureVisible(deleteButtons.last);
        await tester.pumpAndSettle();
        await tester.tap(deleteButtons.last);
        await tester.pumpAndSettle();

        // Tap cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Verify removePublicKey was NOT called
        verifyNever(() => accountController.removePublicKey(
              username: any(named: 'username'),
              keyId: any(named: 'keyId'),
              signingKeypair: any(named: 'signingKeypair'),
            ));
      });

      testWidgets('remove key confirmation calls removePublicKey',
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
        final profile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1],
          username: 'testuser',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(() => profileController.findById(any())).thenReturn(profile);
        when(() => accountController.removePublicKey(
              username: any(named: 'username'),
              keyId: any(named: 'keyId'),
              signingKeypair: any(named: 'signingKeypair'),
            )).thenAnswer((_) async => account.publicKeys.last);

        await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
          tester,
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        );

        // Tap delete button
        final deleteButtons = find.byIcon(Icons.delete_outline);
        await tester.ensureVisible(deleteButtons.last);
        await tester.pumpAndSettle();
        await tester.tap(deleteButtons.last);
        await tester.pumpAndSettle();

        // Confirm removal
        await tester.tap(find.widgetWithText(FilledButton, 'Remove Key'));
        await tester.pumpAndSettle();

        // Verify removePublicKey was called
        verify(() => accountController.removePublicKey(
              username: 'testuser',
              keyId: 'key-2',
              signingKeypair: any(named: 'signingKeypair'),
            )).called(1);

        // Should show success snackbar
        expect(find.text('Key removed successfully'), findsOneWidget);
      });

      testWidgets('last active key cannot be removed (no delete button)',
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

        // Should not show delete button for last active key
        expect(find.byIcon(Icons.delete_outline), findsNothing);
      });

      testWidgets('remove key error shows error snackbar', (tester) async {
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
        final profile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1],
          username: 'testuser',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(() => profileController.findById(any())).thenReturn(profile);
        when(() => accountController.removePublicKey(
              username: any(named: 'username'),
              keyId: any(named: 'keyId'),
              signingKeypair: any(named: 'signingKeypair'),
            )).thenThrow(Exception('Network error'));

        await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
          tester,
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        );

        // Tap delete button
        final deleteButtons = find.byIcon(Icons.delete_outline);
        await tester.ensureVisible(deleteButtons.last);
        await tester.pumpAndSettle();
        await tester.tap(deleteButtons.last);
        await tester.pumpAndSettle();

        // Confirm removal
        await tester.tap(find.widgetWithText(FilledButton, 'Remove Key'));
        await tester.pumpAndSettle();

        // Should show error snackbar
        expect(find.textContaining('Network error'), findsOneWidget);
      });
    });
  });
}
