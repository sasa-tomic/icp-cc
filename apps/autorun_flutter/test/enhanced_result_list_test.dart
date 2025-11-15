import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:icp_autorun/widgets/result_display.dart';

void main() {
  group('EnhancedResultList Widget Tests', () {
    final sampleItems = [
      {'title': 'Item 1', 'subtitle': 'Description 1', 'type': 'transfer'},
      {'title': 'Item 2', 'subtitle': 'Description 2', 'type': 'stake'},
      {'title': 'Item 3', 'subtitle': 'Description 3', 'type': 'transfer'},
    ];

    testWidgets('displays list with items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Test List',
            ),
          ),
        ),
      );

      expect(find.text('Test List'), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget); // Shows count
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
      expect(find.text('Description 1'), findsOneWidget);
      expect(find.text('Description 2'), findsOneWidget);
      expect(find.text('Description 3'), findsOneWidget);
    });

    testWidgets('displays custom title', (WidgetTester tester) async {
      const customTitle = 'Custom Results';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: customTitle,
            ),
          ),
        ),
      );

      expect(find.text(customTitle), findsOneWidget);
    });

    testWidgets('displays count correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Count Test',
            ),
          ),
        ),
      );

      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('shows no results message for empty list', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: [],
              title: 'Empty List',
            ),
          ),
        ),
      );

      expect(find.text('Empty List'), findsOneWidget);
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('search functionality filters items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Search Test',
              searchable: true,
            ),
          ),
        ),
      );

      expect(find.text('Search results...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      // Initially shows all items
      expect(find.text('3/3'), findsOneWidget);

      // Enter search term
      await tester.enterText(find.byType(TextField), 'Item 1');
      await tester.pumpAndSettle();

      // Should show filtered count
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsNothing);
      expect(find.text('Item 3'), findsNothing);
    });

    testWidgets('search is case insensitive', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Case Insensitive Test',
              searchable: true,
            ),
          ),
        ),
      );

      // Search with lowercase
      await tester.enterText(find.byType(TextField), 'item 2');
      await tester.pumpAndSettle();

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);

      // Search with uppercase
      await tester.enterText(find.byType(TextField), 'ITEM 3');
      await tester.pumpAndSettle();

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('search filters across all fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Multi-field Search',
              searchable: true,
            ),
          ),
        ),
      );

      // Search in subtitle
      await tester.enterText(find.byType(TextField), 'Description 1');
      await tester.pumpAndSettle();

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);

      // Search in custom field
      await tester.enterText(find.byType(TextField), 'transfer');
      await tester.pumpAndSettle();

      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('search shows no results for non-matching term', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'No Match Search',
              searchable: true,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('0/3'), findsOneWidget);
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('search can be cleared', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Clear Search Test',
              searchable: true,
            ),
          ),
        ),
      );

      // Search for something
      await tester.enterText(find.byType(TextField), 'Item 1');
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      // Clear search
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('menu shows copy and details options', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Menu Test',
              searchable: false,
            ),
          ),
        ),
      );

      // Find and tap menu button on first item
      final menuButtons = find.byIcon(Icons.more_vert);
      expect(menuButtons, findsWidgets);

      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
    });

    testWidgets('copy action copies item to clipboard', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Copy Test',
              searchable: false,
            ),
          ),
        ),
      );

      // Open menu and tap copy
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(find.text('Item copied to clipboard'), findsOneWidget);
    });

    testWidgets('details action shows item details dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Details Test',
              searchable: false,
            ),
          ),
        ),
      );

      // Open menu and tap details
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget); // Dialog title
      expect(find.byType(SelectableText), findsWidgets); // JSON content
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('details dialog can be closed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Close Dialog Test',
              searchable: false,
            ),
          ),
        ),
      );

      // Open details dialog
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget); // Still visible in list
      expect(find.byType(Dialog), findsNothing); // Dialog closed
    });

    testWidgets('searchable can be disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: sampleItems,
              title: 'Not Searchable',
              searchable: false,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('handles items with missing fields gracefully', (WidgetTester tester) async {
      final incompleteItems = [
        {'title': 'Only Title'},
        {'subtitle': 'Only Subtitle'},
        {'title': 'Complete Item', 'subtitle': 'Has both'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: incompleteItems,
              title: 'Incomplete Items Test',
            ),
          ),
        ),
      );

      expect(find.text('Only Title'), findsOneWidget);
      expect(find.text('Only Subtitle'), findsOneWidget);
      expect(find.text('Complete Item'), findsOneWidget);
      expect(find.text('Has both'), findsOneWidget);
    });

    testWidgets('items without data field still show menu', (WidgetTester tester) async {
      final itemsWithoutData = [
        {'title': 'No Data Field 1'},
        {'title': 'No Data Field 2'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: itemsWithoutData,
              title: 'No Data Field Test',
            ),
          ),
        ),
      );

      // Should still have menu buttons
      expect(find.byIcon(Icons.more_vert), findsWidgets);

      // Menu should only show copy option (no details)
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);
    });

    testWidgets('handles larger item count efficiently', (WidgetTester tester) async {
      final largeItemList = List.generate(20, (index) => {
        'title': 'Item ${index + 1}',
        'subtitle': 'Description ${index + 1}',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedResultList(
              items: largeItemList,
              title: 'Large List Test',
            ),
          ),
        ),
      );

      expect(find.text('Large List Test'), findsOneWidget);
      expect(find.text('20/20'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 20'), findsOneWidget);
    });
  });
}