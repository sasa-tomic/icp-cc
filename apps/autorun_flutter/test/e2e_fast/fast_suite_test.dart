// ignore_for_file: lines_longer_than_80_chars

/// Fast e2e suite — ALL cross-surface flows on the Dart VM in seconds.
///
/// This is the radical speed win over the ~9m integration-test suites. Every
/// flow from `flow_implementations.dart` (the shared library used by BOTH the
/// desktop integration tests and the Web e2e harness) runs here as a widget
/// test with substrate fakes + REAL FFI.
///
/// Run:
///   `just e2e-fast`           # all flows
///   `flutter test test/e2e_fast/fast_suite_test.dart --name scripts.search`
library;

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e/flow_catalog.dart';
import '../../integration_test/e2e/flow_implementations.dart';
import 'fast_harness.dart';

void main() {
  final harness = FastHarness();

  final registry = FlowRegistry()
    ..register('first_run.dismiss_wizard', firstRunDismissWizard)
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

  setUpAll(() async {
    await harness.setUp();
  });

  tearDownAll(() async {
    await harness.tearDown();
  });

  // ── Prerequisite chains ──────────────────────────────────────────────
  // Each non-self-booting flow lists its prerequisite flow ids. The suite
  // runs them in order before the target flow, sharing the same boot.
  const prereqs = <String, List<String>>{
    'first_run.reopen_wizard_chip': <String>[],
    'profile.open_menu': <String>[],
    'settings.open': <String>['profile.open_menu'],
    'settings.theme': <String>['profile.open_menu', 'settings.open'],
    'settings.version_display': <String>['profile.open_menu', 'settings.open'],
    'settings.docs_link': <String>['profile.open_menu', 'settings.open'],
    'settings.report_issue': <String>['profile.open_menu', 'settings.open'],
    'settings.getting_started': <String>['profile.open_menu', 'settings.open'],
    'settings.restart_tour': <String>['profile.open_menu', 'settings.open'],
    'settings.unlock_dev_options': <String>[
      'profile.open_menu', 'settings.open',
    ],
    'settings.copy_api_endpoint': <String>[
      'profile.open_menu', 'settings.open', 'settings.unlock_dev_options',
    ],
    'settings.clear_dev_options': <String>[
      'profile.open_menu', 'settings.open', 'settings.unlock_dev_options',
    ],
    'scripts.browse_marketplace': <String>[],
    'scripts.search': <String>[],
    'scripts.filter_category': <String>[],
    'scripts.filter_sort': <String>[],
    'scripts.view_details': <String>[],
    'scripts.download_free': <String>['scripts.view_details'],
    'scripts.filter_downloaded_only': <String>[
      'scripts.view_details', 'scripts.download_free',
    ],
    'scripts.toggle_favorite': <String>[],
    'scripts.filter_favorites_only': <String>['scripts.toggle_favorite'],
    'scripts.refresh_pull': <String>[],
    'scripts.empty_library': <String>[],
    'scripts.marketplace_load_error': <String>[],
    'scripts.share': <String>[],
    'download_history.view': <String>[
      'scripts.view_details', 'scripts.download_free',
    ],
    'download_history.remove': <String>[
      'scripts.view_details', 'scripts.download_free',
    ],
    'download_history.clear': <String>[
      'scripts.view_details', 'scripts.download_free',
    ],
    'dapps.open_catalog': <String>[],
    'canisters.refresh_pull': <String>[],
    'canisters.bookmark_well_known': <String>[],
    'canisters.save_composer': <String>[],
  };

  // ── Special: first_run.dismiss_wizard (self-contained) ───────────────
  testWidgets('first_run.dismiss_wizard', (tester) async {
    harness.resetState();
    await registry.runFor('first_run.dismiss_wizard')!(tester, harness.driver);
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Standard: per-flow testWidgets with common setup ─────────────────
  for (final entry in prereqs.entries) {
    final flowId = entry.key;
    final prereqIds = entry.value;

    testWidgets(flowId, (tester) async {
      harness.resetState();
      await harness.boot(tester);
      await harness.dismissWizard(tester);

      for (final prereqId in prereqIds) {
        await registry.runFor(prereqId)!(tester, harness.driver);
      }

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      await registry.runFor(flowId)!(tester, harness.driver);

      // Drain flutter_cache_manager cleanup timer.
      await tester.pump(const Duration(seconds: 11));
    }, timeout: const Timeout(Duration(seconds: 90)));
  }

  // ── Coverage report ──────────────────────────────────────────────────
  test('fast suite coverage report', () {
    final cov = FlowCatalog.coverageReport(registry);
    // ignore: avoid_print
    print('FAST_SUITE: ${cov.implemented}/${cov.total} flows registered.');
    expect(cov.implemented, greaterThanOrEqualTo(32),
        reason: 'Fast shared suite must cover at least the shared flow set.');
  }, timeout: const Timeout(Duration(seconds: 10)));
}
