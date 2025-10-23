import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

void main() {
  group('UI Renderer Enhanced Features Tests', () {
    late Map<String, dynamic> mockEvent;

    setUp(() {
      mockEvent = {};
    });

    void handleEvent(Map<String, dynamic> event) {
      mockEvent = event;
    }

    testWidgets('renders enhanced list with search capability', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [
            {'title': 'Item 1', 'subtitle': 'Description 1'},
            {'title': 'Item 2', 'subtitle': 'Description 2'},
          ],
          'title': 'Enhanced Results',
          'searchable': true,
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Enhanced Results'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Search results...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });

    testWidgets('renders enhanced list without search when disabled', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [
            {'title': 'Item 1'},
          ],
          'title': 'No Search',
          'searchable': false,
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('No Search'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.text('Item 1'), findsOneWidget);
    });

    testWidgets('renders enhanced list with empty items', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [],
          'title': 'Empty Enhanced List',
          'searchable': true,
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Empty Enhanced List'), findsOneWidget);
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('renders enhanced list with default title when not specified', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [
            {'title': 'Test Item'},
          ],
          'searchable': true,
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Test Item'), findsOneWidget);
    });

    testWidgets('renders result display widget', (WidgetTester tester) async {
      final ui = {
        'type': 'result_display',
        'props': {
          'data': {
            'name': 'John Doe',
            'age': 30,
            'active': true,
          },
          'title': 'User Data',
          'expandable': true,
          'expanded': false,
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
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

    testWidgets('renders result display with error', (WidgetTester tester) async {
      final ui = {
        'type': 'result_display',
        'props': {
          'error': 'Something went wrong',
          'title': 'Error Display',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Error Display'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders result display without title', (WidgetTester tester) async {
      final ui = {
        'type': 'result_display',
        'props': {
          'data': 'Simple text result',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Simple text result'), findsOneWidget);
    });

    testWidgets('renders result display with default expandable settings', (WidgetTester tester) async {
      final ui = {
        'type': 'result_display',
        'props': {
          'data': {'key': 'value'},
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('key:'), findsOneWidget);
      expect(find.text('value'), findsOneWidget);
    });

    testWidgets('renders regular list when enhanced is false', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': false,
          'items': [
            {'title': 'Regular Item 1', 'subtitle': 'Subtitle 1', 'copy': true},
            {'title': 'Regular Item 2'},
          ],
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Regular Item 1'), findsOneWidget);
      expect(find.text('Subtitle 1'), findsOneWidget);
      expect(find.text('Regular Item 2'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // No search in regular mode
    });

    testWidgets('renders regular list without enhanced property', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'items': [
            {'title': 'Default Item'},
          ],
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Default Item'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // Should be regular list
    });

    testWidgets('handles malformed list items gracefully', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [
            'String item',
            123, // Number item
            null, // Null item
            {'title': 'Valid item'},
          ],
          'title': 'Mixed Items',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      // Should render valid items and handle invalid ones gracefully
      expect(find.text('String item'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
      expect(find.text('Valid item'), findsOneWidget);
    });

    testWidgets('passes onEvent callback correctly', (WidgetTester tester) async {
      final ui = {
        'type': 'list',
        'props': {
          'enhanced': true,
          'items': [
            {'title': 'Clickable Item', 'subtitle': 'Click me'},
          ],
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      // Open menu for the item
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Tap copy button
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // The event should have been captured
      expect(mockEvent, isNotEmpty);
    });

    testWidgets('handles complex nested data structures', (WidgetTester tester) async {
      final complexData = {
        'user': {
          'name': 'John',
          'preferences': {
            'theme': 'dark',
            'notifications': true,
          }
        },
        'metadata': {
          'version': '1.0.0',
          'lastUpdated': 1640995200000000000, // nanosecond timestamp
        }
      };

      final ui = {
        'type': 'result_display',
        'props': {
          'data': complexData,
          'title': 'Complex Data',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Complex Data'), findsOneWidget);
      expect(find.text('user:'), findsOneWidget);
      expect(find.text('metadata:'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsWidgets); // For nested objects
    });

    testWidgets('handles arrays in result display', (WidgetTester tester) async {
      final arrayData = ['first', 'second', 'third'];

      final ui = {
        'type': 'result_display',
        'props': {
          'data': arrayData,
          'title': 'Array Data',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Array Data'), findsOneWidget);
      expect(find.text('[0]:'), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('[1]:'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('[2]:'), findsOneWidget);
      expect(find.text('third'), findsOneWidget);
    });

    testWidgets('renders section with result display content', (WidgetTester tester) async {
      final ui = {
        'type': 'section',
        'props': {
          'title': 'Data Section',
        },
        'children': [
          {
            'type': 'result_display',
            'props': {
              'data': 'Section content',
              'title': 'Section Result',
            }
          }
        ]
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Data Section'), findsOneWidget);
      expect(find.text('Section Result'), findsOneWidget);
      expect(find.text('Section content'), findsOneWidget);
    });

    testWidgets('handles boolean and null values in result display', (WidgetTester tester) async {
      final mixedData = {
        'booleanTrue': true,
        'booleanFalse': false,
        'nullValue': null,
        'stringValue': 'text',
        'numberValue': 42,
      };

      final ui = {
        'type': 'result_display',
        'props': {
          'data': mixedData,
          'title': 'Mixed Types',
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiV1Renderer(
              ui: ui,
              onEvent: handleEvent,
            ),
          ),
        ),
      );

      expect(find.text('Mixed Types'), findsOneWidget);
      expect(find.text('booleanTrue:'), findsOneWidget);
      expect(find.text('true'), findsOneWidget);
      expect(find.text('booleanFalse:'), findsOneWidget);
      expect(find.text('false'), findsOneWidget);
      expect(find.text('nullValue:'), findsOneWidget);
      expect(find.text('null'), findsOneWidget);
      expect(find.text('stringValue:'), findsOneWidget);
      expect(find.text('text'), findsOneWidget);
      expect(find.text('numberValue:'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });
  });
}