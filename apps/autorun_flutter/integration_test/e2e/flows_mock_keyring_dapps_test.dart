// ignore_for_file: lines_longer_than_80_chars

/// Per-flow mock-keyring-dapps e2e tests — ONE `testWidgets` per flow.
///
/// Each flow gets its own app boot so
/// `flutter test --plain-name <flow-id>` runs exactly ONE flow in isolation.
/// For full-surface coverage, use the shared-boot monolith
/// (`suite_mock_keyring_dapps_test.dart` via `just e2e-desktop` PASS 2b).
///
/// Run a single flow:
///   `just e2e-one dapps.copy_principal mock-keyring-dapps`
///   `just e2e-one dapps.trust_grant mock-keyring-dapps`
///
/// Or directly:
///   `flutter test -d linux integration_test/e2e/flows_mock_keyring_dapps_test.dart \
///     --plain-name dapps.copy_principal`
///
/// **Must run under the mock Secret Service** (profiles need a keyring):
///   `scripts/run-with-mock-keyring.sh --display :99 -- flutter test ...`
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import 'e2e_driver.dart';
import 'mock_keyring_dapps_flows.dart';
import 'suite_helpers.dart';

/// Prerequisite flow chains. Each flow assumes a registered account (set up
/// via the wizard flow). The wizard flow itself is self-booting.
const Map<String, List<String>> _prereqs = <String, List<String>>{
  // dapps + shortcut flows all assume a registered account from the wizard.
  'dapps.copy_principal': <String>['first_run.create_profile_with_account'],
  'dapps.trust_grant': <String>['first_run.create_profile_with_account'],
  'dapps.manage_trust_revoke': <String>['first_run.create_profile_with_account'],
  'shortcut.account_save': <String>['first_run.create_profile_with_account'],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final registry = buildMockKeyringDappsRegistry();

  // ── SPECIAL: self-booting wizard flow ─────────────────────────────────
  // first_run.create_profile_with_account: boot → wait for wizard → run
  // flow (drives wizard UI to create profile + account). The flow closure
  // assumes the wizard is on stage.
  testWidgets('first_run.create_profile_with_account', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester);
    await driver.boot(tester);
    final wizardVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardVisible, isTrue,
        reason: 'A clean store must show the setup wizard on boot.');
    await registry.runFor('first_run.create_profile_with_account')!(
        tester, driver);
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── STANDARD: per-flow testWidgets with shared setup ──────────────────
  for (final entry in _prereqs.entries) {
    final flowId = entry.key;
    final prereqIds = entry.value;

    testWidgets(flowId, (tester) async {
      final driver = E2EDriver(surface: E2ESurface.desktop);

      // Common setup: wipe → boot → wizard on stage.
      await resetAppState(tester: tester);
      await driver.boot(tester);
      await driver.waitUntil(
          tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 20));

      // Run prerequisite flows (creates profile + registered account via
      // the wizard UI).
      for (final prereqId in prereqIds) {
        await registry.runFor(prereqId)!(tester, driver);
      }

      // Settle: let the post-wizard state stabilize.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      final onScripts = await driver.waitUntil(
          tester, () => driver.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(onScripts, isTrue,
          reason: 'Setup for "$flowId": ScriptsScreen must render after the '
              'wizard completes.');

      // Run the target flow.
      await registry.runFor(flowId)!(tester, driver);
    }, timeout: const Timeout(Duration(seconds: 180)));
  }
}
