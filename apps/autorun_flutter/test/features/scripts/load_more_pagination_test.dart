// TDD coverage for UX-N2 (scripts load-more UI).
//
// Before this work the ScriptsScreen tracked `_isLoadingMore` / `_hasMore` /
// `_offset` and `_loadMarketplaceScripts(isLoadMore: true)` worked end-to-end,
// but NO UI trigger was wired up — the user could never see past page 1 of the
// marketplace. These tests pin the new behaviour: scrolling near the bottom
// auto-fetches the next page, a "Load more" affordance exists as a fallback,
// the re-entrancy guard holds, and the footer goes honest ("End of results")
// when there are no more pages.
//
// Uses the real [ScriptsScreen] DI seam (`marketplaceService:`) with
// [PagedFakeMarketplaceOpenApi], which honours the real pagination contract
// (slice + `hasMore`). No network, no FFI.
//
// Two non-obvious harness quirks pinned here (documented so the next reader
// doesn't re-discover them):
//   1. There are MULTIPLE `Scrollable`s under ScriptsScreen (the main
//      CustomScrollView plus a sibling from the search/fab chrome). Dragging
//      `find.byType(Scrollable).first` hits the wrong one and the load-more
//      trigger never fires. Always drag `find.byType(CustomScrollView)`.
//   2. The footer (Load more button / End of results text / in-flight
//      spinner) lives in a `SliverToBoxAdapter` whose child is lazily built
//      ONLY when on-screen. With a phone-sized test viewport (800x1200) the
//      footer sits below the scroll extent and is never painted, so
//      `find.text('Load more')` returns 0 even though state is correct.
//      Footer-visibility assertions use a large viewport (1200x3200) where
//      every row + the footer render at once. Auto-load-on-scroll tests use
//      the small viewport (so the list actually scrolls) and assert on the
//      API-call contract + scroll the target into view before asserting on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_scripts_test_harness.dart';
import 'paged_fake_marketplace_open_api.dart';

