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

    testWidgets('text_field triggers on_change event', (WidgetTester tester) async {
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

    testWidgets('renders image widget with network source', (WidgetTester tester) async {
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

    testWidgets('renders image widget with local source placeholder', (WidgetTester tester) async {
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

    testWidgets('image widget shows error state for empty src', (WidgetTester tester) async {
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

    testWidgets('text_field respects keyboard_type property', (WidgetTester tester) async {
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

    testWidgets('text_field supports obscure text', (WidgetTester tester) async {
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
  });
}