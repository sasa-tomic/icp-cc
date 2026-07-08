import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
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

  group('AccountProfileScreen — local-only passkey hint (UXR5-6)', () {
    // A local-only profile (account == null) shows a disabled passkey hint so
    // the user knows where/when passkeys appear. The hint must be honest: it
    // states the registration prerequisite and never offers a fake "Manage"
    // affordance. It renders on every platform (the subtitle is Linux-aware).
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();
      // Local-only mode must NOT call refreshAccount (no backend). Leaving
      // this un-stubbed is itself a fail-fast guard.
    });

    Future<void> pumpLocalOnly(WidgetTester tester,
        {required Profile profile}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen(
            account: null, // local-only — no backend registration
            accountController: accountController,
            profile: profile,
            profileController: profileController,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<Profile> localProfile() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      return Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    testWidgets(
        'surfaces a Passkeys hint explaining the registration prerequisite',
        (tester) async {
      await pumpLocalOnly(tester, profile: await localProfile());

      expect(find.text('Passkeys'), findsOneWidget,
          reason: 'A local-only user should see where passkeys will live.');
      // Matches both the plain subtitle and the Linux-aware one.
      expect(
        find.textContaining('Available after you register a marketplace account'),
        findsOneWidget,
      );
    });

    testWidgets('does not fake passkey support with a Manage affordance',
        (tester) async {
      await pumpLocalOnly(tester, profile: await localProfile());

      // No actionable passkey control — the hint is informational only.
      expect(find.text('Manage'), findsNothing);
      expect(find.text('Manage Passkeys'), findsNothing);
    });

    testWidgets('on Linux desktop the hint also notes the browser requirement',
        (tester) async {
      await pumpLocalOnly(tester, profile: await localProfile());

      if (PasskeyPlatform.isLinuxDesktop) {
        expect(find.textContaining('need a browser'), findsOneWidget);
      } else {
        // On non-Linux, the Linux-only clause must NOT be shown.
        expect(find.textContaining('need a browser'), findsNothing);
      }
    });
  });
}