void main() {
  /// Build N free marketplace scripts. Title format is unique so a sentinel
  /// like `find.text('Marketplace Script 39')` is unambiguous.
  List<MarketplaceScript> seed(int n) => List.generate(
        n,
        (i) => aMarketplaceScript(
          id: 'mp-$i',
          title: 'Marketplace Script $i',
        ),
      );

  /// Phone-sized viewport (~11 rows visible) — used when we need real scroll
  /// semantics (maxScrollExtent > 0) to exercise the auto-load trigger.
  Future<void> usePhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Large viewport — used when we need the footer SliverToBoxAdapter child
  /// to actually paint (Load more button / End of results text / spinner).
  /// ~32 rows + footer fit comfortably; the remaining rows in a 40-row seed
  /// are below the fold and verified by scrolling rather than by count.
  Future<void> useLargeViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Finder for the main CustomScrollView's actual Scrollable descendant.
  ///
  /// `scrollUntilVisible` casts the matched widget to `Scrollable`, so passing
  /// `find.byType(CustomScrollView)` directly throws. And `find.byType(Scrollable)`
  /// matches multiple widgets under ScriptsScreen (main + a sibling from the
  /// chrome) — `.first` grabs the wrong one. This finder nails the one that
  /// scrolls the unified list.
  Finder mainScrollable() => find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );

  group('scripts load-more (UX-N2)', () {
    setUp(() {
      // Without this, _loadSavedCategory()'s SharedPreferences platform
      // channel hangs the first marketplace fetch.
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'scrolling near the bottom auto-loads the next page when hasMore is true',
        (tester) async {
      await usePhoneViewport(tester);

      final api = PagedFakeMarketplaceOpenApi(scripts: seed(40));
      await pumpScriptsScreen(tester, marketplaceService: api);
      await tester.pumpAndSettle();

      // Page 1 fetch happened at mount.
      expect(api.calls, [0]);

      // Drag the (real) main scrollable to the bottom. CustomScrollView —
      // NOT Scrollable.first, which hits a sibling Scrollable from the chrome.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      // Page 2 fetched at offset 20 — primary contract.
      expect(api.calls, [0, 20]);

      // The unified list grew: scroll the last item into view and verify.
      await tester.scrollUntilVisible(
        find.text('Marketplace Script 39'),
        250,
        scrollable: mainScrollable(),
      );
      expect(find.text('Marketplace Script 39'), findsOneWidget);
    });

    testWidgets(
        're-entrancy guard: a second scroll while page 2 is in flight does NOT issue a duplicate fetch',
        (tester) async {
      await usePhoneViewport(tester);

      final api = PagedFakeMarketplaceOpenApi(
        scripts: seed(60),
        callDelay: const Duration(milliseconds: 50),
      );
      await pumpScriptsScreen(tester, marketplaceService: api);
      await tester.pumpAndSettle();
      expect(api.calls, [0]);

      // Big drag past the bottom; multiple scroll notifications arrive while
      // the page-2 fetch is still in flight. The guard (_isLoadingMore)
      // must absorb the second one.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -3000),
      );
      await tester.pump(); // no time advance — fetch still in flight
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      // Exactly one page-2 call (offset 20) — NOT two.
      expect(api.calls, [0, 20]);
    });

    testWidgets(
        'when hasMore is false on page 1, no load-more affordance renders and no second fetch issues',
        (tester) async {
      await useLargeViewport(tester);

      // 15 scripts — fewer than one page. hasMore=false from page 1.
      final api = PagedFakeMarketplaceOpenApi(scripts: seed(15));
      await pumpScriptsScreen(tester, marketplaceService: api);
      await tester.pumpAndSettle();

      expect(api.calls, [0]);
      expect(find.textContaining('Marketplace Script '), findsNWidgets(15));
      expect(find.text('Load more'), findsNothing);
      // Honest end state.
      expect(find.text('End of results'), findsOneWidget);
    });

    testWidgets(
        'tapping the "Load more" button fetches the next page (keyboard / tap fallback)',
        (tester) async {
      await useLargeViewport(tester);

      final api = PagedFakeMarketplaceOpenApi(scripts: seed(40));
      await pumpScriptsScreen(tester, marketplaceService: api);
      await tester.pumpAndSettle();
      expect(api.calls, [0]);

      // Large viewport: the footer (with the button) paints without scrolling.
      final loadMore = find.text('Load more');
      expect(loadMore, findsOneWidget);
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(api.calls, [0, 20]);
      // Button gone from the widget tree — state transitioned to hasMore=false.
      expect(find.text('Load more'), findsNothing);
      // Scroll the footer into view (40 rows push it below the fold) and
      // verify the honest end-state caption.
      await tester.scrollUntilVisible(
        find.text('End of results'),
        250,
        scrollable: mainScrollable(),
      );
      expect(find.text('End of results'), findsOneWidget);
      // And the last row of page 2 actually entered the unified list.
      await tester.scrollUntilVisible(
        find.text('Marketplace Script 39'),
        250,
        scrollable: mainScrollable(),
      );
      expect(find.text('Marketplace Script 39'), findsOneWidget);
    });

    testWidgets(
        'footer shows an in-flight indicator while page 2 is loading',
        (tester) async {
      await useLargeViewport(tester);

      final api = PagedFakeMarketplaceOpenApi(
        scripts: seed(40),
        callDelay: const Duration(milliseconds: 200),
      );
      await pumpScriptsScreen(tester, marketplaceService: api);
      await tester.pumpAndSettle();

      final loadMore = find.text('Load more');
      expect(loadMore, findsOneWidget);

      // Trigger page 2 and STOP before it settles — the in-flight indicator
      // must be on screen and the button must be gone (prevents re-tap).
      await tester.tap(loadMore);
      await tester.pump(); // start the fetch, don't settle

      expect(
        find.bySubtype<CircularProgressIndicator>(),
        findsWidgets,
      );
      expect(find.text('Load more'), findsNothing);

      await tester.pumpAndSettle();
      expect(api.calls, [0, 20]);
    });
  });
}
