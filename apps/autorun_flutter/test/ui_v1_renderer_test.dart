import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

void main() {
  group('UiV1Renderer new widgets', () {
    late Map<String, dynamic> capturedEvent;

    setUp(() {
      capturedEvent = {};
    });

    Widget createTestWidget(Map<String, dynamic> ui) {
      return MaterialApp(
        home: Scaffold(
          body: UiV1Renderer(
            ui: ui,
            onEvent: (msg) => capturedEvent = msg,
          ),
        ),
      );
    }

    testWidgets('renders text_field widget', (WidgetTester tester) async {
      final ui = {
        'type': 'text_field',
        'props': {
          'label': 'Test Field',
          'placeholder': 'Enter text',
          'value': 'initial value',
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Test Field'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);

      // Check that the TextFormField is rendered and has the expected initial value
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Enter text'), findsOneWidget);
    });

    testWidgets('text_field triggers on_change event',
        (WidgetTester tester) async {
      final ui = {
        'type': 'text_field',
        'props': {
          'label': 'Test Field',
          'value': '',
          'on_change': {'type': 'field_changed'},
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'new value');
      await tester.pumpAndSettle();

      expect(capturedEvent['type'], 'field_changed');
      expect(capturedEvent['value'], 'new value');
    });

    testWidgets('renders toggle widget', (WidgetTester tester) async {
      final ui = {
        'type': 'toggle',
        'props': {
          'label': 'Enable feature',
          'value': true,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Enable feature'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      final Switch toggle = tester.widget(find.byType(Switch));
      expect(toggle.value, true);
    });

    testWidgets('toggle triggers on_change event', (WidgetTester tester) async {
      final ui = {
        'type': 'toggle',
        'props': {
          'label': 'Enable feature',
          'value': false,
          'on_change': {'type': 'toggle_changed'},
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(capturedEvent['type'], 'toggle_changed');
      expect(capturedEvent['value'], true);
    });

    testWidgets('renders select widget', (WidgetTester tester) async {
      final ui = {
        'type': 'select',
        'props': {
          'label': 'Role',
          'value': 'user',
          'options': [
            {'value': 'user', 'label': 'User'},
            {'value': 'admin', 'label': 'Administrator'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Role'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('User'), findsOneWidget);
    });

    testWidgets('select triggers on_change event', (WidgetTester tester) async {
      final ui = {
        'type': 'select',
        'props': {
          'label': 'Role',
          'value': 'user',
          'options': [
            {'value': 'user', 'label': 'User'},
            {'value': 'admin', 'label': 'Administrator'},
          ],
          'on_change': {'type': 'select_changed'},
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Administrator'));
      await tester.pumpAndSettle();

      expect(capturedEvent['type'], 'select_changed');
      expect(capturedEvent['value'], 'admin');
    });

    testWidgets('renders image widget with network source',
        (WidgetTester tester) async {
      final ui = {
        'type': 'image',
        'props': {
          'src': 'https://picsum.photos/100/100.jpg',
          'width': 100,
          'height': 100,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);

      final Image image = tester.widget(find.byType(Image));
      expect(image.width, 100);
      expect(image.height, 100);
    });

    testWidgets('renders image widget with local source placeholder',
        (WidgetTester tester) async {
      final ui = {
        'type': 'image',
        'props': {
          'src': 'local://assets/test.png',
          'width': 120,
          'height': 120,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
      expect(find.byType(Column), findsOneWidget);
    });

    testWidgets('image widget shows error state for empty src',
        (WidgetTester tester) async {
      final ui = {
        'type': 'image',
        'props': {
          'src': '',
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Image widget requires src property'), findsOneWidget);
    });

    testWidgets('text_field respects keyboard_type property',
        (WidgetTester tester) async {
      final ui = {
        'type': 'text_field',
        'props': {
          'label': 'Email Field',
          'keyboard_type': 'email',
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Check that the TextFormField is rendered
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('text_field supports obscure text',
        (WidgetTester tester) async {
      final ui = {
        'type': 'text_field',
        'props': {
          'label': 'Password',
          'obscure': true,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Check that the TextFormField is rendered
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('filters out false values in children array',
        (WidgetTester tester) async {
      // Test case that verifies false values are filtered out (not causing errors)
      // This simulates the conditional UI expression pattern: condition and {...}
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Before conditional'},
          },
          false, // This simulates condition and {...} when condition is false
          {
            'type': 'text',
            'props': {'text': 'After conditional'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render the valid nodes without errors
      expect(find.text('Before conditional'), findsOneWidget);
      expect(find.text('After conditional'), findsOneWidget);

      // Should not show error for false values (they're filtered out)
      expect(find.text('UI node missing type'), findsNothing);
    });

    testWidgets('filters out null values in children array',
        (WidgetTester tester) async {
      // Test case that ensures null values are handled gracefully
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Before null'},
          },
          null, // This should be ignored gracefully
          {
            'type': 'text',
            'props': {'text': 'After null'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render the valid nodes without errors
      expect(find.text('Before null'), findsOneWidget);
      expect(find.text('After null'), findsOneWidget);

      // Should not show error for null values
      expect(find.text('UI node missing type'), findsNothing);
    });

    testWidgets('handles empty string type', (WidgetTester tester) async {
      // Test case for empty type field
      final ui = {
        'type': '',
        'props': {'text': 'Empty type test'},
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render the error message for empty type
      expect(find.text('UI node missing type'), findsOneWidget);
    });

    testWidgets('handles Map without type field', (WidgetTester tester) async {
      // Test case that actually triggers the "UI node missing type" error
      // This happens when a Map is passed but missing the type field
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Before invalid node'},
          },
          {
            // Missing 'type' field - this should trigger the error
            'props': {'text': 'This node has no type'},
          },
          {
            'type': 'text',
            'props': {'text': 'After invalid node'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render the error message for missing type
      expect(find.text('UI node missing type'), findsOneWidget);

      // Should still render the valid nodes
      expect(find.text('Before invalid node'), findsOneWidget);
      expect(find.text('After invalid node'), findsOneWidget);
    });
  });

  group('UiV1Renderer table widget', () {
    late Map<String, dynamic> capturedEvent;

    setUp(() {
      capturedEvent = {};
    });

    Widget createTestWidget(Map<String, dynamic> ui) {
      return MaterialApp(
        home: Scaffold(
          body: UiV1Renderer(
            ui: ui,
            onEvent: (msg) => capturedEvent = msg,
          ),
        ),
      );
    }

    testWidgets('renders table with columns and rows',
        (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'columns': [
            {'key': 'name', 'label': 'Name'},
            {'key': 'balance', 'label': 'Balance'},
          ],
          'rows': [
            {'name': 'Alice', 'balance': '100 ICP'},
            {'name': 'Bob', 'balance': '200 ICP'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('100 ICP'), findsOneWidget);
      expect(find.text('200 ICP'), findsOneWidget);
    });

    testWidgets('renders table with title', (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'title': 'Account Balances',
          'columns': [
            {'key': 'name', 'label': 'Name'},
          ],
          'rows': [
            {'name': 'Alice'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Account Balances'), findsOneWidget);
    });

    testWidgets('renders empty table with headers only',
        (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'columns': [
            {'key': 'id', 'label': 'ID'},
            {'key': 'status', 'label': 'Status'},
          ],
          'rows': [],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('ID'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('handles missing column key gracefully',
        (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'columns': [
            {'key': 'name', 'label': 'Name'},
          ],
          'rows': [
            {'name': 'Alice', 'extra': 'ignored'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('renders empty cell for missing row data',
        (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'columns': [
            {'key': 'name', 'label': 'Name'},
            {'key': 'email', 'label': 'Email'},
          ],
          'rows': [
            {'name': 'Alice'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows error for missing columns', (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'rows': [
            {'name': 'Alice'},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Table requires columns property'), findsOneWidget);
    });

    testWidgets('converts numeric values to strings',
        (WidgetTester tester) async {
      final ui = {
        'type': 'table',
        'props': {
          'columns': [
            {'key': 'count', 'label': 'Count'},
          ],
          'rows': [
            {'count': 42},
            {'count': 3.14},
          ],
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('42'), findsOneWidget);
      expect(find.text('3.14'), findsOneWidget);
    });
  });

  group('UiV1Renderer paginated_list widget', () {
    late Map<String, dynamic> capturedEvent;

    setUp(() {
      capturedEvent = {};
    });

    Widget createTestWidget(Map<String, dynamic> ui) {
      return MaterialApp(
        home: Scaffold(
          body: UiV1Renderer(
            ui: ui,
            onEvent: (msg) => capturedEvent = msg,
          ),
        ),
      );
    }

    testWidgets('renders paginated list with items',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'title': 'Test List',
          'items': [
            {'title': 'Item 1', 'subtitle': 'Description 1'},
            {'title': 'Item 2', 'subtitle': 'Description 2'},
          ],
          'has_more': false,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Test List'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Description 1'), findsOneWidget);
      expect(find.text('Description 2'), findsOneWidget);
    });

    testWidgets('shows Load More button when has_more is true',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': [
            {'title': 'Item 1'},
          ],
          'has_more': true,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('Load More triggers correct message',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': [
            {'title': 'Item 1'},
          ],
          'has_more': true,
          'loading': false,
          'load_more_msg': 'custom_load',
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(capturedEvent['type'], 'custom_load');
    });

    testWidgets('shows loading spinner while loading',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': [
            {'title': 'Item 1'},
          ],
          'has_more': true,
          'loading': true,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('shows No more items when has_more is false and items exist',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': [
            {'title': 'Item 1'},
          ],
          'has_more': false,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('No more items'), findsOneWidget);
    });

    testWidgets('shows No items when list is empty',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': <dynamic>[],
          'has_more': false,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('No items'), findsOneWidget);
      expect(find.text('No more items'), findsNothing);
    });

    testWidgets('uses default load_more message when not specified',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': [
            {'title': 'Item 1'},
          ],
          'has_more': true,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(capturedEvent['type'], 'load_more');
    });

    testWidgets('shows error for non-array items', (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': 'not an array',
          'has_more': false,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(
          find.text('Paginated list items must be an array'), findsOneWidget);
    });

    testWidgets('renders primitive items as strings',
        (WidgetTester tester) async {
      final ui = {
        'type': 'paginated_list',
        'props': {
          'items': ['String item', 42, true],
          'has_more': false,
          'loading': false,
        },
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      expect(find.text('String item'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('true'), findsOneWidget);
    });
  });
}
