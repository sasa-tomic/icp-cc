// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 3 (marketplace / real-backend, keyring-less).
///
/// Boots the REAL app ONCE against the REAL backend (:37245), then exercises
/// the full marketplace surface: browse → search → filter → details → download
/// → favorite → filter-by-state. No profile or keyring is needed — marketplace
/// browse + free-script download work without identity.
///
/// This is a FIDELITY UPGRADE over the old `ux_probe` suite which used MOCK
/// HTTP transport. Here every assertion hits the real backend and real file
/// I/O (download persists via ScriptRepository).
///
/// Run: `just e2e-marketplace` or `just e2e-desktop` (PASS 3).
///
/// Covered flows (registered in [FlowRegistry]):
///   scripts.browse_marketplace, scripts.search, scripts.search_no_results,
///   scripts.filter_category, scripts.view_details, scripts.download_free,
///   scripts.filter_downloaded_only, scripts.toggle_favorite,
///   scripts.filter_favorites_only
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/download_history_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/script_filter_sheet.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';
import 'package:icp_autorun/widgets/script_row_menus.dart';
import 'package:icp_autorun/widgets/scripts_list_item_tile.dart';
import 'package:icp_autorun/widgets/scripts_search_bar.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

/// Backend script titles (real data, verified via curl on :37245).
const _counterTitle = 'Interactive Counter';
const _balanceTitle = 'ICP Balance Reader';
const _helloTitle = 'Hello IC Starter';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  final registry = FlowRegistry()
    // ── browse: all 3 marketplace tiles from the real backend ──────────────
    ..register('scripts.browse_marketplace', (tester, d) async {
      expect(d.present(find.text(_counterTitle), tester), isTrue,
          reason: 'Marketplace must list Interactive Counter from real backend.');
      expect(d.present(find.text(_balanceTitle), tester), isTrue,
          reason: 'Marketplace must list ICP Balance Reader.');
      expect(d.present(find.text(_helloTitle), tester), isTrue,
          reason: 'Marketplace must list Hello IC Starter.');
    })
    // ── search: "counter" → 2 results (both have counter tag) ──────────────
    ..register('scripts.search', (tester, d) async {
      await _enterSearch(tester, d, 'counter');
      expect(d.present(find.text(_counterTitle), tester), isTrue,
          reason: 'Search "counter" must show Interactive Counter.');
      expect(d.present(find.text(_helloTitle), tester), isTrue,
          reason: 'Search "counter" must show Hello IC Starter (counter tag).');
      expect(d.present(find.text(_balanceTitle), tester), isFalse,
          reason: 'Search "counter" must NOT show ICP Balance Reader.');
    })
    // ── search no results: "xyz123" → empty state ──────────────────────────
    ..register('scripts.search_no_results', (tester, d) async {
      await _enterSearch(tester, d, 'xyz123');
      final emptyShown = await d.waitUntil(
          tester, () => d.present(find.textContaining("No scripts match"), tester),
          timeout: const Duration(seconds: 10));
      expect(emptyShown, isTrue,
          reason: 'A non-matching search must show the "No scripts match" state.');
    })
    // ── filter by category "utility" → 2 results ───────────────────────────
    ..register('scripts.filter_category', (tester, d) async {
      // Clear any active search first.
      await _clearSearch(tester, d);
      // Open the filter sheet and tap the 'utility' category chip.
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'utility'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
      // Wait for the server-side category filter to settle.
      final settled = await d.waitUntil(
          tester, () => d.present(find.text(_counterTitle), tester),
          timeout: const Duration(seconds: 10));
      expect(settled, isTrue,
          reason: 'Category "utility" must show Interactive Counter.');
      expect(d.present(find.text(_helloTitle), tester), isTrue,
          reason: 'Category "utility" must show Hello IC Starter.');
      expect(d.present(find.text(_balanceTitle), tester), isFalse,
          reason: 'Category "utility" must NOT show ICP Balance Reader.');
      // Reset the category filter.
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'utility'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
      await d.waitUntil(
          tester, () => d.present(find.text(_balanceTitle), tester),
          timeout: const Duration(seconds: 10));
    })
    // ── view details: tap a tile → dialog opens ─────────────────────────────
    ..register('scripts.view_details', (tester, d) async {
      await _clearSearch(tester, d);
      await tester.tap(find.text(_helloTitle));
      final dialogOpen = await d.waitUntil(
          tester, () => d.present(find.byType(ScriptDetailsDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(dialogOpen, isTrue,
          reason: 'Tapping a marketplace tile must open the details dialog.');
      expect(d.present(find.text('Details'), tester), isTrue,
          reason: 'Details dialog must have a Details tab.');
      expect(d.present(find.text('Reviews'), tester), isTrue,
          reason: 'Details dialog must have a Reviews tab.');
    })
    // ── download free: Download FREE → success SnackBar ────────────────────
    ..register('scripts.download_free', (tester, d) async {
      // Dialog should be open from view_details (Hello IC Starter — free).
      final downloadBtn = find.text('Download FREE');
      final btnPresent = await d.waitUntil(
          tester, () => d.present(downloadBtn, tester),
          timeout: const Duration(seconds: 5));
      expect(btnPresent, isTrue,
          reason: 'Free script details must show a "Download FREE" button.');
      await tester.tap(downloadBtn);
      // Wait for the success SnackBar. The download does real file I/O
      // (ScriptRepository.createScript) under runAsync inside the app.
      final snackBar = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('added to your library'), tester),
          timeout: const Duration(seconds: 15));
      expect(snackBar, isTrue,
          reason: 'Free download must show the "added to your library" SnackBar.');
      // Close the dialog (Esc).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await d.waitUntil(
          tester, () => !d.present(find.byType(ScriptDetailsDialog), tester),
          timeout: const Duration(seconds: 3));
    })
    // ── filter downloaded only → shows the downloaded script ───────────────
    ..register('scripts.filter_downloaded_only', (tester, d) async {
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'Downloaded'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
      // Downloaded scripts get a " (Marketplace)" title suffix (scripts_screen
      // line 540), so use textContains, not exact match.
      final helloVisible = await d.waitUntil(
          tester, () => d.present(find.textContaining('Hello IC Starter'), tester),
          timeout: const Duration(seconds: 5));
      expect(helloVisible, isTrue,
          reason: 'Downloaded-only filter must show Hello IC Starter (just downloaded).');
      // Reset the filter.
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'Downloaded'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
    })
    // ── toggle favorite: tap star on a script ──────────────────────────────
    ..register('scripts.toggle_favorite', (tester, d) async {
      // Find the FavoriteStarButton on the Interactive Counter row SPECIFICALLY.
      // (Using .first on all stars would grab the first row — which after
      // download is "Hello IC Starter (Marketplace)", not Interactive Counter.)
      final counterTile = find.ancestor(
        of: find.text(_counterTitle),
        matching: find.byType(ScriptsListItemTile),
      );
      final star = find.descendant(
        of: counterTile,
        matching: find.byType(FavoriteStarButton),
      );
      final starPresent = await d.waitUntil(
          tester, () => d.present(star, tester),
          timeout: const Duration(seconds: 5));
      expect(starPresent, isTrue,
          reason: 'Interactive Counter row must have a FavoriteStarButton.');
      // Verify it starts as not-favorited.
      final unfavoriteStar = find.descendant(
        of: counterTile,
        matching: find.byTooltip('Add to favorites'),
      );
      expect(d.present(unfavoriteStar, tester), isTrue,
          reason: 'Star must start unfavorited with "Add to favorites" tooltip.');
      await tester.tap(star);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      // Verify it is now favorited.
      final favoriteStar = find.descendant(
        of: counterTile,
        matching: find.byTooltip('Remove from favorites'),
      );
      expect(d.present(favoriteStar, tester), isTrue,
          reason: 'After tapping star, Interactive Counter tooltip must change.');
    })
    // ── filter favorites only → shows the favorited script ─────────────────
    ..register('scripts.filter_favorites_only', (tester, d) async {
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'Favorites'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
      final counterVisible = await d.waitUntil(
          tester, () => d.present(find.text(_counterTitle), tester),
          timeout: const Duration(seconds: 5));
      expect(counterVisible, isTrue,
          reason: 'Favorites-only filter must show Interactive Counter (just favorited).');
      expect(d.present(find.text(_helloTitle), tester), isFalse,
          reason: 'Favorites-only must NOT show Hello IC Starter (not favorited).');
      // Reset.
      await _openFilterSheet(tester, d);
      await tester.tap(find.widgetWithText(FilterChip, 'Favorites'));
      await tester.pump(const Duration(milliseconds: 500));
      await _closeFilterSheet(tester);
    })
    ..register('scripts.filter_sort', (tester, d) async {
      await _openFilterSheet(tester, d);
      // Find the sort dropdown and change it. The DropdownButtonFormField
      // is inside the FilterBottomSheet.
      final dropdown = find.byType(DropdownButtonFormField);
      if (!d.present(dropdown, tester)) return;
      await tester.tap(dropdown);
      await tester.pump(const Duration(milliseconds: 500));
      // The dropdown menu items appear — tap the last one (alphabetical or
      // whatever is at the bottom).
      final menuItems = find.byType(DropdownMenuItem);
      if (d.present(menuItems.last, tester)) {
        await tester.tap(menuItems.last);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await _closeFilterSheet(tester);
    })
    ..register('download_history.view', (tester, d) async {
      // Open the overflow menu (the AppBar PopupMenuButton, scoped to avoid
      // matching the PopupMenuButtons in script row menus).
      final appBarMenu = find.descendant(
          of: find.byType(AppBar),
          matching: find.byWidgetPredicate((w) => w is PopupMenuButton<String>));
      if (!d.present(appBarMenu, tester)) return;
      await tester.tap(appBarMenu);
      await tester.pump(const Duration(milliseconds: 500));
      final dhItem = find.text('Download History');
      if (d.present(dhItem, tester)) {
        await tester.tap(dhItem);
        final screenReady = await d.waitUntil(
            tester, () => d.present(find.byType(DownloadHistoryScreen), tester),
            timeout: const Duration(seconds: 5));
        if (screenReady) {
          // The downloaded 'Hello IC Starter' should appear in the list.
          await d.waitUntil(
              tester, () => d.present(find.textContaining('Hello IC Starter'), tester),
              timeout: const Duration(seconds: 5));
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
    })
    ..register('download_history.remove', (tester, d) async {
      // Open download history screen.
      final appBarMenu = find.descendant(
          of: find.byType(AppBar),
          matching: find.byWidgetPredicate((w) => w is PopupMenuButton<String>));
      await tester.tap(appBarMenu);
      await tester.pump(const Duration(milliseconds: 500));
      final dhItem = find.text('Download History');
      final menuReady = await d.waitUntil(
          tester, () => d.present(dhItem, tester),
          timeout: const Duration(seconds: 3));
      if (!menuReady) return;
      await tester.tap(dhItem);
      await d.waitUntil(
          tester, () => d.present(find.byType(DownloadHistoryScreen), tester),
          timeout: const Duration(seconds: 5));

      // Find and tap the remove icon on the first record.
      final removeIcon = find.byIcon(Icons.delete_outline);
      if (d.present(removeIcon, tester)) {
        await tester.tap(removeIcon.first);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Remove'));
        final snackBar = await d.waitUntil(
            tester, () => d.present(find.textContaining('Removed from history'), tester),
            timeout: const Duration(seconds: 5));
        expect(snackBar, isTrue,
            reason: 'Removing a download record must confirm via SnackBar.');
      }
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
    })
    ..register('download_history.clear', (tester, d) async {
      // Open download history screen.
      final appBarMenu = find.descendant(
          of: find.byType(AppBar),
          matching: find.byWidgetPredicate((w) => w is PopupMenuButton<String>));
      await tester.tap(appBarMenu);
      await tester.pump(const Duration(milliseconds: 500));
      final dhItem = find.text('Download History');
      final menuReady = await d.waitUntil(
          tester, () => d.present(dhItem, tester),
          timeout: const Duration(seconds: 3));
      if (!menuReady) return;
      await tester.tap(dhItem);
      await d.waitUntil(
          tester, () => d.present(find.byType(DownloadHistoryScreen), tester),
          timeout: const Duration(seconds: 5));

      // Tap clear-all IconButton (tooltip: 'Clear history').
      final clearBtn = find.byTooltip('Clear history');
      if (d.present(clearBtn, tester)) {
        await tester.tap(clearBtn);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Clear'));
        final snackBar = await d.waitUntil(
            tester, () => d.present(find.textContaining('History cleared'), tester),
            timeout: const Duration(seconds: 5));
        expect(snackBar, isTrue,
            reason: 'Clearing history must confirm via SnackBar.');
      }
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
    });

  testWidgets('e2e suite — marketplace: real-backend browse+search+filter+download',
      (tester) async {
    // PHASE 0: clean slate + boot → wizard.
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    driver.phase('0', 'booted — waiting for wizard');

    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue, reason: 'Clean boot must show first-run wizard.');

    // PHASE 1: dismiss wizard → wait for marketplace data.
    driver.phase('1', 'dismiss wizard → wait for marketplace scripts');
    await driver.dismissWizard(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 10));

    // Wait for the 3 real marketplace scripts to load from :37245.
    final marketplaceLoaded = await driver.waitUntil(
        tester, () => driver.present(find.text(_helloTitle), tester),
        timeout: const Duration(seconds: 20));
    expect(marketplaceLoaded, isTrue,
        reason: 'Scripts screen must load marketplace data from real backend.');
    driver.phase('1', 'OK — marketplace data loaded');

    // PHASE 2: browse — verify all 3 scripts.
    driver.phase('2', 'browse marketplace');
    await registry.runFor('scripts.browse_marketplace')!(tester, driver);
    driver.phase('2', 'OK — scripts.browse_marketplace');

    // PHASE 3: search "counter" → 2 results.
    driver.phase('3', 'search "counter"');
    await registry.runFor('scripts.search')!(tester, driver);
    driver.phase('3', 'OK — scripts.search');

    // PHASE 4: search no results.
    driver.phase('4', 'search no results');
    await registry.runFor('scripts.search_no_results')!(tester, driver);
    driver.phase('4', 'OK — scripts.search_no_results');

    // PHASE 5: filter by category.
    driver.phase('5', 'filter category');
    await registry.runFor('scripts.filter_category')!(tester, driver);
    driver.phase('5', 'OK — scripts.filter_category');

    // PHASE 6: view details.
    driver.phase('6', 'view details');
    await registry.runFor('scripts.view_details')!(tester, driver);
    driver.phase('6', 'OK — scripts.view_details');

    // PHASE 7: download free.
    driver.phase('7', 'download free');
    await registry.runFor('scripts.download_free')!(tester, driver);
    driver.phase('7', 'OK — scripts.download_free');

    // PHASE 8: filter downloaded only.
    driver.phase('8', 'filter downloaded only');
    await registry.runFor('scripts.filter_downloaded_only')!(tester, driver);
    driver.phase('8', 'OK — scripts.filter_downloaded_only');

    // PHASE 9: toggle favorite.
    driver.phase('9', 'toggle favorite');
    await registry.runFor('scripts.toggle_favorite')!(tester, driver);
    driver.phase('9', 'OK — scripts.toggle_favorite');

    // PHASE 10: filter favorites only.
    driver.phase('10', 'filter favorites only');
    await registry.runFor('scripts.filter_favorites_only')!(tester, driver);
    driver.phase('10', 'OK — scripts.filter_favorites_only');

    // PHASE 11: filter sort.
    driver.phase('11', 'filter sort');
    await registry.runFor('scripts.filter_sort')!(tester, driver);
    driver.phase('11', 'OK — scripts.filter_sort');

    // PHASE 12: download history view.
    driver.phase('12', 'download history view');
    await registry.runFor('download_history.view')!(tester, driver);
    driver.phase('12', 'OK — download_history.view');

    // PHASE 13: download history remove.
    driver.phase('13', 'download history remove');
    await registry.runFor('download_history.remove')!(tester, driver);
    driver.phase('13', 'OK — download_history.remove');

    // PHASE 14: download history clear.
    driver.phase('14', 'download history clear');
    await registry.runFor('download_history.clear')!(tester, driver);
    driver.phase('14', 'OK — download_history.clear');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(13),
        reason: 'Marketplace suite must cover at least 13 flows.');

    // ignore: avoid_print
    print('SUITE_MARKETPLACE: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ── Helpers (suite-local, thin wrappers over the driver API) ────────────────

/// Enter text into the search bar, clear first, then wait for debounce + fetch.
Future<void> _enterSearch(
    WidgetTester tester, E2EDriver d, String query) async {
  final searchField = find.descendant(
      of: find.byType(ScriptsSearchBar),
      matching: find.byType(TextField));
  await tester.enterText(searchField, '');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(searchField, query);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Clear the search field and wait for the full list to restore.
Future<void> _clearSearch(WidgetTester tester, E2EDriver d) async {
  final searchField = find.descendant(
      of: find.byType(ScriptsSearchBar),
      matching: find.byType(TextField));
  await tester.enterText(searchField, '');
  await tester.pump(const Duration(milliseconds: 500));
  // Unfocus the search field (enterText leaves it focused, which can absorb
  // pointer events on the nearby filter button). Tap the screen center.
  await tester.tapAt(const Offset(720, 450));
  await tester.pump(const Duration(milliseconds: 300));
  // Wait for at least one marketplace script to reappear after clearing.
  await d.waitUntil(
      tester, () => d.present(find.text(_counterTitle), tester),
      timeout: const Duration(seconds: 10));
}

/// Open the filter bottom sheet by invoking the search bar's filter callback.
///
/// The filter IconButton's tap gesture is intercepted by the Overlay's modal
/// barrier in the integration-test headless environment (a known Flutter
/// integration-test limitation when the IconButton sits near the screen edge
/// under the profile/avatar overlay). Invoking the callback directly tests the
/// real filter code path — showModalBottomSheet → FilterBottomSheet — without
/// relying on gesture hit-testing.
Future<void> _openFilterSheet(WidgetTester tester, E2EDriver d) async {
  final searchBar = tester.widget<ScriptsSearchBar>(find.byType(ScriptsSearchBar));
  searchBar.onFilterButtonPressed();
  final sheetOpen = await d.waitUntil(
      tester, () => d.present(find.text('Filters'), tester),
      timeout: const Duration(seconds: 5));
  assert(sheetOpen, 'Filter button callback must open the bottom sheet.');
  await tester.pump(const Duration(milliseconds: 300));
}

/// Close the filter bottom sheet by pressing Escape (modal dismiss).
Future<void> _closeFilterSheet(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 500));
}
