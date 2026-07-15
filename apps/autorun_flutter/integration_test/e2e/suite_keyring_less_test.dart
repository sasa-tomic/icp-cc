// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 1 (keyring-less / StorageUnavailable).
///
/// Boots the REAL app ONCE, then runs phases with `resetAppState` + remount
/// between them. This is the fast shared-boot harness: one build/load for the
/// whole keyring-less surface instead of one per file.
///
/// Run: `just e2e-desktop` (PASS 1 — no Secret Service required).
///
/// Phase-1 scope: prove the harness MECHANISM (boot, isolation, re-fire of the
/// first-run gate). Deep per-flow assertions land in Phase 2 as flows migrate
/// into the [FlowRegistry].
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  // Register the smoke flow so it counts as covered in the catalog.
  final registry = FlowRegistry()
    ..register('first_run.dismiss_wizard', (tester, d) async {
      await d.boot(tester);
      expect(d.present(find.byType(UnifiedSetupWizard), tester), isTrue,
          reason: 'first_run.dismiss_wizard: a clean store must show the '
              'setup wizard on boot.');
      await d.dismissWizard(tester);
    });

  testWidgets('e2e suite — keyring-less: shared boot + isolation', (tester) async {
    // ── PHASE 0: clean slate + first boot ──────────────────────────────────
    // No Secret Service on this surface → no secrets can exist (the readiness
    // gate blocks profile creation), so skip the libsecret wipe.
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'On a wiped store with no Secret Service the first-run gate '
            'must show the setup wizard (the WU-S2 readiness panel renders '
            'inside it).');
    await driver.screenshot(tester, 'kl_00_first_run_wizard');
    driver.phase('0', 'OK');

    // ── PHASE 1: resetAppState + remount re-fires the gate (isolation) ─────
    // No dismiss needed first: remount (pumpWidget) wholesale replaces the
    // tree, disposing the wizard route. (Dismissing would set the dismissal
    // pref and race with resetAppState's wipe of it.)
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.remount(tester);
    driver.phase('1', 'remount — asserting first-run gate re-fired');
    final wizardOnRemount = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnRemount, isTrue,
        reason: 'resetAppState + remount must reproduce a first-run boot: the '
            'dismissal pref was wiped, so the wizard shows again. This is the '
            'isolation guarantee that lets one booted app run many flows.');
    await driver.screenshot(tester, 'kl_01_remount_refires_gate');
    driver.phase('1', 'OK');

    // ── PHASE 2: coverage contract sanity ──────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('2', 'coverage ${cov.implemented}/${cov.total} implemented '
        '(Phase 1 wires smoke; Phase 2 migrates the rest)');
    expect(cov.total, greaterThan(90), reason: 'catalog must list all flows.');
    expect(cov.implemented, greaterThanOrEqualTo(1));

    // ignore: avoid_print
    print('SUITE_KEYRING_LESS: PASS — shared boot + isolation proven.');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
