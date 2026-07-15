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
///   scripts.create
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

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
      // Tap the barrier/scrim area (top-center, outside any bottom sheet).
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(const Offset(720, 100));
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Ensure ScriptsScreen is visible.
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));

      // Tap the FAB (New Script) — it renders as an AnimatedFab with text label.
      final fab = find.text('New Script');
      expect(d.present(fab, tester), isTrue,
          reason: 'ScriptsScreen must show a New Script FAB.');
      await tester.tap(fab);
      final creationOpen = await d.waitUntil(
          tester, () => d.present(find.byType(ScriptCreationScreen), tester),
          timeout: const Duration(seconds: 5));
      expect(creationOpen, isTrue,
          reason: 'Tapping the FAB must push ScriptCreationScreen.');
    });

  testWidgets('e2e suite — mock keyring: profile flows + isolation',
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

    // ── PHASE 5: resetAppState → wizard returns (isolation) ────────────────
    await resetAppState(tester: tester);
    await driver.remount(tester);
    driver.phase('5', 'remount after wipe — asserting wizard re-fires');
    final wizardAfterWipe = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardAfterWipe, isTrue,
        reason: 'After resetAppState the profile + dismissal pref are gone, so '
            'the wizard must show again.');
    await driver.screenshot(tester, 'mk_05_isolation_wizard_refires');
    driver.phase('5', 'OK');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(4));

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
