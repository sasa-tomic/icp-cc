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
///   scripts.create, scripts.duplicate, scripts.edit, scripts.copy_source,
///   profile.open_account_profile, keypair.generate_local, keypair.set_signing,
///   keypair.edit_label, keypair.export, keypair.import, passkey.unsupported_linux,
///   account.register_from_local, account.refresh, account.edit_profile,
///   keypair.generate_registered, keypair.delete_registered,
///   vault.route_from_menu, vault.setup, vault.unlock,
///   vault.unlock_wrong_password, vault.use_recovery_code
///
/// Split-off dapp + shortcut flows live in `suite_mock_keyring_dapps_test.dart`
/// (dapps.copy_principal, dapps.trust_grant, dapps.manage_trust_revoke,
/// shortcut.account_save) — moved out to dodge the keyring-less suite's
/// binding stability threshold (the documented "Cannot close sink while
/// adding stream" crash past ~30 phases).
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'mock_keyring_flows.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  const testProfileName = kMockKeyringProfileName;
  final suiteState = MockKeyringSuiteState();
  final registry = buildMockKeyringRegistry(suiteState);

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
    if (shouldStopAfter('profile.open_menu')) return;
    await driver.screenshot(tester, 'mk_02_profile_menu');
    driver.phase('2', 'OK — profile.open_menu');

    // ── PHASE 3: manage sheet → rename/delete (F5 fix) ─────────────────────
    driver.phase('3', 'manage sheet → assert Rename/Delete (F5)');
    await registry.runFor('profile.switch_via_manage_sheet')!(tester, driver);
    if (shouldStopAfter('profile.switch_via_manage_sheet')) return;
    await driver.screenshot(tester, 'mk_03_manage_sheet_rename_delete');
    driver.phase('3', 'OK — profile.switch_via_manage_sheet');

    // ── PHASE 4: scripts FAB → ScriptCreationScreen ────────────────────────
    driver.phase('4', 'tap FAB → ScriptCreationScreen');
    await registry.runFor('scripts.create')!(tester, driver);
    if (shouldStopAfter('scripts.create')) return;
    await driver.screenshot(tester, 'mk_04_script_creation');
    driver.phase('4', 'OK — scripts.create');

    // ── PHASE 5: scripts.duplicate ───────────────────────────────────────
    driver.phase('5', 'duplicate created script → verify (Copy)');
    await registry.runFor('scripts.duplicate')!(tester, driver);
    if (shouldStopAfter('scripts.duplicate')) return;
    await driver.screenshot(tester, 'mk_05_script_duplicated');
    driver.phase('5', 'OK — scripts.duplicate');

    // ── PHASE 5b: scripts.edit ───────────────────────────────────────────
    driver.phase('5b', 'edit script → ScriptEditorDialog → Cancel');
    await registry.runFor('scripts.edit')!(tester, driver);
    if (shouldStopAfter('scripts.edit')) return;
    driver.phase('5b', 'OK — scripts.edit');

    // ── PHASE 5c: scripts.copy_source ────────────────────────────────────
    driver.phase('5c', 'copy source → SnackBar');
    await registry.runFor('scripts.copy_source')!(tester, driver);
    if (shouldStopAfter('scripts.copy_source')) return;
    driver.phase('5c', 'OK — scripts.copy_source');

    // Clear stale SnackBars from scripts.create/duplicate/copy so they don't
    // block the SnackBar queue during keypair flows.
    final ctx = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    await tester.pump(const Duration(milliseconds: 500));

    // ── PHASE 6: open AccountProfileScreen ───────────────────────────────
    driver.phase('6', 'open profile menu → AccountProfileScreen');
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await registry.runFor('profile.open_account_profile')!(tester, driver);
    if (shouldStopAfter('profile.open_account_profile')) return;
    await driver.screenshot(tester, 'mk_06_account_profile');
    driver.phase('6', 'OK — profile.open_account_profile');

    // ── PHASE 8: keypair.generate_local ────────────────────────────────────
    driver.phase('8', 'Add Key → generate local keypair');
    await registry.runFor('keypair.generate_local')!(tester, driver);
    if (shouldStopAfter('keypair.generate_local')) return;
    await driver.screenshot(tester, 'mk_08_keypair_generated');
    driver.phase('8', 'OK — keypair.generate_local');

    // ── PHASE 9: keypair.set_signing ───────────────────────────────────────
    driver.phase('9', 'set non-primary key as signing');
    await registry.runFor('keypair.set_signing')!(tester, driver);
    if (shouldStopAfter('keypair.set_signing')) return;
    await driver.screenshot(tester, 'mk_09_signing_key');
    driver.phase('9', 'OK — keypair.set_signing');

    // ── PHASE 10: keypair.edit_label ───────────────────────────────────────
    driver.phase('10', 'edit key label');
    await registry.runFor('keypair.edit_label')!(tester, driver);
    if (shouldStopAfter('keypair.edit_label')) return;
    await driver.screenshot(tester, 'mk_10_edit_label');
    driver.phase('10', 'OK — keypair.edit_label');

    // ── PHASE 11: keypair.export ───────────────────────────────────────────
    driver.phase('11', 'export keys (encrypted backup)');
    await registry.runFor('keypair.export')!(tester, driver);
    if (shouldStopAfter('keypair.export')) return;
    await driver.screenshot(tester, 'mk_11_export');
    driver.phase('11', 'OK — keypair.export');

    // ── PHASE 12: keypair.import (negative) ────────────────────────────────
    driver.phase('12', 'import keys (negative path — garbage input)');
    await registry.runFor('keypair.import')!(tester, driver);
    if (shouldStopAfter('keypair.import')) return;
    await driver.screenshot(tester, 'mk_12_import_negative');
    driver.phase('12', 'OK — keypair.import');

    // ── PHASE 12b: passkey.unsupported_linux ──────────────────────────────
    driver.phase('12b', 'passkey unsupported hint (Linux desktop)');
    await registry.runFor('passkey.unsupported_linux')!(tester, driver);
    if (shouldStopAfter('passkey.unsupported_linux')) return;
    driver.phase('12b', 'OK — passkey.unsupported_linux');

    // ── PHASE 13: register account against the real backend ───────────────
    driver.phase('13', 'register account (real backend, signed request)');
    // Close the ImportKeysDialog from phase 12.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await registry.runFor('account.register_from_local')!(tester, driver);
    if (shouldStopAfter('account.register_from_local')) return;
    // Dismiss any SnackBar/dialog the registration surfaced before navigating
    // away — the overlay's AbsorbPointer chain would otherwise intercept the
    // Back-button tap (now a fatal `hitTestWarning`).
    await driver.dismissOverlays(tester);
    // Close AccountProfileScreen → root, IF it's still on stage. The
    // controller-direct `registerAccount` call mutates profile.username,
    // which can trigger a reactive rebuild that pops AccountProfileScreen
    // out from under us. Calling pageBack() with no Back button on stage
    // throws a fatal TestFailure — guard with a presence check first.
    if (driver.present(find.byType(AccountProfileScreen), tester)) {
      await tester.pageBack();
      await driver.waitUntil(
          tester, () => driver.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));
    }
    // Remount so the profile menu picks up the new username.
    await driver.remount(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    await driver.screenshot(tester, 'mk_13_account_registered');
    driver.phase('13', 'OK — account.register_from_local');

    // ── PHASE 13b: account.refresh — tap refresh on AccountProfileScreen ──
    driver.phase('13b', 'refresh account (tap refresh icon)');
    await registry.runFor('account.refresh')!(tester, driver);
    if (shouldStopAfter('account.refresh')) return;
    driver.phase('13b', 'OK — account.refresh');

    // ── PHASE 13c: account.edit_profile — edit bio + Save Changes ─────────
    driver.phase('13c', 'edit account profile (bio → Save Changes)');
    await registry.runFor('account.edit_profile')!(tester, driver);
    if (shouldStopAfter('account.edit_profile')) return;
    driver.phase('13c', 'OK — account.edit_profile');

    // ── PHASE 13d: keypair.generate_registered — add backend key ───────────
    driver.phase('13d', 'generate registered keypair (signed POST)');
    await registry.runFor('keypair.generate_registered')!(tester, driver);
    if (shouldStopAfter('keypair.generate_registered')) return;
    driver.phase('13d', 'OK — keypair.generate_registered');

    // ── PHASE 13e: keypair.delete_registered — soft-delete a key ───────────
    driver.phase('13e', 'delete registered keypair (isActive=false)');
    await registry.runFor('keypair.delete_registered')!(tester, driver);
    if (shouldStopAfter('keypair.delete_registered')) return;
    driver.phase('13e', 'OK — keypair.delete_registered');

    // ── PHASE 14: vault.route_from_menu ───────────────────────────────────
    driver.phase('14', 'open vault from profile menu');
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await registry.runFor('vault.route_from_menu')!(tester, driver);
    if (shouldStopAfter('vault.route_from_menu')) return;
    await driver.screenshot(tester, 'mk_14_vault_route');
    driver.phase('14', 'OK — vault.route_from_menu');

    // ── PHASE 15: vault.setup (create vault + capture recovery code) ───────
    driver.phase('15', 'set up vault — encrypt, POST, generate recovery codes');
    await registry.runFor('vault.setup')!(tester, driver);
    if (shouldStopAfter('vault.setup')) return;
    await driver.screenshot(tester, 'mk_15_vault_setup');
    driver.phase('15', 'OK — vault.setup (recovery code captured)');

    // ── PHASE 16: vault.unlock (correct password) ─────────────────────────
    driver.phase('16', 'unlock vault with correct password');
    await registry.runFor('vault.unlock')!(tester, driver);
    if (shouldStopAfter('vault.unlock')) return;
    await driver.screenshot(tester, 'mk_16_vault_unlocked');
    driver.phase('16', 'OK — vault.unlock');

    // ── PHASE 17: vault.unlock_wrong_password ─────────────────────────────
    driver.phase('17', 'unlock with wrong password → loud error');
    await registry.runFor('vault.unlock_wrong_password')!(tester, driver);
    if (shouldStopAfter('vault.unlock_wrong_password')) return;
    await driver.screenshot(tester, 'mk_17_vault_wrong_pw');
    driver.phase('17', 'OK — vault.unlock_wrong_password');

    // ── PHASE 18: vault.use_recovery_code (single-use — must be last) ──────
    driver.phase('18', 'use recovery code → reset screen');
    await registry.runFor('vault.use_recovery_code')!(tester, driver);
    if (shouldStopAfter('vault.use_recovery_code')) return;
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
    expect(cov.implemented, greaterThanOrEqualTo(25),
        reason: 'mock-keyring must cover at least 25 flows.');

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
