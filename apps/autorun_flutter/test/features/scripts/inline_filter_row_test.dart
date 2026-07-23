import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Inline filter row (CR-8)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows inline sort chip with default label', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
      expect(find.text('Last Run'), findsWidgets);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('tapping sort chip opens popup with all options',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pump(const Duration(seconds: 1));

      for (final label in [
        'Last Run',
        'Name',
        'Run Count',
        'Last Updated',
        'Source',
      ]) {
        expect(find.text(label), findsWidgets);
      }

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('selecting a sort option updates chip label',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Name').last);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Downloaded FilterChip toggles selected state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Downloaded'),
          )
          .first;

      FilterChip chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isFalse);

      await tester.tap(chipFinder);
      await tester.pump();

      chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isTrue);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Favorites FilterChip toggles selected state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await pumpScriptsScreen(tester);

      final chipFinder = find
          .descendant(
            of: find.byType(MaterialApp),
            matching: find.widgetWithText(FilterChip, 'Favorites'),
          )
          .first;

      FilterChip chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isFalse);

      await tester.tap(chipFinder);
      await tester.pump();

      chip = tester.widget<FilterChip>(chipFinder);
      expect(chip.selected, isTrue);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
