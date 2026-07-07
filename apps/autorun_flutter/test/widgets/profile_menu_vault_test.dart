// Vault entry wiring (A-4 → profile menu navigation).
//
// Proves a real user can REACH the vault screens from the running app's
// Profile menu, and that the routing decision (first-time setup vs unlock)
// is driven by `PasskeyService.getVault(accountId)` exactly as the
// integration probe (h_vault_lifecycle_test.dart) expects.
//
// The HTTP/PasskeyService layer is mocked (per AGENTS.md the HTTP layer MAY
// be mocked); no cryptography is exercised here — this is pure navigation
// wiring. Real-FFI crypto round-trips through these screens are covered in
// vault_crypto_service_test.dart, passkey_service_vault_test.dart, and the
// h_vault_lifecycle integration probe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/screens/vault_unlock_screen.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('ProfileMenuWidget - Vault entry (A-4 wiring)', () {
    late ProfileController profileController;
    late MockPasskeyService mockPasskeyService;
    late MockAccountController mockAccountController;
    late Account testAccount;

    setUp(() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      profileController = await buildProfileController(keypairs: [keypair]);
      await profileController.updateProfileUsername(
        profileId: profileController.profiles.first.id,
        username: 'vaultowner',
      );

      mockPasskeyService = MockPasskeyService();
      mockAccountController = MockAccountController();
      testAccount = buildTestAccount(username: 'vaultowner');

      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);
      when(() => mockAccountController.refreshAccount(any()))
          .thenAnswer((_) async => testAccount);
    });

    Future<void> pumpMenu(WidgetTester tester) async {
      await pumpProfileMenuHost(
        tester,
        profileController: profileController,
        accountController: mockAccountController,
        passkeyService: mockPasskeyService,
      );
    }

    testWidgets(
        'Vault tile is present, labelled, and tappable with a registered account',
        (tester) async {
      await pumpMenu(tester);

      expect(find.text('Vault'), findsOneWidget,
          reason: 'A registered account must expose the Vault tile.');
      expect(find.text('Encrypt your credentials'), findsOneWidget,
          reason: 'The default subtitle describes the vault.');

      // The tile must be enabled (onTap non-null). _MenuTile sets
      // ListTile.enabled = onTap != null, so a tappable tile is `enabled`.
      final vaultTile = find.ancestor(
        of: find.text('Vault'),
        matching: find.byType(ListTile),
      );
      expect(vaultTile, findsOneWidget);
      expect(tester.widget<ListTile>(vaultTile).enabled, isTrue,
          reason: 'The Vault tile must be tappable when an account exists.');
    });

    testWidgets('Vault tile is absent for a local-only profile (no account)',
        (tester) async {
      // A fresh controller WITHOUT updateProfileUsername → username null →
      // hasAccount false. The vault blob is keyed by the backend account id,
      // so a local-only profile has nothing to key it: the tile must be hidden.
      final keypair = await TestKeypairFactory.fromSeed(7);
      final localController = await buildProfileController(keypairs: [keypair]);
      final localAccountController = MockAccountController();
      when(() => localAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => null);

      await pumpProfileMenuHost(
        tester,
        profileController: localController,
        accountController: localAccountController,
        passkeyService: mockPasskeyService,
      );

      expect(find.text('Vault'), findsNothing,
          reason: 'Vault must be hidden when there is no registered account.');
    });

    testWidgets(
        'no vault → tapping Vault routes to VaultPasswordSetupScreen, probing '
        'with the backend account id', (tester) async {
      String? probedAccountId;
      when(() => mockPasskeyService.getVault(any())).thenAnswer((invocation) {
        probedAccountId = invocation.positionalArguments.first as String;
        return Future<VaultData?>.value(); // null → 404 / not-yet-created
      });

      await pumpMenu(tester);
      await tester.tap(find.text('Vault'));
      await tester.pumpAndSettle();

      expect(probedAccountId, equals(testAccount.id),
          reason: 'The probe must key off the BACKEND account id (the same id '
              'AccountProfileScreen passes to PasskeyService), not profile.id.');
      expect(find.byType(VaultPasswordSetupScreen), findsOneWidget,
          reason: 'A first-time user (no vault blob) must reach the setup '
              'screen.');
      expect(find.text('Set Vault Password'), findsOneWidget);
      expect(
          find.widgetWithText(ElevatedButton, 'Create Vault'), findsOneWidget);
    });

    testWidgets('vault exists → tapping Vault routes to VaultUnlockScreen',
        (tester) async {
      when(() => mockPasskeyService.getVault(any())).thenAnswer((_) async =>
          VaultData(
              encryptedData: 'ZW5j', salt: 'c2FsdA==', nonce: 'bm9uY2U='));

      await pumpMenu(tester);
      await tester.tap(find.text('Vault'));
      await tester.pumpAndSettle();

      expect(find.byType(VaultUnlockScreen), findsOneWidget,
          reason: 'An existing vault blob must route to the unlock screen.');
      expect(find.text('Unlock Vault'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Unlock'), findsOneWidget);
    });

    testWidgets(
        'probe failure is surfaced loudly and routes to NEITHER screen '
        '(no silent fallthrough to setup)', (tester) async {
      when(() => mockPasskeyService.getVault(any()))
          .thenThrow(PasskeyException('HTTP 500: internal', statusCode: 500));

      await pumpMenu(tester);
      await tester.tap(find.text('Vault'));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('Could not check vault status'), findsOneWidget,
          reason: 'A probe failure must be surfaced to the user (LOUD).');
      expect(find.byType(VaultPasswordSetupScreen), findsNothing,
          reason: 'Must NOT route to setup on a server error — guessing setup '
              'when the server is down could clobber an existing blob.');
      expect(find.byType(VaultUnlockScreen), findsNothing,
          reason: 'Must NOT route to unlock on a server error either.');
    });
  });
}
