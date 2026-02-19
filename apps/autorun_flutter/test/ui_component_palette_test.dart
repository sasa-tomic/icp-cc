import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/ui_component_palette.dart';
import 'package:icp_autorun/widgets/script_editor.dart';

void main() {
  group('UiComponentPalette', () {
    test('components list is not empty', () {
      expect(UiComponentPalette.components, isNotEmpty);
    });

    test('all components have valid Lua templates', () {
      for (final component in UiComponentPalette.components) {
        expect(component.luaTemplate, isNotEmpty);
        expect(component.luaTemplate, contains('type = '));
      }
    });

    test('all components have required fields', () {
      for (final component in UiComponentPalette.components) {
        expect(component.id, isNotEmpty);
        expect(component.name, isNotEmpty);
        expect(component.description, isNotEmpty);
        expect(component.icon, isNotNull);
      }
    });

    test('byCategory returns correct components', () {
      final layoutComponents =
          UiComponentPalette.byCategory(UiComponentCategory.layout);
      expect(layoutComponents, isNotEmpty);
      for (final c in layoutComponents) {
        expect(c.category, UiComponentCategory.layout);
      }
    });

    test('categoryLabel returns correct labels', () {
      expect(UiComponentPalette.categoryLabel(UiComponentCategory.layout),
          'Layout');
      expect(
          UiComponentPalette.categoryLabel(UiComponentCategory.text), 'Text');
      expect(
          UiComponentPalette.categoryLabel(UiComponentCategory.input), 'Input');
      expect(UiComponentPalette.categoryLabel(UiComponentCategory.display),
          'Display');
    });

    test('Lua templates contain valid table syntax', () {
      final templates =
          UiComponentPalette.components.map((c) => c.luaTemplate).toList();
      for (final template in templates) {
        expect(template, contains('{'));
        expect(template, contains('}'));
        expect(template, isNot(contains('null')));
      }
    });
  });

  group('UiComponentPaletteSheet', () {
    testWidgets('opens and displays categories', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await showUiComponentPalette(context: context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('UI Components'), findsOneWidget);
      expect(find.text('Layout'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Input'), findsOneWidget);
      expect(find.text('Display'), findsOneWidget);
    });

    testWidgets('clicking item returns template', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showUiComponentPalette(context: context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Column'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, contains('type = "column"'));
    });

    testWidgets('category filter works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await showUiComponentPalette(context: context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Column'), findsOneWidget);
      expect(find.text('Row'), findsOneWidget);

      await tester.tap(find.text('Input'));
      await tester.pumpAndSettle();

      expect(find.text('Text Field'), findsOneWidget);
      expect(find.text('Toggle'), findsOneWidget);
    });
  });

  group('ScriptEditor UI Palette Integration', () {
    testWidgets('UI palette button is visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                initialCode: 'print("hi")',
                language: 'lua',
                minLines: 4,
                showIntegrations: true,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('uiPaletteButton')), findsOneWidget);
    });

    testWidgets('UI palette button opens palette sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ScriptEditor(
                initialCode: 'print("hi")',
                language: 'lua',
                minLines: 4,
                showIntegrations: true,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('uiPaletteButton')));
      await tester.tap(find.byKey(const Key('uiPaletteButton')));
      await tester.pumpAndSettle();

      expect(find.text('UI Components'), findsOneWidget);
    });

    testWidgets('selecting component inserts template into editor',
        (tester) async {
      String code = 'print("hi")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ScriptEditor(
                initialCode: code,
                language: 'lua',
                minLines: 4,
                showIntegrations: true,
                onCodeChanged: (newCode) => code = newCode,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('uiPaletteButton')));
      await tester.tap(find.byKey(const Key('uiPaletteButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Column'));
      await tester.pumpAndSettle();

      expect(code, contains('type = "column"'));
    });

    testWidgets('UI palette button is hidden when showIntegrations is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                initialCode: 'print("hi")',
                language: 'lua',
                minLines: 4,
                showIntegrations: false,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('uiPaletteButton')), findsNothing);
    });
  });
}
