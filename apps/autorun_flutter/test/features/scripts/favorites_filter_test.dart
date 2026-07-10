import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/screens/script_filter_sheet.dart';
import 'package:icp_autorun/services/favorites_service.dart';
import 'package:icp_autorun/widgets/scripts_empty_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_scripts_test_harness.dart';

/// Favorites filter behaviour.
///
/// The previous version of this file was almost entirely
/// `expect(true, isTrue)` "verified by code inspection" placeholders — nine
/// tests that could never fail and so masked the missing real coverage (the
/// sibling `active_filter_chips_test.dart` was already cleaned up from the same
/// antipattern). These tests drive the real widgets ([FilterBottomSheet]
/// Favorites chip + [ScriptsEmptyState] favorites variant) and the real
/// [FavoritesService]; every assertion below can go red on a real regression.
void main() {
  group('FilterBottomSheet Favorites chip', () {
    FilterBottomSheet buildSheet({
      required bool showFavoritesOnly,
      ValueChanged<bool>? onFavoritesFilterChanged,
    }) {
      return FilterBottomSheet(
        categories: const ['All'],
        selectedCategory: 'All',
        sortOption: ScriptSortOption.updatedAt,
        sortAscending: false,
        showDownloadedOnly: false,
        showFavoritesOnly: showFavoritesOnly,
        onCategoryChanged: (_) {},
        onSortChanged: (_, __) {},
        onDownloadedFilterChanged: (_) {},
        onFavoritesFilterChanged: onFavoritesFilterChanged ?? (_) {},
        onReset: () {},
      );
    }

    Finder favoritesChip() => find.ancestor(
          of: find.text('Favorites'),
          matching: find.byType(FilterChip),
        );

    testWidgets('renders a FilterChip labelled "Favorites"', (tester) async {
      await pumpInScaffold(tester, buildSheet(showFavoritesOnly: false));

      expect(favoritesChip(), findsOneWidget);
    });

    testWidgets('is unselected when the filter is inactive', (tester) async {
      await pumpInScaffold(tester, buildSheet(showFavoritesOnly: false));

      expect(
        tester.widget<FilterChip>(favoritesChip()).selected,
        isFalse,
      );
    });

    testWidgets('is selected when the filter is active', (tester) async {
      await pumpInScaffold(tester, buildSheet(showFavoritesOnly: true));

      expect(
        tester.widget<FilterChip>(favoritesChip()).selected,
        isTrue,
      );
    });

    testWidgets('tapping the chip fires onFavoritesFilterChanged(true)',
        (tester) async {
      bool? captured;
      await pumpInScaffold(
        tester,
        buildSheet(
          showFavoritesOnly: false,
          onFavoritesFilterChanged: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('Favorites'));
      await tester.pump();

      expect(captured, isTrue);
    });
  });

  group('Favorites filter empty state', () {
    testWidgets('shows favorites-specific copy when the filter is active',
        (tester) async {
      await pumpInScaffold(
        tester,
        const ScriptsEmptyState(kind: ScriptsEmptyStateKind.favoritesFilter),
      );
      // ModernEmptyState schedules staggered entrance animations via
      // Future.delayed; pumpAndSettle flushes those timers (otherwise the test
      // framework fails on a pending timer) and finishes the fade-in.
      await tester.pumpAndSettle();

      expect(find.text("You haven't favorited any scripts yet"), findsOneWidget);
      expect(
        find.text('Tap the star icon on scripts to add them to favorites'),
        findsOneWidget,
      );
    });

    testWidgets('Browse Scripts action clears the favorites filter',
        (tester) async {
      var clearCalls = 0;
      await pumpInScaffold(
        tester,
        ScriptsEmptyState(
          kind: ScriptsEmptyStateKind.favoritesFilter,
          onClearFavoritesFilter: () => clearCalls++,
        ),
      );
      // Settle the entrance animations so the action button is rendered and
      // hittable (it starts at opacity 0).
      await tester.pumpAndSettle();

      await tester.tap(find.text('Browse Scripts'));
      await tester.pump();

      expect(clearCalls, 1);
    });
  });

  group('FavoritesService', () {
    late FavoritesService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = FavoritesService();
    });

    tearDown(() async {
      await service.clearFavorites();
    });

    test('can be instantiated', () {
      expect(service, isNotNull);
    });

    test('starts with empty favorites', () async {
      expect(await service.getAllFavorites(), isEmpty);
    });

    // Comprehensive FavoritesService coverage (toggle / isFavorite / stream /
    // persistence / edge cases) lives in test/services/favorites_service_test.dart;
    // this group is intentionally just a colocated smoke check for the filter.
  });
}
