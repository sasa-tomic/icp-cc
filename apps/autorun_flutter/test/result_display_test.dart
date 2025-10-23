import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/result_display.dart';

void main() {
  group('ResultDisplay Widget Tests', () {
    testWidgets('displays simple text data', (WidgetTester tester) async {
      const data = 'Hello World';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Test Result',
            ),
          ),
        ),
      );

      expect(find.text('Test Result'), findsOneWidget);
      expect(find.text('Hello World'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('displays numeric data', (WidgetTester tester) async {
      const data = 42;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Number Result',
            ),
          ),
        ),
      );

      expect(find.text('Number Result'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('displays map data as key-value pairs', (WidgetTester tester) async {
      final data = {
        'name': 'John Doe',
        'age': 30,
        'active': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'User Data',
            ),
          ),
        ),
      );

      expect(find.text('User Data'), findsOneWidget);
      expect(find.text('name:'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('age:'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('active:'), findsOneWidget);
      expect(find.text('true'), findsOneWidget);
    });

    testWidgets('displays list data with indices', (WidgetTester tester) async {
      final data = ['apple', 'banana', 'cherry'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Fruit List',
            ),
          ),
        ),
      );

      expect(find.text('Fruit List'), findsOneWidget);
      expect(find.text('[0]: '), findsOneWidget);
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('[1]: '), findsOneWidget);
      expect(find.text('banana'), findsOneWidget);
      expect(find.text('[2]: '), findsOneWidget);
      expect(find.text('cherry'), findsOneWidget);
    });

    testWidgets('displays empty object message', (WidgetTester tester) async {
      const data = <String, dynamic>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Empty Object',
            ),
          ),
        ),
      );

      expect(find.text('Empty object'), findsOneWidget);
    });

    testWidgets('displays empty array message', (WidgetTester tester) async {
      const data = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Empty Array',
            ),
          ),
        ),
      );

      expect(find.text('Empty array'), findsOneWidget);
    });

    testWidgets('displays null data message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: null,
              title: 'Null Data',
            ),
          ),
        ),
      );

      expect(find.text('Null Data'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('displays error state', (WidgetTester tester) async {
      const error = 'Something went wrong';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: null,
              error: error,
              title: 'Error Result',
            ),
          ),
        ),
      );

      expect(find.text('Error Result'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('copy button copies to clipboard for text data', (WidgetTester tester) async {
      const data = 'Test data to copy';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Copy Test',
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(find.text('Data copied to clipboard'), findsOneWidget);
    });

    testWidgets('copy button copies error to clipboard', (WidgetTester tester) async {
      const error = 'Error message to copy';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: null,
              error: error,
              title: 'Error Copy Test',
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(find.text('Error copied to clipboard'), findsOneWidget);
    });

    testWidgets('export buttons available for map data', (WidgetTester tester) async {
      final data = {'key': 'value', 'number': 42};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Export Test',
            ),
          ),
        ),
      );

      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('export buttons available for list data', (WidgetTester tester) async {
      const data = ['item1', 'item2'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Export Test',
            ),
          ),
        ),
      );

      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('JSON export copies formatted JSON to clipboard', (WidgetTester tester) async {
      final data = {'name': 'Test', 'value': 123};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'JSON Export Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      expect(find.text('JSON copied to clipboard'), findsOneWidget);
    });

    testWidgets('CSV export copies CSV to clipboard for map data', (WidgetTester tester) async {
      final data = {'column1': 'value1', 'column2': 'value2'};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'CSV Export Test',
            ),
          ),
        ),
      );

      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();

      expect(find.text('CSV copied to clipboard'), findsOneWidget);
    });

    testWidgets('handles nested objects with expansion', (WidgetTester tester) async {
      final data = {
        'user': {
          'name': 'John',
          'details': {
            'age': 30,
            'city': 'New York'
          }
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Nested Data',
            ),
          ),
        ),
      );

      expect(find.text('Nested Data'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsWidgets);

      // Tap to expand nested object
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // Should show the nested content
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('handles long text with expansion', (WidgetTester tester) async {
      final longText = 'A' * 300; // 300 characters
      expect(longText.length, greaterThan(200));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: longText,
              title: 'Long Text',
            ),
          ),
        ),
      );

      expect(find.text('Long Text'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('300 characters'), findsOneWidget);
    });

    testWidgets('detects table-like structures', (WidgetTester tester) async {
      final tableData = {
        'name': 'John',
        'age': 30,
        'city': 'New York',
        'active': true
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: tableData,
              title: 'Table Data',
            ),
          ),
        ),
      );

      expect(find.text('Table View (4 rows)'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('without title works correctly', (WidgetTester tester) async {
      const data = 'No title data';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
            ),
          ),
        ),
      );

      expect(find.text('No title data'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('isExpandable parameter controls expansion functionality', (WidgetTester tester) async {
      const data = 'Expandable data';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultDisplay(
              data: data,
              title: 'Expandable Test',
              isExpandable: false,
            ),
          ),
        ),
      );

      // Should not show expand icon when expandable is false
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });
}