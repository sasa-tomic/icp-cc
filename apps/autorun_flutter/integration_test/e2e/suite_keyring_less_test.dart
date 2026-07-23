// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 1 (keyring-less / StorageUnavailable).
///
/// Boots the REAL app ONCE, then runs phases with `resetAppState` + remount
/// between isolation groups. This is the fast shared-boot harness: one
/// build/load for the whole keyring-less surface instead of one per file.
///
/// Run: `just e2e-desktop` (PASS 1 — no Secret Service required).
///
/// Covered flows (registered in [FlowRegistry]):
///   first_run.dismiss_wizard, first_run.keyring_unavailable,
///   first_run.reopen_wizard_chip,
///   profile.open_menu, settings.open, settings.unlock_dev_options,
///   settings.version_display, settings.theme, settings.docs_link,
///   settings.report_issue, settings.getting_started,
///   settings.copy_api_endpoint, settings.clear_dev_options,
///   settings.restart_tour,
///   shortcut.tab_switch, shortcut.show_help, shortcut.escape_back,
///   shortcut.new_script, shortcut.focus_search, shortcut.refresh,
///   shortcut.details_prev_next_tab,
///   scripts.browse_marketplace, scripts.search, scripts.search_no_results,
///   scripts.filter_category, scripts.view_details, scripts.download_free,
///   scripts.filter_downloaded_only, scripts.toggle_favorite,
///   scripts.filter_favorites_only, scripts.filter_sort, scripts.share,
///   scripts.view_in_marketplace, scripts.refresh_pull, scripts.run,
///   scripts.empty_library, scripts.marketplace_load_error,
///   download_history.view, download_history.remove, download_history.clear,
///   canisters.bookmark_well_known, canisters.save_composer,
///   canisters.recent_calls, canisters.tap_bookmark, canisters.refresh_pull,
///   canisters.open_inline_client,
///   dapps.open_catalog, dapps.local_replica_unreachable,
///   dapps.apply_connection, dapps.refresh, dapps.open_frontend,
///   shortcut.dapp_refresh,
///   scripts.delete (Phase 51 — unblocked on Flutter 3.44.6),
///   scripts.load_more (Phase 52 — requires `dart run tool/seed_marketplace.dart
///   --count=25` to seed the backend past the page-size threshold of 20),
///   dapps.run_ledger_mainnet (Phase 53 — real IC mainnet canister call;
///   best-effort, network-dependent),
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/spotlight_overlay.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';
import 'keyring_less_flows.dart';


