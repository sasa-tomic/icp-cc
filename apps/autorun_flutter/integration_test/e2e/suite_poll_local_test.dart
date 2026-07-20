// ignore_for_file: lines_longer_than_80_chars

/// Dedicated e2e suite for the local-replica Poll dapp flows.
///
/// These two flows (`dapps.run_poll` + `dapps.create_profile_to_vote`)
/// were originally targeted for `suite_keyring_less_test.dart` as PHASE
/// 56 + 57. However, that suite's single `testWidgets` body already runs
/// 55 phases (2478 lines) and adding the poll flow bodies inline (even
/// extracted to `poll_flows.dart` and imported) deterministically
/// destabilises the flutter_test binding's stream protocol — the Linux
/// desktop app process crashes mid-suite with a flaky
/// `"Cannot close sink while adding stream"` error in
/// `FlutterPlatform._startTest`. The crash threshold is a function of
/// TOTAL compiled code size (app + test file + imported helpers), not
/// line count alone: even an unused `import 'poll_flows.dart';` in the
/// suite file triggers it.
///
/// Rather than fight the pre-existing flakiness, this dedicated suite
/// boots the app FRESH and runs ONLY the 2 poll phases. The coverage
/// contract still counts them: `FlowCatalog.coverageReport` aggregates
/// across all suite files' registries when computing desktop coverage
/// (see `just e2e-desktop` → coverage union).
///
/// Run: `just e2e-local-replica` (starts the replica + runs this suite).
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';
import 'poll_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  final registry = FlowRegistry()
    ..register('dapps.run_poll', dappsRunPoll)
    ..register('dapps.create_profile_to_vote', dappsCreateProfileToVote);

  testWidgets('e2e suite — poll local replica: dapps.run_poll + create_profile_to_vote',
      (tester) async {
    // PHASE 0: clean slate + boot. The local replica is an EXTERNAL
    // precondition (started by `scripts/start-local-replica.sh` BEFORE
    // the test process — see justfile `e2e-local-replica`). The flows
    // themselves verify the pre-state via `pollReplicaReady` and fail
    // LOUD with a clear pointer if it isn't satisfied.
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    // Dismiss the first-run wizard so the main shell (ModernNavigationBar)
    // is visible — _navigateToDapps taps the nav bar.
    await driver.dismissWizard(tester);
    driver.phase('0', 'booted + wizard dismissed');

    // PHASE 1: dapps.run_poll — real canister round-trip.
    driver.phase('1', 'dapps: run poll (local replica)');
    await registry.runFor('dapps.run_poll')!(tester, driver);
    driver.phase('1', 'OK — dapps.run_poll');

    // Reset between phases so the second flow starts from a clean
    // DappsScreen (the first flow closed the DappRunnerScreen; a remount
    // ensures no stale state leaks).
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.remount(tester);
    await driver.dismissWizard(tester);

    // PHASE 2: dapps.create_profile_to_vote — keyless CTA deep-link.
    driver.phase('2', 'dapps: create profile to vote CTA');
    await registry.runFor('dapps.create_profile_to_vote')!(tester, driver);
    driver.phase('2', 'OK — dapps.create_profile_to_vote');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented in THIS suite; '
        'flows: ${cov.covered.join(", ")}');
    expect(cov.implemented, equals(2),
        reason: 'This suite must cover both poll flows.');

    // ignore: avoid_print
    print('SUITE_POLL_LOCAL: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
