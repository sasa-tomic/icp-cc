// ignore_for_file: lines_longer_than_80_chars

/// Per-flow keyring-less e2e tests — ONE `testWidgets` per flow.
///
/// Each flow gets its own app boot so `flutter test --plain-name <flow-id>`
/// runs exactly ONE flow in isolation (target: <20s including FFI load).
/// For full-surface coverage, use the shared-boot monolith
/// (`suite_keyring_less_test.dart` via `just e2e-desktop`) — it boots once
/// and chains all 58 flows in ~4min.
///
/// Run a single flow:
///   `just e2e-one scripts.search`
///   `just e2e-one settings.theme`
///
/// Or directly:
///   `flutter test -d linux integration_test/e2e/flows_keyring_less_test.dart \
///     --plain-name scripts.search`
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import 'e2e_driver.dart';
import 'suite_helpers.dart';
import 'keyring_less_flows.dart';

/// Prerequisite flow chains. Each key is a flow id; the value is the list of
/// flow ids that must run BEFORE it to set up the required app state (screen
/// navigation, downloaded scripts, bookmarks, etc.). All flows assume the
/// common setup: `resetAppState → boot → dismissWizard → ScriptsScreen`.
const Map<String, List<String>> _prereqs = <String, List<String>>{
  // ── first_run ──────────────────────────────────────────────────────────
  // dismiss_wizard and keyring_unavailable are handled specially (see below).
  'first_run.reopen_wizard_chip': <String>[],

  // ── profile ────────────────────────────────────────────────────────────
  'profile.open_menu': <String>[],

  // ── settings (each builds on profile.open_menu) ────────────────────────
  'settings.open': <String>['profile.open_menu'],
  'settings.unlock_dev_options': <String>['profile.open_menu', 'settings.open'],
  'settings.version_display': <String>['profile.open_menu', 'settings.open'],
  'settings.theme': <String>['profile.open_menu', 'settings.open'],
  'settings.docs_link': <String>['profile.open_menu', 'settings.open'],
  'settings.report_issue': <String>['profile.open_menu', 'settings.open'],
  'settings.getting_started': <String>['profile.open_menu', 'settings.open'],
  'settings.copy_api_endpoint': <String>[
    'profile.open_menu',
    'settings.open',
    'settings.unlock_dev_options',
  ],
  'settings.clear_dev_options': <String>[
    'profile.open_menu',
    'settings.open',
    'settings.unlock_dev_options',
  ],
  'settings.restart_tour': <String>['profile.open_menu', 'settings.open'],

  // ── shortcuts (need ScriptsScreen) ─────────────────────────────────────
  'shortcut.tab_switch': <String>[],
  'shortcut.show_help': <String>[],
  'shortcut.escape_back': <String>[],
  'shortcut.new_script': <String>[],
  'shortcut.focus_search': <String>[],
  'shortcut.refresh': <String>[],
  'shortcut.details_prev_next_tab': <String>[],
  'shortcut.dapp_refresh': <String>[],

  // ── canisters (navigate internally) ────────────────────────────────────
  'canisters.bookmark_well_known': <String>[],
  'canisters.save_composer': <String>[],
  'canisters.recent_calls': <String>[],
  'canisters.tap_bookmark': <String>['canisters.bookmark_well_known'],
  'canisters.refresh_pull': <String>[],
  'canisters.open_inline_client': <String>[],

  // ── dapps (navigate internally via _navigateToDapps) ───────────────────
  'dapps.open_catalog': <String>[],
  'dapps.local_replica_unreachable': <String>[],
  'dapps.apply_connection': <String>[],
  'dapps.refresh': <String>[],
  'dapps.open_frontend': <String>[],
  'dapps.run_ledger_mainnet': <String>[],

  // ── scripts (read flows — just need ScriptsScreen) ─────────────────────
  'scripts.marketplace_load_error': <String>[],
  'scripts.empty_library': <String>[],
  'scripts.refresh_pull': <String>[],
  'scripts.browse_marketplace': <String>[],
  'scripts.search': <String>[],
  'scripts.search_no_results': <String>[],
  'scripts.filter_category': <String>[],
  'scripts.view_details': <String>[],
  'scripts.filter_sort': <String>[],

  // ── scripts (download chain) ───────────────────────────────────────────
  // download_free expects the details dialog already open from view_details.
  'scripts.download_free': <String>['scripts.view_details'],
  'scripts.filter_downloaded_only': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],

  // ── scripts (favorites — work on marketplace tiles, no download needed) ─
  'scripts.toggle_favorite': <String>[],
  'scripts.filter_favorites_only': <String>['scripts.toggle_favorite'],

  // ── scripts (operate on LocalScriptRowMenu — need a download) ───────────
  'scripts.share': <String>[],
  'scripts.view_in_marketplace': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],
  'scripts.run': <String>['scripts.view_details', 'scripts.download_free'],
  'scripts.delete': <String>['scripts.view_details', 'scripts.download_free'],

  // ── download history (need a downloaded script in history) ──────────────
  'download_history.view': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],
  'download_history.remove': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],
  'download_history.clear': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],
  'download_history.run': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],

  // ── flows with internal resetAppState (manage their own boot) ──────────
  'scripts.load_more': <String>[],
  'scripts.buy': <String>[],
  'scripts.download_paid': <String>[],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final registry = buildKeyringLessRegistry();

  // ── SPECIAL: self-booting flows ──────────────────────────────────────────
  // first_run.dismiss_wizard: boot → wait for wizard → dismiss.
  // The flow closure in keyring_less_flows.dart is a thin wrapper that doesn't
  // wait for the wizard to mount (the monolith handles the wait in PHASE 0).
  // Here we do it inline with a proper bounded wait.
  testWidgets('first_run.dismiss_wizard', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    final wizardVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardVisible, isTrue,
        reason: 'A clean store must show the setup wizard on boot.');
    await driver.dismissWizard(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // first_run.keyring_unavailable needs the wizard VISIBLE (boot without
  // dismissWizard) to assert the readiness panel / setup form.
  testWidgets('first_run.keyring_unavailable', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    await registry.runFor('first_run.keyring_unavailable')!(tester, driver);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── STANDARD: per-flow testWidgets with common setup ─────────────────────
  for (final entry in _prereqs.entries) {
    final flowId = entry.key;
    final prereqIds = entry.value;

    testWidgets(flowId, (tester) async {
      final driver = E2EDriver(surface: E2ESurface.desktop);

      // Common setup: wipe → boot → dismiss wizard → ScriptsScreen.
      await resetAppState(tester: tester, wipeSecureStorage: false);
      await driver.boot(tester);
      await driver.dismissWizard(tester);
      final onScripts = await driver.waitUntil(
          tester, () => driver.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(onScripts, isTrue,
          reason: 'Setup for "$flowId": ScriptsScreen must render after '
              'dismissing the wizard.');

      // Run prerequisite flows (sets up screen state, downloads, bookmarks…).
      for (final prereqId in prereqIds) {
        await registry.runFor(prereqId)!(tester, driver);
      }

      // Settle: let async content (settings loads, marketplace fetches, etc.)
      // finish rendering. In the monolith, intermediate flows naturally pump
      // between settings.open and settings.theme; per-flow needs an explicit
      // bounded wait to replicate that settling time.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // Run the target flow.
      await registry.runFor(flowId)!(tester, driver);
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}
