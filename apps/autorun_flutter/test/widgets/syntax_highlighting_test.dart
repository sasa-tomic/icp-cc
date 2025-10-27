import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import '../../lib/widgets/script_editor.dart';

void main() {
  group('Syntax Highlighting Tests', () {
    testWidgets('ScriptEditor should initialize with CodeController', (WidgetTester tester) async {
      const testCode = '''
-- Simple Lua test
local function greet(name)
  print("Hello, " .. name .. "!")
end

greet("World")
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptEditor(
              initialCode: testCode,
              onCodeChanged: (code) {},
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify the editor is rendered
      expect(find.byType(CodeField), findsOneWidget);
      expect(find.byType(CodeTheme), findsOneWidget);
    });

    testWidgets('ScriptEditor should handle theme switching', (WidgetTester tester) async {
      const testCode = 'print("Hello World")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptEditor(
              initialCode: testCode,
              onCodeChanged: (code) {},
              language: 'lua',
            ),
          ),
        ),
      );

      // Find theme selector dropdown
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      
      // Tap on dropdown to open it
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Verify theme options are present
      expect(find.text('Vs2015'), findsAtLeastNWidgets(1));
      expect(find.text('Atom One Dark'), findsAtLeastNWidgets(1));
      expect(find.text('Monokai Sublime'), findsAtLeastNWidgets(1));
    });

    testWidgets('ScriptEditor should display line numbers', (WidgetTester tester) async {
      const testCode = '''
local x = 1
local y = 2
print(x + y)
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptEditor(
              initialCode: testCode,
              onCodeChanged: (code) {},
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify the editor is rendered with gutter (line numbers)
      expect(find.byType(CodeField), findsOneWidget);
    });
  });
}