void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);
  final registry = buildKeyringLessRegistry();

  testWidgets('e2e suite — keyring-less: shared boot + flows', (tester) async {
    // ── GROUP A: harness mechanism (boot + isolation) ──────────────────────
    // PHASE 0pre: purge any stale bulk_seed scripts left by a prior crashed
    // run of scripts.load_more. Earlier phases (PHASE 15's tapAt(720,450),
    // PHASE 30's browse assertions) assume a sparse 3-script marketplace;
    // leaked seeds would change the layout and break those phases. This
    // purge is idempotent (no-op when no seeds exist) and bounded.
    driver.phase('0pre', 'purge stale bulk_seed scripts');
    final purged = await runSeeder(tester, <String>['--purge']);
    expect(purged, isTrue,
        reason: 'bulk_seed purge must succeed (or be a no-op). '
            'Check [seed!] log lines for backend connectivity issues.');

    // PHASE 0: clean slate + first boot → wizard present.
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'On a wiped store with no Secret Service the first-run gate '
            'must show the setup wizard.');
    await driver.screenshot(tester, 'kl_00_first_run_wizard');
    driver.phase('0', 'OK');

    // PHASE 1: resetAppState + remount → wizard re-fires (isolation proof).
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.remount(tester);
    driver.phase('1', 'remount — asserting first-run gate re-fired');
    final wizardOnRemount = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnRemount, isTrue,
        reason: 'resetAppState + remount must reproduce a first-run boot.');
    driver.phase('1', 'OK');

    // PHASE 1b: first_run.keyring_unavailable — assert the WU-S2 actionable
    // blocking panel renders when the Secret Service is unreachable. On a
    // keyring-less box this exercises the full panel; on a box with a working
    // keyring the flow no-ops (use `just e2e-keyring-unavailable` for the
    // controlled assertion there).
    driver.phase('1b', 'first_run.keyring_unavailable (readiness panel)');
    await registry.runFor('first_run.keyring_unavailable')!(tester, driver);
    if (shouldStopAfter('first_run.keyring_unavailable')) return;
    driver.phase('1b', 'OK — first_run.keyring_unavailable');

    // ── GROUP B: user flows on a single session ────────────────────────────
    // PHASE 2: dismiss wizard → ScriptsScreen visible.
    driver.phase('2', 'dismiss wizard → ScriptsScreen');
    await driver.dismissWizard(tester);
    final scriptsVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 10));
    expect(scriptsVisible, isTrue,
        reason: 'After dismissing the wizard the Scripts tab must render.');
    driver.phase('2', 'OK — first_run.dismiss_wizard');

    // PHASE 3: reopen wizard via persistent chip.
    driver.phase('3', 'tap ProfileSetupChip → wizard re-opens');
    await registry.runFor('first_run.reopen_wizard_chip')!(tester, driver);
    if (shouldStopAfter('first_run.reopen_wizard_chip')) return;
    driver.phase('3', 'OK — first_run.reopen_wizard_chip');

    // PHASE 4: dismiss again → ScriptsScreen → open profile menu.
    driver.phase('4', 'dismiss + open profile menu');
    await driver.dismissWizard(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 5));
    await registry.runFor('profile.open_menu')!(tester, driver);
    if (shouldStopAfter('profile.open_menu')) return;
    driver.phase('4', 'OK — profile.open_menu');

    // PHASE 5: tap Settings tile → SettingsScreen.
    driver.phase('5', 'navigate to Settings');
    await registry.runFor('settings.open')!(tester, driver);
    if (shouldStopAfter('settings.open')) return;
    driver.phase('5', 'OK — settings.open');

    // PHASE 6: unlock dev options (7 taps on version).
    driver.phase('6', 'unlock dev options');
    await registry.runFor('settings.unlock_dev_options')!(tester, driver);
    if (shouldStopAfter('settings.unlock_dev_options')) return;
    driver.phase('6', 'OK — settings.unlock_dev_options');

    // ── G8: Settings flows (SettingsScreen still open) ─────────────────────
    // PHASE 7: version display.
    driver.phase('7', 'settings: version display');
    await registry.runFor('settings.version_display')!(tester, driver);
    if (shouldStopAfter('settings.version_display')) return;
    driver.phase('7', 'OK — settings.version_display');

    // PHASE 8: theme toggle.
    driver.phase('8', 'settings: theme');
    await registry.runFor('settings.theme')!(tester, driver);
    if (shouldStopAfter('settings.theme')) return;
    driver.phase('8', 'OK — settings.theme');

    // PHASE 9: docs link + report issue (assert presence).
    driver.phase('9', 'settings: docs + report');
    await registry.runFor('settings.docs_link')!(tester, driver);
    if (shouldStopAfter('settings.docs_link')) return;
    await registry.runFor('settings.report_issue')!(tester, driver);
    if (shouldStopAfter('settings.report_issue')) return;
    driver.phase('9', 'OK — settings.docs_link + settings.report_issue');

    // PHASE 10: getting started.
    driver.phase('10', 'settings: getting started');
    await registry.runFor('settings.getting_started')!(tester, driver);
    if (shouldStopAfter('settings.getting_started')) return;
    driver.phase('10', 'OK — settings.getting_started');

    // PHASE 11: copy API endpoint (dev options still unlocked from phase 6).
    driver.phase('11', 'settings: copy API endpoint');
    await registry.runFor('settings.copy_api_endpoint')!(tester, driver);
    if (shouldStopAfter('settings.copy_api_endpoint')) return;
    driver.phase('11', 'OK — settings.copy_api_endpoint');

    // PHASE 12: clear dev options (must be AFTER copy_api_endpoint).
    driver.phase('12', 'settings: clear dev options');
    await registry.runFor('settings.clear_dev_options')!(tester, driver);
    if (shouldStopAfter('settings.clear_dev_options')) return;
    driver.phase('12', 'OK — settings.clear_dev_options');

    // ── G9: Keyboard shortcuts (need ScriptsScreen, not Settings) ──────────
    // PHASE 13: close Settings → ScriptsScreen → tab switching.
    driver.phase('13', 'close settings → shortcuts');
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 5));
    await registry.runFor('shortcut.tab_switch')!(tester, driver);
    if (shouldStopAfter('shortcut.tab_switch')) return;
    driver.phase('13', 'OK — shortcut.tab_switch');

    // PHASE 14: shortcuts help (?) + escape back (Esc).
    driver.phase('14', 'shortcuts help + escape');
    await registry.runFor('shortcut.show_help')!(tester, driver);
    if (shouldStopAfter('shortcut.show_help')) return;
    await registry.runFor('shortcut.escape_back')!(tester, driver);
    if (shouldStopAfter('shortcut.escape_back')) return;
    driver.phase('14', 'OK — shortcut.show_help + shortcut.escape_back');

    // PHASE 15: new script shortcut (N).
    driver.phase('15', 'shortcut: N → new script');
    await registry.runFor('shortcut.new_script')!(tester, driver);
    if (shouldStopAfter('shortcut.new_script')) return;
    driver.phase('15', 'OK — shortcut.new_script');

    // PHASE 16: focus search shortcut (/).
    driver.phase('16', 'shortcut: / → focus search');
    await registry.runFor('shortcut.focus_search')!(tester, driver);
    if (shouldStopAfter('shortcut.focus_search')) return;
    driver.phase('16', 'OK — shortcut.focus_search');

    // PHASE 17: refresh shortcut (R).
    driver.phase('17', 'shortcut: R → refresh');
    await registry.runFor('shortcut.refresh')!(tester, driver);
    if (shouldStopAfter('shortcut.refresh')) return;
    driver.phase('17', 'OK — shortcut.refresh');

    // PHASE 18: details dialog tab switching (←/→).
    driver.phase('18', 'shortcut: ←/→ details tabs');
    await registry.runFor('shortcut.details_prev_next_tab')!(tester, driver);
    if (shouldStopAfter('shortcut.details_prev_next_tab')) return;
    driver.phase('18', 'OK — shortcut.details_prev_next_tab');

    // PHASE 19: restart tour (open settings, tap, remount, verify).
    driver.phase('19', 'settings: restart tour');
    // PHASE 18 closed a ScriptDetailsDialog via Esc; under Flutter 3.44.6 the
    // Overlay theater retains a residual RenderAbsorbPointer that shadows the
    // ProfileAvatarButton tap (hit-test lands on the theater, not the button).
    // Invoke ProfileAvatarButton.onTap directly — same callback-direct
    // workaround pattern used in PHASES 14/15/18 (E2E-PHASE-O-REGRESSION).
    final avatarBtn = tester.widget<ProfileAvatarButton>(
        find.byType(ProfileAvatarButton).first);
    avatarBtn.onTap();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Settings'));
    await driver.waitUntil(
        tester, () => driver.present(find.byType(SettingsScreen), tester),
        timeout: const Duration(seconds: 5));
    await registry.runFor('settings.restart_tour')!(tester, driver);
    if (shouldStopAfter('settings.restart_tour')) return;

    // The spotlight tour only fires in initState after a remount.
    // DO NOT resetAppState here — the spotlight pref must persist.
    await driver.remount(tester);
    final tourShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(SpotlightOverlay), tester),
        timeout: const Duration(seconds: 10));
    expect(tourShown, isTrue,
        reason: 'After remount with spotlight pref set, the tour must appear.');
    // Dismiss the tour.
    await driver.tapIfPresent(tester, find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 500));
    driver.phase('19', 'OK — settings.restart_tour (tour verified)');

    // PHASE 20: canisters — bookmark a well-known canister.
    driver.phase('20', 'canisters: bookmark well-known');
    await registry.runFor('canisters.bookmark_well_known')!(tester, driver);
    if (shouldStopAfter('canisters.bookmark_well_known')) return;
    driver.phase('20', 'OK — canisters.bookmark_well_known');

    // PHASE 21: canisters — save via composer.
    driver.phase('21', 'canisters: save composer');
    await registry.runFor('canisters.save_composer')!(tester, driver);
    if (shouldStopAfter('canisters.save_composer')) return;
    driver.phase('21', 'OK — canisters.save_composer');

    // PHASE 22: dapps — open catalog.
    driver.phase('22', 'dapps: open catalog');
    await registry.runFor('dapps.open_catalog')!(tester, driver);
    if (shouldStopAfter('dapps.open_catalog')) return;
    driver.phase('22', 'OK — dapps.open_catalog');

    // PHASE 23: canisters — recent calls section.
    driver.phase('23', 'canisters: recent calls');
    await registry.runFor('canisters.recent_calls')!(tester, driver);
    if (shouldStopAfter('canisters.recent_calls')) return;
    driver.phase('23', 'OK — canisters.recent_calls');

    // PHASE 24: canisters — tap bookmark (verify saved bookmark persists).
    driver.phase('24', 'canisters: tap bookmark');
    await registry.runFor('canisters.tap_bookmark')!(tester, driver);
    if (shouldStopAfter('canisters.tap_bookmark')) return;
    driver.phase('24', 'OK — canisters.tap_bookmark');

    // PHASE 25: canisters.refresh_pull — pull-to-refresh the bookmarks list.
    driver.phase('25', 'canisters: pull-to-refresh');
    await registry.runFor('canisters.refresh_pull')!(tester, driver);
    if (shouldStopAfter('canisters.refresh_pull')) return;
    driver.phase('25', 'OK — canisters.refresh_pull');

    // PHASE 26: scripts.marketplace_load_error — assert the marketplace
    // load-error panel renders when the backend is unreachable. We can't
    // take the backend down here; instead, this flow asserts the
    // error-state widget tree compiles + mounts (the conditional render
    // path is exercised). See flow body for details.
    driver.phase('26', 'scripts: marketplace load-error panel shape');
    await registry.runFor('scripts.marketplace_load_error')!(tester, driver);
    if (shouldStopAfter('scripts.marketplace_load_error')) return;
    driver.phase('26', 'OK — scripts.marketplace_load_error');

    // PHASE 27: scripts.empty_library — assert the empty-library state.
    driver.phase('27', 'scripts: empty library state');
    await registry.runFor('scripts.empty_library')!(tester, driver);
    if (shouldStopAfter('scripts.empty_library')) return;
    driver.phase('27', 'OK — scripts.empty_library');

    // PHASE 28: scripts.refresh_pull — pull-to-refresh the marketplace list.
    driver.phase('28', 'scripts: pull-to-refresh');
    await registry.runFor('scripts.refresh_pull')!(tester, driver);
    if (shouldStopAfter('scripts.refresh_pull')) return;
    driver.phase('28', 'OK — scripts.refresh_pull');

    // ── GROUP C: marketplace + download-history flows (folded from the
    //    retired suite_marketplace_test.dart — same backend, same keyring-less
    //    surface, now reached without a second app boot). By phase 28 the
    //    marketplace is loaded and no downloads/favorites exist yet, so the
    //    group starts from the same pre-state the marketplace suite had.)

    // PHASE 29: browse — verify all 3 scripts.
    driver.phase('29', 'browse marketplace');
    await registry.runFor('scripts.browse_marketplace')!(tester, driver);
    if (shouldStopAfter('scripts.browse_marketplace')) return;
    driver.phase('29', 'OK — scripts.browse_marketplace');

    // PHASE 30: search "counter" → 2 results.
    driver.phase('30', 'search "counter"');
    await registry.runFor('scripts.search')!(tester, driver);
    if (shouldStopAfter('scripts.search')) return;
    driver.phase('30', 'OK — scripts.search');

    // PHASE 31: search no results.
    driver.phase('31', 'search no results');
    await registry.runFor('scripts.search_no_results')!(tester, driver);
    if (shouldStopAfter('scripts.search_no_results')) return;
    driver.phase('31', 'OK — scripts.search_no_results');

    // PHASE 32: filter by category.
    driver.phase('32', 'filter category');
    await registry.runFor('scripts.filter_category')!(tester, driver);
    if (shouldStopAfter('scripts.filter_category')) return;
    driver.phase('32', 'OK — scripts.filter_category');

    // PHASE 33: view details.
    driver.phase('33', 'view details');
    await registry.runFor('scripts.view_details')!(tester, driver);
    if (shouldStopAfter('scripts.view_details')) return;
    driver.phase('33', 'OK — scripts.view_details');

    // PHASE 34: download free.
    driver.phase('34', 'download free');
    await registry.runFor('scripts.download_free')!(tester, driver);
    if (shouldStopAfter('scripts.download_free')) return;
    driver.phase('34', 'OK — scripts.download_free');

    // PHASE 35: filter downloaded only.
    driver.phase('35', 'filter downloaded only');
    await registry.runFor('scripts.filter_downloaded_only')!(tester, driver);
    if (shouldStopAfter('scripts.filter_downloaded_only')) return;
    driver.phase('35', 'OK — scripts.filter_downloaded_only');

    // PHASE 36: toggle favorite.
    driver.phase('36', 'toggle favorite');
    await registry.runFor('scripts.toggle_favorite')!(tester, driver);
    if (shouldStopAfter('scripts.toggle_favorite')) return;
    driver.phase('36', 'OK — scripts.toggle_favorite');

    // PHASE 37: filter favorites only.
    driver.phase('37', 'filter favorites only');
    await registry.runFor('scripts.filter_favorites_only')!(tester, driver);
    if (shouldStopAfter('scripts.filter_favorites_only')) return;
    driver.phase('37', 'OK — scripts.filter_favorites_only');

    // PHASE 38: filter sort.
    driver.phase('38', 'filter sort');
    await registry.runFor('scripts.filter_sort')!(tester, driver);
    if (shouldStopAfter('scripts.filter_sort')) return;
    driver.phase('38', 'OK — scripts.filter_sort');

    // PHASE 39: download history view.
    driver.phase('39', 'download history view');
    await registry.runFor('download_history.view')!(tester, driver);
    if (shouldStopAfter('download_history.view')) return;
    driver.phase('39', 'OK — download_history.view');

    // PHASE 40: download history remove.
    driver.phase('40', 'download history remove');
    await registry.runFor('download_history.remove')!(tester, driver);
    if (shouldStopAfter('download_history.remove')) return;
    driver.phase('40', 'OK — download_history.remove');

    // PHASE 41: download history clear.
    driver.phase('41', 'download history clear');
    await registry.runFor('download_history.clear')!(tester, driver);
    if (shouldStopAfter('download_history.clear')) return;
    driver.phase('41', 'OK — download_history.clear');

    // ── GROUP D: Phase D — script + canister + dapp-runner flows. Appended
    //    after the marketplace group; each phase navigates to the surface it
    //    needs (ScriptsScreen is still on stage from phase 41; the canister
    //    and dapp flows re-navigate via Alt+2 / Alt+3).

    // PHASE 42: scripts.share — invoke onShare on a marketplace row.
    driver.phase('42', 'scripts: share via marketplace row menu');
    await registry.runFor('scripts.share')!(tester, driver);
    if (shouldStopAfter('scripts.share')) return;
    driver.phase('42', 'OK — scripts.share');

    // PHASE 43: scripts.view_in_marketplace — invoke onViewInMarketplace on
    // the downloaded Hello IC Starter row.
    driver.phase('43', 'scripts: view in marketplace');
    await registry.runFor('scripts.view_in_marketplace')!(tester, driver);
    if (shouldStopAfter('scripts.view_in_marketplace')) return;
    driver.phase('43', 'OK — scripts.view_in_marketplace');

    // PHASE 44: scripts.run — open ScriptExecutionBottomSheet on Hello IC Starter.
    driver.phase('44', 'scripts: run via QuickJS');
    await registry.runFor('scripts.run')!(tester, driver);
    if (shouldStopAfter('scripts.run')) return;
    driver.phase('44', 'OK — scripts.run');

    // PHASE 45–50: previously DEFERRED. Re-attempted on Flutter 3.44.6
    // (upgraded from 3.38.3) to see whether the Overlay `RenderAbsorbPointer`
    // bug cleared. See docs/specs/phase-d-triage.md for the resume log.

    // PHASE 45: dapps.local_replica_unreachable — Polls → local-replica banner.
    driver.phase('45', 'dapps: local replica unreachable banner');
    await registry.runFor('dapps.local_replica_unreachable')!(tester, driver);
    if (shouldStopAfter('dapps.local_replica_unreachable')) return;
    driver.phase('45', 'OK — dapps.local_replica_unreachable');

    // PHASE 46: dapps.apply_connection — Polls → Connection → Apply → SnackBar.
    // Unblocked by E2E-D-RESUME-1 fix (ScriptAppHost._dispatch mounted guard).
    driver.phase('46', 'dapps: apply connection');
    await registry.runFor('dapps.apply_connection')!(tester, driver);
    if (shouldStopAfter('dapps.apply_connection')) return;
    driver.phase('46', 'OK — dapps.apply_connection');

    // PHASE 47: dapps.refresh — Polls → AppBar refresh icon → SnackBar.
    // Unblocked by E2E-D-RESUME-1 fix.
    driver.phase('47', 'dapps: refresh icon');
    await registry.runFor('dapps.refresh')!(tester, driver);
    if (shouldStopAfter('dapps.refresh')) return;
    driver.phase('47', 'OK — dapps.refresh');

    // PHASE 48: dapps.open_frontend — Polls → AppBar open-in-new icon.
    driver.phase('48', 'dapps: open frontend icon');
    await registry.runFor('dapps.open_frontend')!(tester, driver);
    if (shouldStopAfter('dapps.open_frontend')) return;
    driver.phase('48', 'OK — dapps.open_frontend');

    // PHASE 48b: shortcut.dapp_refresh — Polls → press R → SnackBar.
    // Unblocked by E2E-D-RESUME-1 fix.
    driver.phase('48b', 'shortcut: dapp_refresh (R key)');
    await registry.runFor('shortcut.dapp_refresh')!(tester, driver);
    if (shouldStopAfter('shortcut.dapp_refresh')) return;
    driver.phase('48b', 'OK — shortcut.dapp_refresh');

    // PHASE 49: canisters.open_inline_client — Popular Canister card → sheet.
    driver.phase('49', 'canisters: open inline client');
    await registry.runFor('canisters.open_inline_client')!(tester, driver);
    if (shouldStopAfter('canisters.open_inline_client')) return;
    driver.phase('49', 'OK — canisters.open_inline_client');

    // PHASE 50: download_history.run — record tap → ScriptExecutionBottomSheet.
    driver.phase('50', 'download_history: run via record tap');
    await registry.runFor('download_history.run')!(tester, driver);
    if (shouldStopAfter('download_history.run')) return;
    driver.phase('50', 'OK — download_history.run');

    // PHASE 51: scripts.delete — onConfirmDelete on Hello IC Starter →
    // AlertDialog → tap Delete → SnackBar + script row gone.
    driver.phase('51', 'scripts: delete via confirm dialog');
    await registry.runFor('scripts.delete')!(tester, driver);
    if (shouldStopAfter('scripts.delete')) return;
    driver.phase('51', 'OK — scripts.delete');

    // PHASE 52: scripts.load_more — pagination contract. The marketplace is
    // seeded with 25 bulk-seed scripts (via tool/seed_marketplace.dart) +
    // the 3 hand-seeded originals = 28 total, exceeding the page size of 20.
    // Asserts the first page loaded with bulk-seed tiles visible and the
    // marketplace didn't fall into the empty/error state.
    driver.phase('52', 'scripts: load_more (pagination contract)');
    await registry.runFor('scripts.load_more')!(tester, driver);
    if (shouldStopAfter('scripts.load_more')) return;
    driver.phase('52', 'OK — scripts.load_more');

    // PHASE 53: dapps.run_ledger_mainnet — ICP Ledger card → DappRunnerScreen
    // → ScriptAppHost → real mainnet canister call. Best-effort: success
    // (token metadata rendered) and network-error (error UI rendered) are
    // both valid PASS outcomes; only a crash fails.
    driver.phase('53', 'dapps: run ICP Ledger (mainnet)');
    await registry.runFor('dapps.run_ledger_mainnet')!(tester, driver);
    if (shouldStopAfter('dapps.run_ledger_mainnet')) return;
    driver.phase('53', 'OK — dapps.run_ledger_mainnet');


    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.total, greaterThan(90), reason: 'Catalog must list all flows.');
    expect(cov.implemented, greaterThanOrEqualTo(56),
        reason: 'keyring-less must cover at least 56 flows '
            '(42 base + 2 Phase-D easy + 1 Phase-D medium + 3 Phase D-resume '
            '+ 4 post-bug-fix: canisters.open_inline_client, '
            'dapps.apply_connection, dapps.refresh, shortcut.dapp_refresh, '
            '+ 1 Phase-51: scripts.delete, '
            '+ 1 Phase-1b: first_run.keyring_unavailable, '
            '+ 1 Phase-52: scripts.load_more, '
            '+ 1 Phase-53: dapps.run_ledger_mainnet).');

    // ignore: avoid_print
    print('SUITE_KEYRING_LESS: PASS — ${cov.implemented} flows covered '
        '(base + marketplace).');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
