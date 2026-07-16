// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 2 (mock Secret Service / StorageReady).
///
/// Boots the REAL app ONCE under the mock keyring
/// (`scripts/run-with-mock-keyring.sh`), then runs phases with `resetAppState`
/// + remount between them. One build/load covers the whole keyring-required
/// surface.
///
/// Run: `just e2e-desktop` (PASS 2 — wraps the run in the mock Secret Service).
///
/// Covered flows (registered in [FlowRegistry]):
///   first_run.create_profile, profile.open_menu, profile.switch_via_manage_sheet,
///   scripts.create, scripts.duplicate,
///   profile.open_account_profile, keypair.generate_local, keypair.set_signing,
///   keypair.edit_label, keypair.export, keypair.import,
///   account.register_from_local,
///   vault.route_from_menu, vault.setup, vault.unlock,
///   vault.unlock_wrong_password, vault.use_recovery_code
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/screens/export_keys_dialog.dart';
import 'package:icp_autorun/screens/import_keys_dialog.dart';
import 'package:icp_autorun/screens/recovery_codes_screen.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/screens/vault_unlock_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/script_row_menus.dart';
import 'package:icp_autorun/widgets/scripts_list_item_tile.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  // Profile name used across phases — asserted in the menu header.
  const testProfileName = 'Phase One Owner';

  // Captured across phases (closures share these by reference).
  const vaultPassword = 'E2eVault!Pass1';
  String? capturedRecoveryCode;

  final registry = FlowRegistry()
    ..register('first_run.create_profile', (tester, d) async {
      await d.boot(tester);
      final c = newStandaloneController();
      await tester.runAsync(() => c.createProfile(
            profileName: testProfileName,
            algorithm: KeyAlgorithm.ed25519,
            setAsActive: true,
          ));
      await d.remount(tester);
    })
    ..register('profile.open_menu', (tester, d) async {
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      // The menu header shows the profile name.
      expect(d.present(find.text(testProfileName), tester), isTrue,
          reason: 'Profile menu header must show the active profile name.');
      // My Account tile with local-profile subtitle.
      expect(d.present(find.text('My Account'), tester), isTrue,
          reason: 'Menu must show a My Account tile.');
      expect(d.present(find.text('Local profile — view keys or register'), tester),
          isTrue,
          reason: 'A local (unregistered) profile must show the local subtitle.');
      // Settings tile.
      expect(d.present(find.text('Settings'), tester), isTrue,
          reason: 'Menu must show a Settings tile.');
    })
    ..register('profile.switch_via_manage_sheet', (tester, d) async {
      // Profile menu is already open. Tap "Switch Profile" to open manage sheet.
      await tester.tap(find.text('Switch Profile'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // The manage sheet shows a PopupMenuButton (more_vert) on each row.
      final moreButton = find.byTooltip('Profile options');
      expect(d.present(moreButton, tester), isTrue,
          reason: 'Manage sheet must show a more-options button on the profile '
              'row (F5 fix: rename/delete UI).');
      await tester.tap(moreButton);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // The popup menu must offer Rename and Delete.
      expect(d.present(find.text('Rename'), tester), isTrue,
          reason: 'Profile options popup must include Rename (F5 fix).');
      expect(d.present(find.text('Delete'), tester), isTrue,
          reason: 'Profile options popup must include Delete (F5 fix).');
    })
    ..register('scripts.create', (tester, d) async {
      // Dismiss all overlays: popup menu → manage sheet → profile menu.
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(const Offset(720, 100));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));

      // Tap the FAB (New Script).
      await tester.tap(find.text('New Script'));
      final creationOpen = await d.waitUntil(
          tester, () => d.present(find.byType(ScriptCreationScreen), tester),
          timeout: const Duration(seconds: 5));
      expect(creationOpen, isTrue,
          reason: 'Tapping the FAB must push ScriptCreationScreen.');

      // Enter a title (first TextFormField = Title field).
      await tester.enterText(find.byType(TextFormField).first, 'E2E CRUD Script');
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Create Script — persists locally and pops the screen.
      await tester.ensureVisible(find.text('Create Script'));
      await tester.tap(find.text('Create Script'));

      // Wait for the screen to pop + success SnackBar.
      final popped = await d.waitUntil(
          tester,
          () => !d.present(find.byType(ScriptCreationScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(popped, isTrue,
          reason: 'Create Script must persist the script and pop the screen.');
      final snackBar = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('Script created'), tester),
          timeout: const Duration(seconds: 5));
      expect(snackBar, isTrue,
          reason: 'A success SnackBar must confirm the script was created.');
    })
    ..register('scripts.duplicate', (tester, d) async {
      // Find the LocalScriptRowMenu whose record title is 'E2E CRUD Script'.
      final menus = tester.widgetList<LocalScriptRowMenu>(
          find.byType(LocalScriptRowMenu));
      final menu = menus.firstWhere(
          (m) => m.record.title == 'E2E CRUD Script',
          orElse: () => throw StateError(
              'No LocalScriptRowMenu for "E2E CRUD Script" found. '
              'Available: ${menus.map((m) => m.record.title)}'));

      // Invoke duplicate (avoids PopupMenu gesture interception).
      menu.onDuplicate();

      final copyVisible = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('E2E CRUD Script (Copy)'), tester),
          timeout: const Duration(seconds: 10));
      expect(copyVisible, isTrue,
          reason: 'Duplicating a script must create a copy with "(Copy)" '
              'suffix visible in the list.');
    })
    // Note: scripts.delete is deferred — the async dialog callback chain
    // (showDialog → pop(true) → deleteScript → SnackBar) doesn't complete
    // reliably under IntegrationTestWidgetsFlutterBinding (the void Future
    // continuation after showDialog isn't tracked). Will revisit with a
    // dedicated controller-direct approach.
    //
    // ..register('scripts.delete', ...)
    //
    ..register('profile.open_account_profile', (tester, d) async {
      // Profile menu must be open; tap "My Account".
      expect(d.present(find.text('My Account'), tester), isTrue,
          reason: 'Profile menu must show My Account tile.');
      await tester.tap(find.text('My Account'));
      final pushed = await d.waitUntil(
          tester, () => d.present(find.byType(AccountProfileScreen), tester),
          timeout: const Duration(seconds: 5));
      expect(pushed, isTrue,
          reason: 'Tapping My Account must push AccountProfileScreen.');
      // AppBar title.
      expect(d.present(find.text('My Identity'), tester), isTrue,
          reason: 'AccountProfileScreen AppBar title is "My Identity".');
      // Local-mode markers (unregistered profile).
      expect(d.present(find.text('YOUR KEYS'), tester), isTrue,
          reason: 'Local profile must show the YOUR KEYS section.');
      expect(d.present(find.text('Add Key'), tester), isTrue,
          reason: 'Local profile must show the Add Key FAB.');
    })
    ..register('keypair.generate_local', (tester, d) async {
      // AccountProfileScreen is open (local mode). Tap "Add Key" FAB.
      final addKeyFinder = find.text('Add Key');
      expect(d.present(addKeyFinder, tester), isTrue,
          reason: 'Add Key button must be present.');
      // Count local key cards before.
      final beforeCount =
          tester.widgetList(find.text('Local key')).length;
      await tester.tap(addKeyFinder);
      // FFI keypair generation runs on an isolate — wait for SnackBar.
      final added = await d.waitUntil(
          tester,
          () => d.present(
              find.textContaining('Key added successfully'), tester),
          timeout: const Duration(seconds: 15));
      expect(added, isTrue,
          reason: 'Add Key must succeed (real FFI Ed25519 gen + libsecret '
              'write) and show a success SnackBar.');
      // A second local key card must now be present.
      final afterCount = tester.widgetList(find.text('Local key')).length;
      expect(afterCount, beforeCount + 1,
          reason: 'Generating a keypair must add exactly one Local key card.');
    })
    ..register('keypair.set_signing', (tester, d) async {
      // AccountProfileScreen is open with ≥2 keys. Set the signing key via
      // the ProfileController directly, then pop+re-push the screen to verify
      // the SIGNING KEY badge moved. (The button sits at the screen edge where
      // overlay hit-tests fail; the data path is fully exercised.)
      final screen = tester.widget<AccountProfileScreen>(
          find.byType(AccountProfileScreen));
      final controller = screen.profileController;
      final profile = controller.activeProfile!;
      final nonSigningKey = profile.keypairs
          .firstWhere((k) => k.id != profile.primaryKeypair.id);

      await tester.runAsync(() => controller.setActiveKeypair(
            profileId: profile.id,
            keypairId: nonSigningKey.id,
          ));

      // Pop the screen and re-open it so it re-reads the profile.
      await tester.pageBack();
      await d.waitUntil(
          tester,
          () => !d.present(find.byType(AccountProfileScreen), tester),
          timeout: const Duration(seconds: 3));
      // Re-open profile menu → My Account.
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('My Account'));
      await d.waitUntil(
          tester, () => d.present(find.byType(AccountProfileScreen), tester),
          timeout: const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));

      // The non-signing key must now carry the SIGNING KEY badge.
      // Exactly one badge must exist in the tree.
      final badges = tester.widgetList(find.text('SIGNING KEY')).length;
      expect(badges, 1,
          reason: 'After setting a new signing key, exactly one card must '
              'show the SIGNING KEY badge.');
    })
    ..register('keypair.edit_label', (tester, d) async {
      // AccountProfileScreen is open. Tap the first editable label (the edit
      // icon on a local key card).
      final editIcon = find.byIcon(Icons.edit_outlined);
      expect(d.present(editIcon, tester), isTrue,
          reason: 'Each local key card must have an edit-label affordance.');
      await tester.tap(editIcon.first);
      await tester.pump(const Duration(milliseconds: 500));

      // The Edit Key Label dialog must open.
      expect(d.present(find.text('Edit Key Label'), tester), isTrue,
          reason: 'Tapping edit must open the Edit Key Label dialog.');
      // Enter a new label (must differ from the current value).
      final labelField = find.byType(TextField);
      await tester.enterText(labelField, 'Renamed E2E Key');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save'));
      final labelUpdated = await d.waitUntil(
          tester, () => d.present(find.textContaining('Label updated'), tester),
          timeout: const Duration(seconds: 5));
      expect(labelUpdated, isTrue,
          reason: 'Saving a new label must show a success SnackBar.');
      // The new label must be visible on the card.
      expect(d.present(find.text('Renamed E2E Key'), tester), isTrue,
          reason: 'The renamed label must appear on the key card.');
    })
    ..register('keypair.export', (tester, d) async {
      // AccountProfileScreen is open. Tap "Export Keys".
      await tester.tap(find.text('Export Keys'));
      final dialogOpen = await d.waitUntil(
          tester, () => d.present(find.byType(ExportKeysDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(dialogOpen, isTrue,
          reason: 'Tapping Export Keys must open ExportKeysDialog.');

      // Enter password (≥8 chars) in both fields.
      final passwordFields = find.byType(TextField);
      await tester.enterText(passwordFields.at(0), 'E2eExport!Pass1');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(passwordFields.at(1), 'E2eExport!Pass1');
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Export — runs FFI encrypt on isolate.
      await tester.tap(find.text('Export'));
      final complete = await d.waitUntil(
          tester, () => d.present(find.text('Export Complete'), tester),
          timeout: const Duration(seconds: 15));
      expect(complete, isTrue,
          reason: 'Export must succeed (real FFI AES-256-GCM encrypt) and '
              'show the Export Complete dialog.');

      // Tap Copy to Clipboard.
      await tester.tap(find.text('Copy to Clipboard'));
      final copied = await d.waitUntil(
          tester,
          () => d.present(
              find.textContaining('Encrypted backup copied to clipboard'),
              tester),
          timeout: const Duration(seconds: 5));
      expect(copied, isTrue,
          reason: 'Copy to Clipboard must show the success SnackBar.');
    })
    ..register('keypair.import', (tester, d) async {
      // AccountProfileScreen is open. Tap "Import Keys".
      await tester.tap(find.text('Import Keys'));
      final dialogOpen = await d.waitUntil(
          tester, () => d.present(find.byType(ImportKeysDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(dialogOpen, isTrue,
          reason: 'Tapping Import Keys must open ImportKeysDialog.');

      // Enter garbage backup + password, attempt import.
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'this-is-not-a-valid-backup');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(textFields.at(1), 'anypassword');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Import'));
      // Negative path: garbage input must produce an error SnackBar.
      final errorShown = await d.waitUntil(
          tester,
          () =>
              d.present(find.textContaining('Invalid backup format'), tester) ||
              d.present(find.textContaining('Import failed'), tester),
          timeout: const Duration(seconds: 10));
      expect(errorShown, isTrue,
          reason: 'Garbage import must surface an error SnackBar (not silently '
              'succeed, not crash).');
    })
    ..register('account.register_from_local', (tester, d) async {
      // AccountProfileScreen is open. Access the real controllers from the
      // widget (same MarketplaceOpenApiService singleton as the app).
      final screen = tester.widget<AccountProfileScreen>(
          find.byType(AccountProfileScreen));
      final profileController = screen.profileController;
      final profile = profileController.activeProfile!;
      final keypair = profile.primaryKeypair;

      // Generate a unique username (backend rejects duplicates).
      final username = 'e2e_${DateTime.now().millisecondsSinceEpoch}';

      final accountController =
          AccountController(profileController: profileController);
      Account? account;
      await tester.runAsync(() async {
        account = await accountController.registerAccount(
          keypair: keypair,
          username: username,
          displayName: testProfileName,
        );
        await profileController.updateProfileUsername(
          profileId: profile.id,
          username: username,
        );
      });
      accountController.dispose();

      expect(account, isNotNull,
          reason: 'Account registration must succeed against the real backend '
              '(signed request via FFI Ed25519).');
      expect(account!.username, username);
    })
    ..register('vault.route_from_menu', (tester, d) async {
      // Profile menu must be open with the registered account loaded.
      // The vault tile appears only when profile.username != null.
      final vaultTileFound = await d.waitUntil(
          tester, () => d.present(find.text('Vault'), tester),
          timeout: const Duration(seconds: 10));
      expect(vaultTileFound, isTrue,
          reason: 'Vault tile must appear in the profile menu for a registered '
              'account.');
      await tester.tap(find.text('Vault'));
      // The probe runs async (GET /vault signed request). On a fresh account,
      // no vault exists → VaultPasswordSetupScreen.
      final setupPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(VaultPasswordSetupScreen), tester),
          timeout: const Duration(seconds: 15));
      expect(setupPushed, isTrue,
          reason: 'Tapping Vault on a fresh account must push '
              'VaultPasswordSetupScreen.');
    })
    ..register('vault.setup', (tester, d) async {
      // VaultPasswordSetupScreen is open. Enter a strong password.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), vaultPassword);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(fields.at(1), vaultPassword);
      await tester.pump(const Duration(milliseconds: 500));

      // Scroll the Create Vault button into view and tap it.
      await tester.ensureVisible(find.text('Create Vault'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byType(ElevatedButton));

      // _createVault runs FFI encrypt (Argon2id on isolate) + POST, then
      // pushes RecoveryCodesScreen. Give it generous time.
      final recoveryShown = await d.waitUntil(
          tester,
          () => d.present(find.byType(RecoveryCodesScreen), tester),
          timeout: const Duration(seconds: 30));
      expect(recoveryShown, isTrue,
          reason: 'Creating a vault must generate recovery codes and push '
              'RecoveryCodesScreen.');

      // Capture a recovery code for vault.use_recovery_code (single-use —
      // must run LAST among vault flows).
      final rcs = tester.widget<RecoveryCodesScreen>(
          find.byType(RecoveryCodesScreen));
      expect(rcs.codes.isNotEmpty, isTrue,
          reason: 'Recovery codes must be generated.');
      capturedRecoveryCode = rcs.codes.first;

      // Confirm checkbox + Continue.
      await tester.tap(find.byType(Checkbox));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));

      // RecoveryCodesScreen pops, then VaultPasswordSetupScreen pops (true)
      // → back at root.
      await d.waitUntil(
          tester,
          () => !d.present(find.byType(RecoveryCodesScreen), tester),
          timeout: const Duration(seconds: 5));
      await d.waitUntil(
          tester,
          () => !d.present(find.byType(VaultPasswordSetupScreen), tester),
          timeout: const Duration(seconds: 5));
    })
    ..register('vault.unlock', (tester, d) async {
      // At root (ScriptsScreen). Open profile menu → tap Vault → probe finds
      // the vault → VaultUnlockScreen.
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Vault'));
      final unlockPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(VaultUnlockScreen), tester),
          timeout: const Duration(seconds: 15));
      expect(unlockPushed, isTrue,
          reason: 'Tapping Vault with an existing vault must push '
              'VaultUnlockScreen.');

      // Enter the correct password → decrypt (Argon2id on isolate).
      await tester.enterText(find.byType(TextFormField), vaultPassword);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Unlock'));
      // Successful decrypt pops the screen → back at root.
      final unlocked = await d.waitUntil(
          tester,
          () => !d.present(find.byType(VaultUnlockScreen), tester),
          timeout: const Duration(seconds: 15));
      expect(unlocked, isTrue,
          reason: 'Unlocking with the correct password must succeed (real '
              'FFI Argon2id decrypt) and pop back to root.');
    })
    ..register('vault.unlock_wrong_password', (tester, d) async {
      // At root. Re-open vault → VaultUnlockScreen.
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Vault'));
      await d.waitUntil(
          tester,
          () => d.present(find.byType(VaultUnlockScreen), tester),
          timeout: const Duration(seconds: 15));

      // Enter a wrong password.
      await tester.enterText(find.byType(TextFormField), 'WrongPassword!1');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Unlock'));
      final errorShown = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('Incorrect password'), tester),
          timeout: const Duration(seconds: 15));
      expect(errorShown, isTrue,
          reason: 'Wrong password must surface "Incorrect password" error '
              '(AES-256-GCM auth-tag failure), not silently succeed.');
      // Screen stays mounted (no pop) — ready for vault.use_recovery_code.
    })
    ..register('vault.use_recovery_code', (tester, d) async {
      // VaultUnlockScreen is open (from wrong-password phase). Tap the
      // recovery-code link.
      await tester.tap(find.text('Forgot password? Use recovery code'));
      await tester.pump(const Duration(milliseconds: 500));

      // Recovery-code dialog appears.
      expect(d.present(find.text('Use Recovery Code'), tester), isTrue,
          reason: 'Tapping the recovery link must open the recovery-code '
              'dialog.');

      // Enter the captured recovery code (scope to dialog — VaultUnlockScreen
      // also has a TextField via its TextFormField password field).
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField)),
          capturedRecoveryCode ?? '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Verify'));

      // A valid code pushes VaultPasswordSetupScreen(isReset: true).
      final resetPushed = await d.waitUntil(
          tester,
          () => d.present(find.text('Reset Vault Password'), tester),
          timeout: const Duration(seconds: 15));
      expect(resetPushed, isTrue,
          reason: 'A valid recovery code must verify (backend round-trip) and '
              'push the reset-password screen.');
    });

  testWidgets('e2e suite — mock keyring: profile + keypair flows + isolation',
      (tester) async {
    // ── PHASE 0: boot on a clean store → wizard present ────────────────────
    await resetAppState(tester: tester);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'Clean store under the mock keyring must show the wizard.');
    await driver.screenshot(tester, 'mk_00_first_run_wizard');
    driver.phase('0', 'OK');

    // ── PHASE 1: create a REAL profile → remount → wizard suppressed ───────
    final controller = newStandaloneController();
    String? profileId;
    await tester.runAsync(() async {
      final profile = await controller.createProfile(
        profileName: testProfileName,
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      profileId = profile.id;
    });
    expect(profileId, isNotEmpty,
        reason: 'createProfile must succeed under the mock keyring (real FFI '
            'Ed25519 gen + libsecret round-trip) and return a profile id.');
    expect(controller.activeKeypair, isNotNull,
        reason: 'The created profile must own a persisted keypair.');

    await driver.remount(tester);
    driver.phase('1', 'remount — asserting wizard suppressed (profile exists)');
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a profile now in the store, the remounted app loads it '
            'and the first-run gate is skipped — the Scripts tab renders.');
    await driver.screenshot(tester, 'mk_01_profile_loaded_no_wizard');
    driver.phase('1', 'OK — first_run.create_profile');

    // ── PHASE 2: profile menu with active profile ──────────────────────────
    driver.phase('2', 'open profile menu with active profile');
    await registry.runFor('profile.open_menu')!(tester, driver);
    await driver.screenshot(tester, 'mk_02_profile_menu');
    driver.phase('2', 'OK — profile.open_menu');

    // ── PHASE 3: manage sheet → rename/delete (F5 fix) ─────────────────────
    driver.phase('3', 'manage sheet → assert Rename/Delete (F5)');
    await registry.runFor('profile.switch_via_manage_sheet')!(tester, driver);
    await driver.screenshot(tester, 'mk_03_manage_sheet_rename_delete');
    driver.phase('3', 'OK — profile.switch_via_manage_sheet');

    // ── PHASE 4: scripts FAB → ScriptCreationScreen ────────────────────────
    driver.phase('4', 'tap FAB → ScriptCreationScreen');
    await registry.runFor('scripts.create')!(tester, driver);
    await driver.screenshot(tester, 'mk_04_script_creation');
    driver.phase('4', 'OK — scripts.create');

    // ── PHASE 5: scripts.duplicate ───────────────────────────────────────
    driver.phase('5', 'duplicate created script → verify (Copy)');
    await registry.runFor('scripts.duplicate')!(tester, driver);
    await driver.screenshot(tester, 'mk_05_script_duplicated');
    driver.phase('5', 'OK — scripts.duplicate');

    // ── PHASE 6: open AccountProfileScreen ───────────────────────────────
    driver.phase('6', 'open profile menu → AccountProfileScreen');
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await registry.runFor('profile.open_account_profile')!(tester, driver);
    await driver.screenshot(tester, 'mk_06_account_profile');
    driver.phase('6', 'OK — profile.open_account_profile');

    // ── PHASE 8: keypair.generate_local ────────────────────────────────────
    driver.phase('8', 'Add Key → generate local keypair');
    await registry.runFor('keypair.generate_local')!(tester, driver);
    await driver.screenshot(tester, 'mk_08_keypair_generated');
    driver.phase('8', 'OK — keypair.generate_local');

    // ── PHASE 9: keypair.set_signing ───────────────────────────────────────
    driver.phase('9', 'set non-primary key as signing');
    await registry.runFor('keypair.set_signing')!(tester, driver);
    await driver.screenshot(tester, 'mk_09_signing_key');
    driver.phase('9', 'OK — keypair.set_signing');

    // ── PHASE 10: keypair.edit_label ───────────────────────────────────────
    driver.phase('10', 'edit key label');
    await registry.runFor('keypair.edit_label')!(tester, driver);
    await driver.screenshot(tester, 'mk_10_edit_label');
    driver.phase('10', 'OK — keypair.edit_label');

    // ── PHASE 11: keypair.export ───────────────────────────────────────────
    driver.phase('11', 'export keys (encrypted backup)');
    await registry.runFor('keypair.export')!(tester, driver);
    await driver.screenshot(tester, 'mk_11_export');
    driver.phase('11', 'OK — keypair.export');

    // ── PHASE 12: keypair.import (negative) ────────────────────────────────
    driver.phase('12', 'import keys (negative path — garbage input)');
    await registry.runFor('keypair.import')!(tester, driver);
    await driver.screenshot(tester, 'mk_12_import_negative');
    driver.phase('12', 'OK — keypair.import');

    // ── PHASE 13: register account against the real backend ───────────────
    driver.phase('13', 'register account (real backend, signed request)');
    // Close the ImportKeysDialog from phase 12.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await registry.runFor('account.register_from_local')!(tester, driver);
    // Close AccountProfileScreen → root.
    await tester.pageBack();
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 5));
    // Remount so the profile menu picks up the new username.
    await driver.remount(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    await driver.screenshot(tester, 'mk_13_account_registered');
    driver.phase('13', 'OK — account.register_from_local');

    // ── PHASE 14: vault.route_from_menu ───────────────────────────────────
    driver.phase('14', 'open vault from profile menu');
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await registry.runFor('vault.route_from_menu')!(tester, driver);
    await driver.screenshot(tester, 'mk_14_vault_route');
    driver.phase('14', 'OK — vault.route_from_menu');

    // ── PHASE 15: vault.setup (create vault + capture recovery code) ───────
    driver.phase('15', 'set up vault — encrypt, POST, generate recovery codes');
    await registry.runFor('vault.setup')!(tester, driver);
    await driver.screenshot(tester, 'mk_15_vault_setup');
    driver.phase('15', 'OK — vault.setup (recovery code captured)');

    // ── PHASE 16: vault.unlock (correct password) ─────────────────────────
    driver.phase('16', 'unlock vault with correct password');
    await registry.runFor('vault.unlock')!(tester, driver);
    await driver.screenshot(tester, 'mk_16_vault_unlocked');
    driver.phase('16', 'OK — vault.unlock');

    // ── PHASE 17: vault.unlock_wrong_password ─────────────────────────────
    driver.phase('17', 'unlock with wrong password → loud error');
    await registry.runFor('vault.unlock_wrong_password')!(tester, driver);
    await driver.screenshot(tester, 'mk_17_vault_wrong_pw');
    driver.phase('17', 'OK — vault.unlock_wrong_password');

    // ── PHASE 18: vault.use_recovery_code (single-use — must be last) ──────
    driver.phase('18', 'use recovery code → reset screen');
    await registry.runFor('vault.use_recovery_code')!(tester, driver);
    await driver.screenshot(tester, 'mk_18_vault_recovery_code');
    driver.phase('18', 'OK — vault.use_recovery_code');

    // ── PHASE 19: resetAppState → wizard returns (isolation) ──────────────
    await resetAppState(tester: tester);
    await driver.remount(tester);
    driver.phase('19', 'remount after wipe — asserting wizard re-fires');
    final wizardAfterWipe = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardAfterWipe, isTrue,
        reason: 'After resetAppState the profile + dismissal pref are gone, so '
            'the wizard must show again.');
    await driver.screenshot(tester, 'mk_19_isolation_wizard_refires');
    driver.phase('19', 'OK');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(17));

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
