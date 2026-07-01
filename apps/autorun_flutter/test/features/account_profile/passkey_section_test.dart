import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/utils/passkey_platform.dart';

import 'account_profile_test_helpers.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Passkey Section', () {
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

    testWidgets('shows PASSKEYS section header', (tester) async {
      // Skip on Linux desktop (passkeys not supported)
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
    });

    testWidgets('shows Manage Passkeys button on supported platforms',
        (tester) async {
      // Skip on Linux desktop (passkeys not supported)
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

      expect(find.text('Manage Passkeys'), findsOneWidget);
    });

    testWidgets('shows passkey description', (tester) async {
      // Skip on Linux desktop (passkeys not supported)
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

      expect(
        find.textContaining('Biometric'),
        findsOneWidget,
      );
    });

    testWidgets('shows key icon in passkey section', (tester) async {
      // Skip on Linux desktop (passkeys not supported)
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

    testWidgets('Manage Passkeys button is an OutlinedButton', (tester) async {
      // Skip on Linux desktop (passkeys not supported)
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

      final button = find.widgetWithText(OutlinedButton, 'Manage');
      expect(button, findsOneWidget);
    });
  });

  group('AccountProfileScreen - Passkey Section (Linux Desktop)', () {
    // These tests verify the Linux unsupported message behavior
    // They don't actually need to run on Linux to verify the logic

    testWidgets('on non-Linux platforms shows normal passkey section',
        (tester) async {
      // If we're on Linux desktop, this test is not relevant
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test is for non-Linux platforms');
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

      // Should NOT show unsupported message (this test runs on non-Linux platforms)
      expect(
        find.text('Passkeys require a browser on Linux'),
        findsNothing,
      );
    });
  });
}
