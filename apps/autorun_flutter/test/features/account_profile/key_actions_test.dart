import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';

import 'account_profile_test_helpers.dart';
import '../../test_helpers/test_keypair_factory.dart';

void main() {
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  Future<void> expandPublicKeysSection(WidgetTester tester) async {
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
  }

  Future<void> scrollToDeleteButton(WidgetTester tester) async {
    final scrollView = find.byType(SingleChildScrollView);
    for (int i = 0; i < 10; i++) {
      await tester.fling(scrollView, const Offset(0, -300), 10000);
      await tester.pumpAndSettle();

      final deleteButtons = find.byWidgetPredicate((widget) {
        if (widget is IconButton && widget.icon is Icon) {
          final icon = widget.icon as Icon;
          return icon.icon == Icons.delete_outline;
        }
        return false;
      });

      if (deleteButtons.evaluate().isNotEmpty) {
        try {
          await tester.ensureVisible(deleteButtons.first);
          await tester.pumpAndSettle();
          return;
        } catch (_) {}
      }
    }
  }

  Future<void> scrollToUseForSigningButton(WidgetTester tester) async {
    final scrollView = find.byType(SingleChildScrollView);
    for (int i = 0; i < 10; i++) {
      await tester.fling(scrollView, const Offset(0, -300), 10000);
      await tester.pumpAndSettle();

      final useForSigningButtons = find.text('Use for signing');
      if (useForSigningButtons.evaluate().isNotEmpty) {
        try {
          await tester.ensureVisible(useForSigningButtons.first);
          await tester.pumpAndSettle();
          return;
        } catch (_) {}
      }
    }
  }

  Finder findDeleteIconButton() {
    return find.byWidgetPredicate((widget) {
      if (widget is IconButton && widget.icon is Icon) {
        final icon = widget.icon as Icon;
        return icon.icon == Icons.delete_outline;
      }
      return false;
    });
  }

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

        await expandPublicKeysSection(tester);
        await scrollToUseForSigningButton(tester);

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

        final profile = Profile(
          id: 'profile-1',
          name: 'Test',
          keypairs: [keypair1, keypair2],
          username: 'testuser',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

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

        await expandPublicKeysSection(tester);
        await scrollToUseForSigningButton(tester);

        await tester.tap(find.text('Use for signing'));
        await tester.pumpAndSettle();

        verify(() => profileController.setActiveKeypair(
              profileId: 'profile-1',
              keypairId: keypair2.id,
            )).called(1);

        expect(find.text('Signing key updated'), findsOneWidget);
      });

      testWidgets('does not show Use for signing for key without local keypair',
          (tester) async {
        final keypair1 = await TestKeypairFactory.fromSeed(1);
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

        await expandPublicKeysSection(tester);

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

        await expandPublicKeysSection(tester);

        expect(findDeleteIconButton(), findsWidgets);
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

        await expandPublicKeysSection(tester);
        await scrollToDeleteButton(tester);

        final deleteButtons = findDeleteIconButton();
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

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

        await expandPublicKeysSection(tester);
        await scrollToDeleteButton(tester);

        final deleteButtons = findDeleteIconButton();
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

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

        await expandPublicKeysSection(tester);
        await scrollToDeleteButton(tester);

        final deleteButtons = find.byIcon(Icons.delete_outline);
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Remove Key'));
        await tester.pumpAndSettle();

        verify(() => accountController.removePublicKey(
              username: 'testuser',
              keyId: 'key-1',
              signingKeypair: any(named: 'signingKeypair'),
            )).called(1);

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

        await expandPublicKeysSection(tester);

        expect(find.byIcon(Icons.delete_outline), findsNothing);
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

        await expandPublicKeysSection(tester);

        expect(findDeleteIconButton(), findsNothing);
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

        await expandPublicKeysSection(tester);
        await scrollToDeleteButton(tester);

        final deleteButtons = findDeleteIconButton();
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Remove Key'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Network error'), findsOneWidget);
      });
    });
  });
}
