import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/script_editor.dart';

void main() {
  testWidgets(
      'line numbers are hidden by default and toggle from overflow menu',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: false,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final codeFieldFinder = find.byType(CodeField);
    final CodeField initialField = tester.widget<CodeField>(codeFieldFinder);
    expect(initialField.gutterStyle.showLineNumbers, isFalse);

    final overflowButton = find.byKey(const Key('toolbarOverflowButton'));
    expect(overflowButton, findsOneWidget);

    await tester.tap(overflowButton);
    await tester.pumpAndSettle();

    final lineNumbersToggle = find.byKey(const Key('lineNumberToggle'));
    expect(lineNumbersToggle, findsOneWidget);

    final switchWidget = find.descendant(
      of: lineNumbersToggle,
      matching: find.byType(Switch),
    );
    expect(switchWidget, findsOneWidget);

    await tester.tap(switchWidget);
    await tester.pumpAndSettle();

    final CodeField updatedField = tester.widget<CodeField>(codeFieldFinder);
    expect(updatedField.gutterStyle.showLineNumbers, isTrue);
  });

  testWidgets('format code button is removed from toolbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: true,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final formatButton = find.byIcon(Icons.format_align_left_rounded);
    expect(formatButton, findsNothing);
  });

  testWidgets('theme selector is visible in toolbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: false,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final themeDropdown = find.byType(DropdownButton<String>);
    expect(themeDropdown, findsOneWidget);
  });

  testWidgets('stats are shown in overflow menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: false,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.textContaining('Lines:'), findsNothing);

    final overflowButton = find.byKey(const Key('toolbarOverflowButton'));
    await tester.tap(overflowButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Lines:'), findsOneWidget);
    expect(find.textContaining('Chars:'), findsOneWidget);
  });

  testWidgets('copy code action is in overflow menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: false,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final overflowButton = find.byKey(const Key('toolbarOverflowButton'));
    await tester.tap(overflowButton);
    await tester.pumpAndSettle();

    final copyButton = find.byKey(const Key('copyCodeButton'));
    expect(copyButton, findsOneWidget);
  });

  testWidgets(
      'UI components and snippets are in overflow menu when integrations enabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: true,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byKey(const Key('uiPaletteButton')), findsNothing);

    final overflowButton = find.byKey(const Key('toolbarOverflowButton'));
    await tester.tap(overflowButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('uiPaletteButton')), findsOneWidget);
    expect(find.byKey(const Key('snippetsButton')), findsOneWidget);
  });

  testWidgets('editor renders without a language badge (TS-only)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              minLines: 4,
              maxLines: 12,
              showIntegrations: false,
              onCodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // TS-only runtime: there is no language badge in the toolbar.
    expect(find.text('TS'), findsNothing);
  });
}
