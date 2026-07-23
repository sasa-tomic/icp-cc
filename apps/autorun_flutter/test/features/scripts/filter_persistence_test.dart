import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Filter persistence (CR-6)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('saved sort option is restored on screen load',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      SharedPreferences.setMockInitialValues({
        'last_sort_option': 'name',
      });

      await pumpScriptsScreen(tester);

      // The inline sort chip should now show "Name" instead of "Last Run".
      // On an empty marketplace screen "Name" only appears in the sort chip.
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Last Run'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('saved downloaded filter is restored on screen load',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      SharedPreferences.setMockInitialValues({
        'last_downloaded_only': true,
      });

      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Downloaded'),
          )
          .first;

      final chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isTrue);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('saved favorites filter is restored on screen load',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      SharedPreferences.setMockInitialValues({
        'last_favorites_only': true,
      });

      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Favorites'),
          )
          .first;

      final chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isTrue);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('persisting one filter saves all values (round-trip)',
        (tester) async {
      // Pre-seed with a non-default sort to prove _persistFilters saves it.
      SharedPreferences.setMockInitialValues({
        'last_sort_option': 'name',
      });
      await pumpScriptsScreen(tester);

      // Toggle Downloaded — _persistFilters saves ALL four values.
      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Downloaded'),
          )
          .first;
      await tester.tap(chipFinder);
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_sort_option'), equals('name'));
      expect(prefs.getBool('last_downloaded_only'), isTrue);
    });

    testWidgets('toggling Downloaded filter persists to SharedPreferences',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Downloaded'),
          )
          .first;

      await tester.tap(chipFinder);
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('last_downloaded_only'), isTrue);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('toggling Favorites filter persists to SharedPreferences',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Favorites'),
          )
          .first;

      await tester.tap(chipFinder);
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('last_favorites_only'), isTrue);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
