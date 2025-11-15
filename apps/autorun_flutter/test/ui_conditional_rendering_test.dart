import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

void main() {
  group('UI Conditional Rendering Tests', () {
    late Map<String, dynamic> capturedEvent;

    setUp(() {
      capturedEvent = {};
    });

    tearDown(() {
      // Use capturedEvent to avoid unused variable warning
      expect(capturedEvent, isA<Map<String, dynamic>>());
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

    testWidgets('conditional UI with false condition is handled gracefully', (WidgetTester tester) async {
      // This test verifies that the pattern "condition and {...}" works correctly
      // when condition is false, without causing "UI node missing type" errors
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Always visible'},
          },
          // This simulates: false and {type: 'section', ...}
          // In Lua, this would evaluate to false and be inserted into the children array
          false,
          {
            'type': 'text',
            'props': {'text': 'Also always visible'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render the valid text nodes
      expect(find.text('Always visible'), findsOneWidget);
      expect(find.text('Also always visible'), findsOneWidget);
      
      // Should NOT show "UI node missing type" error
      expect(find.text('UI node missing type'), findsNothing);
    });

    testWidgets('conditional UI with true condition renders correctly', (WidgetTester tester) async {
      // This test verifies that when condition is true, the UI node renders
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Before conditional'},
          },
          // This simulates: true and {type: 'section', ...}
          // In a real scenario, this would be the actual UI node, not true
          {
            'type': 'section',
            'props': {'title': 'Conditional Section'},
            'children': [
              {
                'type': 'text',
                'props': {'text': 'Conditional content'},
              },
            ],
          },
          {
            'type': 'text',
            'props': {'text': 'After conditional'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should render all nodes
      expect(find.text('Before conditional'), findsOneWidget);
      expect(find.text('Conditional Section'), findsOneWidget);
      expect(find.text('Conditional content'), findsOneWidget);
      expect(find.text('After conditional'), findsOneWidget);
      
      // Should NOT show any errors
      expect(find.text('UI node missing type'), findsNothing);
    });

    testWidgets('demonstrates the original issue pattern', (WidgetTester tester) async {
      // This test demonstrates the pattern that caused the original issue
      // In Lua: state.show_info and {type: 'section', ...}
      // When state.show_info is false, this evaluates to false
      
      // Simulate the problematic case where false gets into the children array
      final problematicUi = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Header'},
          },
          false, // This is what "state.show_info and {...}" evaluates to when false
          {
            'type': 'text',
            'props': {'text': 'Footer'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(problematicUi));
      await tester.pumpAndSettle();

      // The renderer should handle this gracefully by filtering out false
      expect(find.text('Header'), findsOneWidget);
      expect(find.text('Footer'), findsOneWidget);
      expect(find.text('UI node missing type'), findsNothing);
    });

    testWidgets('shows error for actual missing type (not false values)', (WidgetTester tester) async {
      // This test shows what actually causes the "UI node missing type" error
      // It's not false values, but Map objects missing the type field
      final ui = {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Valid node'},
          },
          {
            // This is a Map but missing the 'type' field - this causes the error
            'props': {'text': 'Invalid node - no type'},
          },
        ],
      };

      await tester.pumpWidget(createTestWidget(ui));
      await tester.pumpAndSettle();

      // Should show the error for the missing type
      expect(find.text('UI node missing type'), findsOneWidget);
      expect(find.text('Valid node'), findsOneWidget);
    });
  });
}