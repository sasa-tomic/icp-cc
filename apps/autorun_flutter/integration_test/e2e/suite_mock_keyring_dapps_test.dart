// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 3 (mock Secret Service / daps + wizard + shortcut split-off).
///
/// Boots the REAL app ONCE under the mock keyring
/// (`scripts/run-with-mock-keyring.sh`), drives the FULL first-run wizard
/// (creating a real profile + registering a real backend account), then
/// runs the dapp trust/copy-principal flows and the Ctrl+S save-profile
/// shortcut flow against the registered state.
///
/// These flows were split out of `suite_mock_keyring_test.dart` because
/// that suite's single `testWidgets` body was approaching the flutter_test
/// binding's stability threshold (the documented "Cannot close sink while
/// adding stream" crash past ~30 phases — same root cause as
/// `suite_keyring_less_test.dart` per OPEN_ISSUES E2E-PHASE56+57). The
/// profile/account/keypair/vault flows stay in the original suite; the
/// wizard + dapp + shortcut flows move here.
///
/// Run: `just e2e-desktop` (PASS 2b — wrapped in the mock Secret Service,
/// same as PASS 2). Also runnable standalone via
/// `just e2e-one first_run.create_profile_with_account mock-keyring-dapps`
/// (or any other flow id in this suite).
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'mock_keyring_dapps_flows.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  final registry = buildMockKeyringDappsRegistry();

  testWidgets(
      'e2e suite — mock keyring dapps + shortcut: trust/copy/save flows',
      (tester) async {
    // ── PHASE 0: clean slate + boot → wizard present ──────────────────────
    await resetAppState(tester: tester);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'Clean store under the mock keyring must show the wizard.');
    driver.phase('0', 'OK');

    // ── PHASE 1: first_run.create_profile_with_account ───────────────────
    // Drive the FULL wizard UI flow (display name + unique username → Get
    // Started → success → Start Exploring). This is BOTH the
    // first_run.create_profile_with_account flow AND the profile-setup
    // phase for this suite's subsequent dapp/shortcut flows — the wizard
    // creates a real profile + registers a real backend account, which is
    // exactly the precondition the dapp flows need.
    driver.phase('1', 'wizard: display name + username → account created');
    await registry.runFor('first_run.create_profile_with_account')!(tester, driver);
    if (shouldStopAfter('first_run.create_profile_with_account')) return;
    driver.phase('1', 'OK — first_run.create_profile_with_account');

    // Verify the profile is loaded (the wizard flow already asserted the
    // persisted state; here we just confirm the shell is interactive).
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a profile + registered account in the store, the '
            'remounted app loads it and skips the first-run gate.');
    driver.phase('1b', 'profile + account loaded — wizard popped');

    // ── PHASE 2: dapps.copy_principal ─────────────────────────────────────
    driver.phase('2', 'dapps: copy principal (auth-status chip → clipboard)');
    await registry.runFor('dapps.copy_principal')!(tester, driver);
    if (shouldStopAfter('dapps.copy_principal')) return;
    driver.phase('2', 'OK — dapps.copy_principal');

    // ── PHASE 3: dapps.trust_grant ────────────────────────────────────────
    driver.phase('3', 'dapps: grant trust (Trust dialog → Trusted chip)');
    await registry.runFor('dapps.trust_grant')!(tester, driver);
    if (shouldStopAfter('dapps.trust_grant')) return;
    driver.phase('3', 'OK — dapps.trust_grant');

    // ── PHASE 4: dapps.manage_trust_revoke ────────────────────────────────
    driver.phase('4', 'dapps: manage trust → revoke (chip disappears)');
    await registry.runFor('dapps.manage_trust_revoke')!(tester, driver);
    if (shouldStopAfter('dapps.manage_trust_revoke')) return;
    driver.phase('4', 'OK — dapps.manage_trust_revoke');

    // ── PHASE 5: shortcut.account_save ────────────────────────────────────
    driver.phase('5', 'shortcut: Ctrl+S save profile');
    await registry.runFor('shortcut.account_save')!(tester, driver);
    if (shouldStopAfter('shortcut.account_save')) return;
    driver.phase('5', 'OK — shortcut.account_save');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(5),
        reason: 'mock-keyring-dapps must cover at least 5 flows.');

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING_DAPS: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
