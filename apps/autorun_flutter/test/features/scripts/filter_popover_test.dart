import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_list_item.dart';

import '_scripts_test_harness.dart';

void main() {
  group('ScriptsScreen filter popover', () {
    testWidgets('filter button opens filter bottom sheet', (tester) async {
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Sort by'), findsOneWidget);
    });

    testWidgets('filter bottom sheet has reset button', (tester) async {
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Reset'), findsOneWidget);
    });

    testWidgets('filter bottom sheet shows category chips', (tester) async {
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      // "All" category chip is shown and selected by default.
      expect(find.widgetWithText(FilterChip, 'All'), findsWidgets);
    });

    testWidgets('filter bottom sheet shows default sort option',
        (tester) async {
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Last Run'), findsOneWidget);
    });
  });

  group('ScriptSortOption', () {
    test('has expected sort options', () {
      expect(ScriptSortOption.values.length, equals(5));
      expect(ScriptSortOption.values.contains(ScriptSortOption.lastRun), isTrue);
      expect(ScriptSortOption.values.contains(ScriptSortOption.name), isTrue);
      expect(
          ScriptSortOption.values.contains(ScriptSortOption.runCount), isTrue);
      expect(
          ScriptSortOption.values.contains(ScriptSortOption.updatedAt), isTrue);
      expect(ScriptSortOption.values.contains(ScriptSortOption.source), isTrue);
    });

    test('has correct labels', () {
      expect(ScriptSortOption.lastRun.label, equals('Last Run'));
      expect(ScriptSortOption.name.label, equals('Name'));
      expect(ScriptSortOption.runCount.label, equals('Run Count'));
      expect(ScriptSortOption.updatedAt.label, equals('Last Updated'));
      expect(ScriptSortOption.source.label, equals('Source'));
    });
  });
}
