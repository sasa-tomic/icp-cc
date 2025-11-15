import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/script_editor.dart';

void main() {
  testWidgets('line numbers are hidden by default and toggle on demand', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditor(
              initialCode: 'print("hi")',
              language: 'lua',
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

    final switchFinder = find.byKey(const Key('lineNumberSwitch'));
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder, warnIfMissed: false);
    await tester.pump();

    final CodeField updatedField = tester.widget<CodeField>(codeFieldFinder);
    expect(updatedField.gutterStyle.showLineNumbers, isTrue);
  });
}
