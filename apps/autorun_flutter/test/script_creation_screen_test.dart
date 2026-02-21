import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/script_template.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';

import 'script_creation_screen_test.mocks.dart';

const _testLuaCode = '''-- Test Script
function init(arg)
  return { counter = 0 }, {}
end

function view(state)
  return {
    type = "section",
    props = { title = "Test" },
    children = {
      {
        type = "text",
        props = { text = "Counter: " .. state.counter }
      }
    }
  }
end

function update(msg, state)
  if msg.type == "increment" then
    state.counter = state.counter + 1
  end
  return state, {}
end
''';

@GenerateMocks([ScriptController, ScriptRecord])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();
  });

  group('ScriptCreationScreen - Single Page Layout', () {
    late MockScriptController mockController;
    late ScriptTemplate testTemplate;

    setUp(() {
      mockController = MockScriptController();
      testTemplate = ScriptTemplate(
        id: 'test_template',
        title: 'Test Template',
        description: 'A test template for unit testing',
        emoji: '🧪',
        level: 'beginner',
        tags: ['test', 'unit'],
        preloadedLuaSource: _testLuaCode,
      );
    });

    testWidgets('should NOT have tabs - single scrollable page',
        (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
      expect(find.text('CODE EDITOR'), findsNothing);
      expect(find.text('DETAILS'), findsNothing);
    });

    testWidgets('all fields visible without switching tabs',
        (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
            initialTemplate: testTemplate,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Title *'), findsOneWidget);
      expect(find.text('Emoji'), findsOneWidget);
      expect(find.text('Image URL'), findsOneWidget);
      expect(find.text('Choose a Template'), findsOneWidget);
    });

    testWidgets('has sticky Create Script button at bottom',
        (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Create Script'), findsOneWidget);
    });

    testWidgets('template selection updates code', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Hello World template should be visible in the template cards
      expect(find.text('Hello World'), findsWidgets);
    });

    testWidgets('create button validates empty title',
        (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        '',
      );

      await tester.tap(find.text('Create Script'));
      await tester.pump();

      expect(find.text('Title is required'), findsOneWidget);
      verifyNever(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      ));
    });

    testWidgets('create script successfully', (WidgetTester tester) async {
      final mockRecord = MockScriptRecord();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => mockRecord);

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
            initialTemplate: testTemplate,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Script'));
      await tester.pump();

      verify(mockController.createScript(
        title: testTemplate.title,
        emoji: testTemplate.emoji,
        imageUrl: null,
        luaSourceOverride: testTemplate.luaSource,
      )).called(1);
    });

    testWidgets('shows loading state during creation',
        (WidgetTester tester) async {
      final completer = Completer<ScriptRecord>();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
            initialTemplate: testTemplate,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Script'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Create Script'), findsNothing);

      completer.complete(MockScriptRecord());
      await tester.pumpAndSettle();
    });

    testWidgets('handles creation error', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenThrow(Exception('Creation failed'));

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
            initialTemplate: testTemplate,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Script'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to create script: Exception: Creation failed'),
          findsOneWidget);
    });

    testWidgets('screen closes on successful creation',
        (WidgetTester tester) async {
      final mockRecord = MockScriptRecord();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => mockRecord);

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
            initialTemplate: testTemplate,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Script'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptCreationScreen), findsNothing);
    });

    testWidgets('shows template cards prominently',
        (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Template cards should be visible (using keys with template_card_ prefix)
      expect(
          find.byKey(const Key('template_card_hello_world')), findsOneWidget);
      expect(find.byKey(const Key('template_card_blank')), findsOneWidget);
    });
  });
}
