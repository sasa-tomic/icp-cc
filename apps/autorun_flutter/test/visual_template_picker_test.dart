import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/script_template.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';

import 'visual_template_picker_test.mocks.dart';

@GenerateMocks([ScriptController, ScriptRecord])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();
  });

  group('Visual Template Picker - PoC', () {
    late MockScriptController mockController;

    setUp(() {
      mockController = MockScriptController();
      when(mockController.createScript(
        title: anyNamed('title'),
        emoji: anyNamed('emoji'),
        imageUrl: anyNamed('imageUrl'),
        bundleOverride: anyNamed('bundleOverride'),
      )).thenAnswer((_) async => MockScriptRecord());
    });

    testWidgets('shows template cards NOT dropdown',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should NOT have a dropdown - the old UI pattern
      expect(
        find.byType(DropdownButtonFormField<ScriptTemplate>),
        findsNothing,
        reason: 'Templates should be shown as visual cards, not a dropdown',
      );
    });

    testWidgets(
        'shows template cards with emoji, title, description, difficulty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the Hello World template content somewhere on screen
      expect(find.text('👋'), findsWidgets);
      expect(find.text('Hello World'), findsWidgets);
      expect(find.textContaining('Simple introduction'), findsWidgets);
      expect(find.text('Beginner'), findsWidgets);
    });

    testWidgets('each template card shows emoji icon prominently',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Template emojis should be visible - they're key identifiers
      expect(find.text('👋'), findsWidgets); // Hello World
      expect(find.text('🌐'), findsWidgets); // Canister Query Demo
      expect(find.text('🎨'), findsWidgets); // Forms & UI Demo
      expect(find.text('🟦'), findsWidgets); // TypeScript Counter
    });

    testWidgets('difficulty badges show correct levels',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show difficulty badges with full text
      expect(find.text('Beginner'), findsWidgets);
      expect(find.text('Intermediate'), findsWidgets);
      expect(find.text('Advanced'), findsWidgets);
    });

    testWidgets('Blank Script is available as a template option',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Blank Script should be visible as a template card
      expect(find.text('Blank Script'), findsOneWidget);
    });

    testWidgets('template card selection populates code editor',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on the Hello World template card
      final helloWorldCard = find.ancestor(
        of: find.text('Hello World'),
        matching: find.byType(GestureDetector),
      );

      await tester.tap(helloWorldCard.first);
      await tester.pumpAndSettle();

      // Verify the title field is populated
      final titleField = find.widgetWithText(TextFormField, 'Title *');
      expect(titleField, findsOneWidget);

      // The title should now be 'Hello World'
      final textFieldWidget = tester.widget<TextFormField>(titleField);
      expect(textFieldWidget.controller?.text, 'Hello World');
    });

    testWidgets('selected template card is highlighted',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the template cards - they have unique keys based on template id
      expect(
          find.byKey(const Key('template_card_hello_world')), findsOneWidget);

      // One card should be selected (shown by the selected indicator)
      expect(find.byKey(const Key('template_card_selected')), findsOneWidget);
    });

    testWidgets('template section is collapsible after selection',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show a collapse/expand button for template section
      expect(find.byIcon(Icons.expand_less), findsWidgets);
    });

    testWidgets('tapping different template updates code editor',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptCreationScreen(
            controller: mockController,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // First, tap on the Canister Query Demo template
      final icpDemoCard = find.ancestor(
        of: find.text('Canister Query Demo'),
        matching: find.byType(GestureDetector),
      );

      await tester.tap(icpDemoCard);
      await tester.pumpAndSettle();

      // Title should update
      final titleField = find.widgetWithText(TextFormField, 'Title *');
      final textFieldWidget = tester.widget<TextFormField>(titleField);
      expect(textFieldWidget.controller?.text, 'Canister Query Demo');
    });
  });
}
