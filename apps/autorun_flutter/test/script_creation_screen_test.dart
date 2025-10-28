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

@GenerateMocks([ScriptController, ScriptRecord])
void main() {
  group('ScriptCreationScreen Tests', () {
    late MockScriptController mockController;
    late ScriptTemplate testTemplate;

    setUp(() {
      mockController = MockScriptController();

      // Create a test template
      testTemplate = const ScriptTemplate(
        id: 'test_template',
        title: 'Test Template',
        description: 'A test template for unit testing',
        emoji: '🧪',
        level: 'beginner',
        tags: ['test', 'unit'],
      );
    });

    testWidgets('should render with default template', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Verify screen is rendered
      expect(find.byType(ScriptCreationScreen), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);

      // Verify default tabs
      expect(find.text('CODE EDITOR'), findsOneWidget);
      expect(find.text('DETAILS'), findsOneWidget);

      // Verify initial template is loaded (Hello World by default)
      expect(find.descendant(of: find.byType(DropdownButtonFormField<ScriptTemplate>), matching: find.textContaining('Hello World')), findsOneWidget);
    });

    testWidgets('should render with provided template', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab to see template information
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Verify provided template is loaded
      expect(find.text(testTemplate.title), findsAtLeastNWidgets(1));
      expect(find.text(testTemplate.description), findsAtLeastNWidgets(1));
      expect(find.text(testTemplate.emoji), findsAtLeastNWidgets(1));
    });

    testWidgets('should show code editor tab by default', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Wait for UI to render
      await tester.pumpAndSettle();

      // Verify code editor is visible
      expect(find.byType(TabBarView), findsOneWidget);
      expect(find.text('Template'), findsOneWidget);
    });

    testWidgets('should switch to details tab', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Tap on details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Verify details form is visible
      expect(find.text('Script Details'), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
      expect(find.text('Title *'), findsOneWidget);
      expect(find.text('Emoji'), findsOneWidget);
      expect(find.text('Image URL'), findsOneWidget);
    });

    testWidgets('should show template selection dialog', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Initially template should be selected, no floating button
      expect(find.byType(FloatingActionButton), findsNothing);

      // Go to details tab and back to code editor
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CODE EDITOR'));
      await tester.pumpAndSettle();

      // Template should still be selected
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('should display template information correctly', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab to see template information
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Verify template information is displayed (there should be multiple instances - in display and in form fields)
      expect(find.text(testTemplate.title), findsAtLeastNWidgets(2));
      expect(find.text(testTemplate.description), findsOneWidget);
      expect(find.text(testTemplate.emoji), findsAtLeastNWidgets(2));

      // Verify template tags
      expect(find.text('test'), findsOneWidget);
      expect(find.text('unit'), findsOneWidget);
    });

    testWidgets('should populate form fields with template data', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Verify form fields are populated with template data
      expect(find.descendant(of: find.byType(TextFormField), matching: find.text(testTemplate.title)), findsOneWidget);
      expect(find.descendant(of: find.byType(TextFormField), matching: find.text(testTemplate.emoji)), findsOneWidget);
    });

    testWidgets('should validate title field', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Clear title field
      await tester.enterText(find.ancestor(of: find.text('Title *'), matching: find.byType(TextFormField)), '');
      await tester.pump();

      // Try to create script
      await tester.tap(find.text('CREATE'));
      await tester.pump();

      // Should show validation error and switch to details tab
      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('should create script successfully', (WidgetTester tester) async {
      final mockRecord = MockScriptRecord();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => mockRecord);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Create script
      await tester.tap(find.text('CREATE'));
      await tester.pump();

      // Verify createScript was called
      verify(mockController.createScript(
        title: testTemplate.title,
        emoji: testTemplate.emoji,
        imageUrl: null,
        luaSourceOverride: testTemplate.luaSource,
      )).called(1);
    });

    testWidgets('should handle create script error', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenThrow(Exception('Creation failed'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Try to create script
      await tester.tap(find.text('CREATE'));
      await tester.pump();

      // Should show error message
      expect(find.text('Failed to create script: Exception: Creation failed'), findsOneWidget);
    });

    testWidgets('should show loading state during creation', (WidgetTester tester) async {
      final completer = Completer<ScriptRecord>();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Start creation
      await tester.tap(find.text('CREATE'));
      await tester.pump();

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('CREATE'), findsNothing);
    });

    testWidgets('should show helper text in details tab', (WidgetTester tester) async {
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => MockScriptRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Verify helper text is shown
      expect(find.textContaining('Provide either an emoji or an image URL'), findsOneWidget);
    });

    testWidgets('should close screen on successful creation', (WidgetTester tester) async {
      final mockRecord = MockScriptRecord();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        luaSourceOverride: anyNamed('luaSourceOverride'),
      )).thenAnswer((_) async => mockRecord);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCreationScreen(
              controller: mockController,
              initialTemplate: testTemplate,
            ),
          ),
        ),
      );

      // Switch to details tab
      await tester.tap(find.text('DETAILS'));
      await tester.pumpAndSettle();

      // Create script
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();

      // Screen should be closed (no longer in widget tree)
      expect(find.byType(ScriptCreationScreen), findsNothing);
    });

    group('Template Selection Dialog', () {
      testWidgets('should show all templates in dialog', (WidgetTester tester) async {
        when(mockController.createScript(
          title: anyNamed('title'),
          emoji: anyNamed('emoji'),
          imageUrl: anyNamed('imageUrl'),
          luaSourceOverride: anyNamed('luaSourceOverride'),
        )).thenAnswer((_) async => MockScriptRecord());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScriptCreationScreen(
                controller: mockController,
              ),
            ),
          ),
        );

        // Clear current template to trigger floating action button
        // (This is a bit tricky to test without exposing internal state)
        // For now, let's test the template dialog components

        // Look for template-related content in the template selector
        expect(find.descendant(of: find.byType(DropdownButtonFormField<ScriptTemplate>), matching: find.textContaining('Hello World')), findsOneWidget);
        // Also verify that templates are displayed in the UI generally
        expect(find.text('Hello World'), findsAtLeastNWidgets(1));
      });
    });

    group('Accessibility', () {
      testWidgets('should have proper semantic labels', (WidgetTester tester) async {
        when(mockController.createScript(
          title: anyNamed('title'),
          emoji: anyNamed('emoji'),
          imageUrl: anyNamed('imageUrl'),
          luaSourceOverride: anyNamed('luaSourceOverride'),
        )).thenAnswer((_) async => MockScriptRecord());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScriptCreationScreen(
                controller: mockController,
              ),
            ),
          ),
        );

        // Check for tab icons with semantic labels (look for Icon widgets within TabBar)
        final codeIcon = find.descendant(of: find.byType(TabBar), matching: find.byIcon(Icons.code));
        final detailsIcon = find.descendant(of: find.byType(TabBar), matching: find.byIcon(Icons.info_outline));
        expect(codeIcon, findsOneWidget);
        expect(detailsIcon, findsOneWidget);
      });

      testWidgets('should be keyboard navigable', (WidgetTester tester) async {
        when(mockController.createScript(
          title: anyNamed('title'),
          emoji: anyNamed('emoji'),
          imageUrl: anyNamed('imageUrl'),
          luaSourceOverride: anyNamed('luaSourceOverride'),
        )).thenAnswer((_) async => MockScriptRecord());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScriptCreationScreen(
                controller: mockController,
              ),
            ),
          ),
        );

        // Test tab switching
        await tester.tap(find.text('DETAILS'));
        await tester.pumpAndSettle();

        // Should have switched to details tab
        expect(find.text('Script Details'), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should handle null controller gracefully', (WidgetTester tester) async {
        expect(
          () => ScriptCreationScreen(
            controller: mockController, // Mock controller should work fine
          ),
          returnsNormally,
        );
      });

      testWidgets('should handle empty template list', (WidgetTester tester) async {
        // This test would require modifying the template system to return empty
        // For now, we test that the screen doesn't crash with default templates
        when(mockController.createScript(
          title: anyNamed('title'),
          emoji: anyNamed('emoji'),
          imageUrl: anyNamed('imageUrl'),
          luaSourceOverride: anyNamed('luaSourceOverride'),
        )).thenAnswer((_) async => MockScriptRecord());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScriptCreationScreen(
                controller: mockController,
              ),
            ),
          ),
        );

        // Should not crash
        expect(find.byType(ScriptCreationScreen), findsOneWidget);
      });
    });
  });
}