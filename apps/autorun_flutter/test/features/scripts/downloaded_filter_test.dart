import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/models/script_list_item.dart';

void main() {
  group('Downloaded filter chip', () {
    testWidgets('appears in filter bottom sheet', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Downloaded'), findsOneWidget);
    });

    testWidgets('is not selected by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      final downloadedChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Downloaded'),
      );
      expect(downloadedChip.selected, isFalse);
    });

    testWidgets('resets with other filters when Reset button tapped',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Reset'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      final downloadedChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Downloaded'),
      );
      expect(downloadedChip.selected, isFalse);
    });
  });

  group('ScriptSortOption', () {
    test('has expected sort options', () {
      expect(ScriptSortOption.values.length, equals(5));
    });
  });
}
