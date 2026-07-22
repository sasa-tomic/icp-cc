// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 2c (mock Secret Service / identity + scripts publish flows).
///
/// Boots the REAL app ONCE under the mock keyring
/// (`scripts/run-with-mock-keyring.sh`), then runs three flows that each
/// need a Secret Service for keypair generation + signing:
///
///   PHASE 1 — `account.register_from_publish` (group D account)
///     A LOCAL-ONLY profile tries to publish → AccountRegistrationWizard
///     pushes directly (QW-1 removed the intermediate prompt) → real
///     `registerAccount` round-trip.
///
///   PHASE 2 — `scripts.publish` (group E scripts)
///     Now that the profile has a registered account, create a local script
///     → invoke `LocalScriptRowMenu.onPublish` → fill QuickUploadDialog →
///     real signed `uploadScript` round-trip → success SnackBar.
///
///   PHASE 3 — `profile.create_via_menu_dialog` (group B profile)
///     The Phase-O UX-PMD-1 fix flow: open profile menu → "Switch Profile"
///     → manage sheet → "Create New Profile" → UnifiedSetupWizard pushes
///     (the post-fix navigator capture path) → fill display name + username
///     → real `createProfile` + `registerAccount` round-trip → success.
///
/// These three flows live in a dedicated 3-phase mini-suite (mirroring the
/// Phase N `suite_mock_keyring_dapps_test.dart` split pattern) so the
/// existing keyring-less + mock-keyring suites stay below the documented
/// flutter_test binding stability threshold (see OPEN_ISSUES
/// E2E-PHASE56+57). State evolves naturally: local-only → registered →
/// second profile, so no resetAppState between phases.
///
/// Run: `just e2e-desktop` (PASS 2c — wrapped in the mock Secret Service,
/// same as PASS 2). Also runnable standalone via
/// `just e2e-one <flow-id> mock-keyring-identity` for any of the three
/// flow ids above.
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'mock_keyring_identity_flows.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  const firstProfileName = kIdentityProfileName;

  final registry = buildMockKeyringIdentityRegistry();

  // ── Shared helpers (top-level functions below main) ───────────────────

  testWidgets(
      'e2e suite — mock keyring identity: register_from_publish + publish + '
      'create_via_menu_dialog', (tester) async {
    // ── PHASE 0: clean slate + boot + create first LOCAL-ONLY profile ──
    await resetAppState(tester: tester);
    await driver.boot(tester);
    driver.phase('0', 'booted — creating local-only profile via controller');

    // Pre-create a LOCAL-ONLY profile (no username) so PHASE 1 hits the
    // "no account → register prompt" branch of _publishToMarketplace.
    // Using the controller directly keeps PHASE 0 fast; the wizard UI is
    // exercised end-to-end in PHASE 3 below.
    final setupController = newStandaloneController();
    await tester.runAsync(() => setupController.createProfile(
          profileName: firstProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await driver.remount(tester);
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a local-only profile in the store, the remounted app '
            'loads it and skips the first-run gate.');
    driver.phase('0', 'OK — local-only profile loaded');

    // ── PHASE 1: account.register_from_publish ───────────────────────────
    driver.phase('1', 'account: register from publish prompt');
    await registry.runFor('account.register_from_publish')!(tester, driver);
    if (shouldStopAfter('account.register_from_publish')) return;
    driver.phase('1', 'OK — account.register_from_publish');

    // ── PHASE 2: scripts.publish ──────────────────────────────────────────
    driver.phase('2', 'scripts: publish via QuickUploadDialog');
    await registry.runFor('scripts.publish')!(tester, driver);
    if (shouldStopAfter('scripts.publish')) return;
    driver.phase('2', 'OK — scripts.publish');

    // ── PHASE 3: profile.create_via_menu_dialog ──────────────────────────
    driver.phase('3', 'profile: create via manage-sheet dialog (UX-PMD-1)');
    await registry.runFor('profile.create_via_menu_dialog')!(tester, driver);
    if (shouldStopAfter('profile.create_via_menu_dialog')) return;
    driver.phase('3', 'OK — profile.create_via_menu_dialog');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(3),
        reason: 'mock-keyring-identity must cover at least 3 flows.');

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING_IDENTITY: PASS — ${cov.implemented} flows '
        'covered.');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
