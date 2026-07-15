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
/// Phase-1 scope: prove the harness mechanism UNDER a working Secret Service —
/// a real Ed25519 keypair persists through libsecret and phase isolation holds.
/// Deep per-flow assertions land in Phase 2.
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/profile_repository.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  // A standalone controller shares the same on-disk store + process-global
  // libsecret as the booted app (proven pattern from h_vault_lifecycle_test).
  // Used here to create a REAL profile/keypair that a remounted app then sees.
  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  final registry = FlowRegistry()
    ..register('first_run.create_profile', (tester, d) async {
      await d.boot(tester);
      final c = newStandaloneController();
      await tester.runAsync(() => c.createProfile(
            profileName: 'E2E Smoke',
            algorithm: KeyAlgorithm.ed25519,
            setAsActive: true,
          ));
      await d.remount(tester);
    });

  testWidgets('e2e suite — mock keyring: keypair persists + isolation holds',
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
    // createProfile hits libsecret (mock keyring). If it succeeds the keypair
    // genuinely persisted; a failure throws (no silent error).
    final controller = newStandaloneController();
    String? profileId;
    await tester.runAsync(() async {
      final profile = await controller.createProfile(
        profileName: 'Phase One Owner',
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

    // No dismiss first: remount replaces the tree (wizard route disposed), and
    // the fresh app controller now sees the created profile → gate skips.
    await driver.remount(tester);
    driver.phase('1', 'remount — asserting wizard suppressed (profile exists)');
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a profile now in the store, the remounted app loads it '
            'and the first-run gate is skipped — the Scripts tab renders '
            'directly. This proves the keypair survived the libsecret '
            'round-trip AND the app honours an existing profile.');
    await driver.screenshot(tester, 'mk_01_profile_loaded_no_wizard');
    driver.phase('1', 'OK');

    // ── PHASE 2: resetAppState → wizard returns (isolation) ────────────────
    await resetAppState(tester: tester);
    await driver.remount(tester);
    driver.phase('2', 'remount after wipe — asserting wizard re-fires');
    final wizardAfterWipe = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardAfterWipe, isTrue,
        reason: 'After resetAppState the profile + dismissal pref are gone, so '
            'the wizard must show again — proving phases do not leak state.');
    await driver.screenshot(tester, 'mk_02_isolation_wizard_refires');
    driver.phase('2', 'OK');

    // ── PHASE 3: coverage contract sanity ──────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('3', 'coverage ${cov.implemented}/${cov.total} implemented');
    expect(cov.implemented, greaterThanOrEqualTo(1));

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING: PASS — keypair persists + isolation proven.');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
