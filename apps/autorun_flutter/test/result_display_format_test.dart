import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/result_display.dart';

void main() {
  group('ResultDisplay Format Toggle Tests', () {
    testWidgets('format toggle buttons appear for map data',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30, 'city': 'NYC', 'active': true};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Format Test',
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('JSON'), findsWidgets);
      expect(find.text('Raw'), findsOneWidget);
      expect(find.text('Table'), findsOneWidget);
    });

    testWidgets('format toggle buttons appear for list data',
        (WidgetTester tester) async {
      const data = ['item1', 'item2', 'item3'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Format Test',
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('JSON'), findsWidgets);
      expect(find.text('Raw'), findsOneWidget);
    });

    testWidgets('JSON format shows formatted JSON string',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'JSON Format Test',
            ),
          ),
        ),
      );

      final toggleButtons = find.byType(ToggleButtons);
      await tester
          .tap(find.descendant(of: toggleButtons, matching: find.text('JSON')));
      await tester.pumpAndSettle();

      final selectableTexts =
          tester.widgetList<SelectableText>(find.byType(SelectableText));
      final allText = selectableTexts.map((t) => t.data ?? '').join('\n');
      expect(allText, contains('"name"'));
      expect(allText, contains('"John"'));
    });

    testWidgets('Raw format shows unformatted value',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Raw Format Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();

      final selectableTexts =
          tester.widgetList<SelectableText>(find.byType(SelectableText));
      final allText = selectableTexts.map((t) => t.data ?? '').join('\n');
      expect(allText, contains('name'));
    });

    testWidgets('Table format shows DataTable for appropriate data',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30, 'city': 'NYC', 'active': true};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Table Format Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Table View (4 rows)'), findsOneWidget);
    });

    testWidgets('Auto format uses automatic detection for table-like data',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30, 'city': 'NYC', 'active': true};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Auto Format Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('format selection persists in widget state',
        (WidgetTester tester) async {
      final data = {'name': 'John', 'age': 30, 'city': 'NYC', 'active': true};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Format Persistence Test',
            ),
          ),
        ),
      );

      final toggleButtons = find.byType(ToggleButtons);
      await tester
          .tap(find.descendant(of: toggleButtons, matching: find.text('JSON')));
      await tester.pumpAndSettle();

      var selectableTexts =
          tester.widgetList<SelectableText>(find.byType(SelectableText));
      var allText = selectableTexts.map((t) => t.data ?? '').join('\n');
      expect(allText, contains('"name"'));

      await tester.tap(
          find.descendant(of: toggleButtons, matching: find.text('Table')));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('format toggle does not appear for simple string data',
        (WidgetTester tester) async {
      const data = 'Simple string';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Simple Test',
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsNothing);
      expect(find.text('Raw'), findsNothing);
      expect(find.text('Table'), findsNothing);
    });

    testWidgets('format toggle does not appear for numeric data',
        (WidgetTester tester) async {
      const data = 42;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Number Test',
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsNothing);
      expect(find.text('Raw'), findsNothing);
      expect(find.text('Table'), findsNothing);
    });

    testWidgets('Table format falls back to map display for non-table data',
        (WidgetTester tester) async {
      final data = {
        'name': 'John',
        'nested': {'key': 'value'}
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Non-Table Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsNothing);
      expect(find.text('name:'), findsOneWidget);
    });
  });
}
