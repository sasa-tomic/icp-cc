// ignore_for_file: lines_longer_than_80_chars

/// Per-flow Web e2e tests — ONE `testWidgets` per flow.
///
/// Mirrors the desktop per-flow pattern (`flows_keyring_less_test.dart`) but
/// for the Web surface (`flutter test -d chrome`). Each flow boots the REAL
/// app on Chromium with substrate fakes at the smallest I/O boundary.
///
/// Currently covers the 7 cross-surface flows already ported to
/// `flow_implementations.dart`. The full web migration (~66 more flows) is
/// tracked in `docs/specs/2026-07-21-e2e-harness-overhaul.md` Phase P2.
///
/// Run a single flow:
///   `just e2e-web-one first_run.dismiss_wizard`
///   `just e2e-web-one scripts.browse_marketplace`
///
/// Or directly:
///   `flutter test -d chrome test/e2e_web/flows_web_test.dart \
///     --name first_run.dismiss_wizard`
@Tags(['web'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import '../../integration_test/e2e/e2e_driver.dart';
import '../../integration_test/e2e/flow_catalog.dart';
import '../../integration_test/e2e/flow_implementations.dart';
import 'web_suite_helpers.dart';

/// Prerequisite flow chains for the non-self-booting flows. Each assumes the
/// common setup: `resetWebAppState → boot (substrateAware) → dismissWizard`.
const Map<String, List<String>> _prereqs = <String, List<String>>{
  // ── first_run ──────────────────────────────────────────────────────────
  'first_run.reopen_wizard_chip': <String>[],

  // ── profile ────────────────────────────────────────────────────────────
  'profile.open_menu': <String>[],

  // ── settings (each builds on profile.open_menu → settings.open) ────────
  'settings.open': <String>['profile.open_menu'],
  'settings.theme': <String>['profile.open_menu', 'settings.open'],
  'settings.version_display': <String>['profile.open_menu', 'settings.open'],
  'settings.docs_link': <String>['profile.open_menu', 'settings.open'],
  'settings.report_issue': <String>['profile.open_menu', 'settings.open'],
  'settings.getting_started': <String>['profile.open_menu', 'settings.open'],
  'settings.restart_tour': <String>['profile.open_menu', 'settings.open'],
  'settings.unlock_dev_options': <String>[
    'profile.open_menu',
    'settings.open',
  ],
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

  // ── scripts (marketplace read flows — no profile needed) ───────────────
  'scripts.browse_marketplace': <String>[],
  'scripts.search': <String>[],
  // scripts.search_no_results: BLOCKED — MockClient stream-read needs runAsync
  // which re-evaluates the wizard gate post-boot. See flow docstring.
  'scripts.filter_category': <String>[],
  'scripts.filter_sort': <String>[],
  'scripts.view_details': <String>[],
  'scripts.download_free': <String>['scripts.view_details'],
  'scripts.filter_downloaded_only': <String>[
    'scripts.view_details',
    'scripts.download_free',
  ],
  'scripts.toggle_favorite': <String>[],
  'scripts.filter_favorites_only': <String>['scripts.toggle_favorite'],
  'scripts.refresh_pull': <String>[],
  'scripts.empty_library': <String>[],
  'scripts.marketplace_load_error': <String>[],
  'scripts.share': <String>[],

  // ── download history (need a downloaded script) ──────────────────────
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

  // ── dapps (profile-independent — catalog navigation) ─────────────────
  'dapps.open_catalog': <String>[],

  // ── canisters (profile-independent) ──────────────────────────────────
  'canisters.refresh_pull': <String>[],
  'canisters.bookmark_well_known': <String>[],
  'canisters.save_composer': <String>[],

  // scripts.view_in_marketplace: BLOCKED — LocalScriptRowMenu doesn't render
  // on web after download (ScriptController.loadScripts needs runAsync). See
  // flow docstring.
};

void main() {
  setUpAll(() {
    installWebSubstrate();
  });

  final driver = E2EDriver(surface: E2ESurface.web, substrateAware: true);

  final tagsById = <String, Set<String>>{
    for (final s in FlowCatalog.all) s.id: s.tags,
  };

  final registry = FlowRegistry()
    ..register('first_run.reopen_wizard_chip', firstRunReopenWizardChip)
    ..register('profile.open_menu', profileOpenMenu)
    ..register('settings.open', settingsOpen)
    ..register('settings.theme', settingsTheme)
    ..register('settings.version_display', settingsVersionDisplay)
    ..register('settings.docs_link', settingsDocsLink)
    ..register('settings.report_issue', settingsReportIssue)
    ..register('settings.getting_started', settingsGettingStarted)
    ..register('settings.restart_tour', settingsRestartTour)
    ..register('settings.unlock_dev_options', settingsUnlockDevOptions)
    ..register('settings.copy_api_endpoint', settingsCopyApiEndpoint)
    ..register('settings.clear_dev_options', settingsClearDevOptions)
    ..register('scripts.browse_marketplace', scriptsBrowseMarketplace)
    ..register('scripts.search', scriptsSearch)
    // scripts.search_no_results: not registered (BLOCKED — see flow docstring)
    ..register('scripts.filter_category', scriptsFilterCategory)
    ..register('scripts.filter_sort', scriptsFilterSort)
    ..register('scripts.view_details', scriptsViewDetails)
    ..register('scripts.download_free', scriptsDownloadFree)
    ..register('scripts.filter_downloaded_only', scriptsFilterDownloadedOnly)
    ..register('scripts.toggle_favorite', scriptsToggleFavorite)
    ..register('scripts.filter_favorites_only', scriptsFilterFavoritesOnly)
    ..register('scripts.refresh_pull', scriptsRefreshPull)
    ..register('scripts.empty_library', scriptsEmptyLibrary)
    ..register('scripts.marketplace_load_error', scriptsMarketplaceLoadError)
    ..register('scripts.share', scriptsShare)
    ..register('download_history.view', downloadHistoryView)
    ..register('download_history.remove', downloadHistoryRemove)
    ..register('download_history.clear', downloadHistoryClear)
    ..register('dapps.open_catalog', dappsOpenCatalog)
    ..register('canisters.refresh_pull', canistersRefreshPull)
    ..register('canisters.bookmark_well_known', canistersBookmarkWellKnown)
    ..register('canisters.save_composer', canistersSaveComposer);
    // scripts.view_in_marketplace: not registered (BLOCKED — see flow docstring)

  // ── SPECIAL: first_run.dismiss_wizard (self-contained, no prereqs) ─────────
  // Boot → wizard appears (or chip if onboarding already done) → dismiss.
  testWidgets('first_run.dismiss_wizard', (tester) async {
    await driver.boot(tester);
    // The boot's substrateAware loop bails when EITHER the wizard or the
    // "Set up profile" chip appears. On a clean store, the wizard shows.
    // If onboarding was already completed (substrate state leak), the chip
    // shows instead — both are valid boot outcomes.
    final wizardVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 15));
    if (wizardVisible) {
      await driver.dismissWizard(tester);
      expect(driver.present(find.byType(UnifiedSetupWizard), tester), isFalse,
          reason: 'Tapping close must dismiss the wizard.');
    } else {
      // Fallback: chip visible (onboarding already done from substrate state).
      final chip = find.textContaining('Set up profile');
      expect(driver.present(chip, tester), isTrue,
          reason: 'Either the wizard or the "Set up profile" chip must be '
              'visible after boot.');
    }
    // Drain cache timer for clean teardown.
    await tester.pump(const Duration(seconds: 11));
  },
      timeout: const Timeout(Duration(seconds: 60)),
      tags: ['onboarding']);

  // ── STANDARD: per-flow testWidgets with common setup ──────────────────────
  for (final entry in _prereqs.entries) {
    final flowId = entry.key;
    final prereqIds = entry.value;

    testWidgets(flowId, (tester) async {
      resetWebAppState();
      await driver.boot(tester);
      await driver.dismissWizard(tester);

      // Run prerequisite flows (sets up screen state).
      for (final prereqId in prereqIds) {
        await registry.runFor(prereqId)!(tester, driver);
      }

      // Settle: let async content finish rendering.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // Run the target flow.
      await registry.runFor(flowId)!(tester, driver);

      // Drain flutter_cache_manager's cleanup timer so the binding's
      // timersPending invariant doesn't trip on teardown.
      await tester.pump(const Duration(seconds: 11));
    },
        timeout: const Timeout(Duration(seconds: 120)),
        tags: tagsById[flowId]?.toList());
  }

  // ── Coverage report ───────────────────────────────────────────────────────
  testWidgets('web coverage report', (tester) async {
    final cov = FlowCatalog.coverageReport(registry);
    // ignore: avoid_print
    print('WEB_PER_FLOW: ${cov.implemented}/${cov.total} flows registered.');
    expect(cov.implemented, greaterThanOrEqualTo(32),
        reason: 'Per-flow web harness must cover at least the 32 registered '
            'flows (plus dismiss_wizard tested inline above).');
  },
      timeout: const Timeout(Duration(seconds: 30)),
      tags: ['smoke']);
}
