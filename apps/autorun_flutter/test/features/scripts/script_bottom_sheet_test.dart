import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';

import '_scripts_test_harness.dart';

const _validBundle = '''
function init(arg)
  return { message = "Hello World" }, {}
end
function view(state)
  return { type = "message", content = state.message }
end
''';

/// Tests for bottom sheet script execution (item #32): running a script shows
/// its output in a bottom sheet with an "Expand to full screen" option, instead
/// of navigating away and losing context.
void main() {
  /// Pumps a [Scaffold] whose body is a single button that opens the execution
  /// sheet — a stable harness for driving [showScriptExecutionBottomSheet].
  Future<void> pumpSheet(WidgetTester tester, ScriptRecord script) async {
    await pumpInScaffold(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showScriptExecutionBottomSheet(context: context, script: script),
          child: const Text('Show'),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  group('ScriptExecutionBottomSheet widget', () {
    testWidgets('shows script title in header', (tester) async {
      await pumpSheet(tester, _script(id: 'test-1', title: 'Test Script'));

      expect(find.text('Test Script'), findsOneWidget,
          reason: 'Bottom sheet header should show script title');
    });

    testWidgets('contains ScriptAppHost for script execution', (tester) async {
      await pumpSheet(tester, _script(id: 'test-2', title: 'Script with Host'));

      expect(find.byType(ScriptAppHost), findsOneWidget,
          reason: 'Bottom sheet should contain ScriptAppHost');
    });

    testWidgets('has expand to full screen button', (tester) async {
      await pumpSheet(tester, _script(id: 'test-3', title: 'Expandable Script'));

      expect(find.byIcon(Icons.open_in_full), findsOneWidget,
          reason: 'Bottom sheet should have expand button');
    });

    testWidgets('has close button', (tester) async {
      await pumpSheet(tester, _script(id: 'test-4', title: 'Closable Script'));

      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'Bottom sheet should have close button');
    });

    testWidgets('can be dismissed by tapping close button', (tester) async {
      await pumpSheet(tester, _script(id: 'test-5', title: 'Dismissible Script'));

      expect(find.byType(ScriptExecutionBottomSheet), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptExecutionBottomSheet), findsNothing,
          reason: 'Bottom sheet should close after tapping close button');
    });

    testWidgets('output is scrollable via SingleChildScrollView', (tester) async {
      await pumpSheet(tester, _script(id: 'test-6', title: 'Scrollable Script'));

      expect(find.byType(SingleChildScrollView), findsWidgets,
          reason: 'Script output should be scrollable');
    });
  });

  group('Script execution bottom sheet integration', () {
    testWidgets('shows loading indicator during script initialization',
        (tester) async {
      await pumpInScaffold(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showScriptExecutionBottomSheet(context: context, script: _script(id: 'test-7', title: 'Loading Script')),
            child: const Text('Show'),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'Should show loading indicator during script init');
    });
  });
}

ScriptRecord _script({required String id, required String title}) {
  return ScriptRecord(
    id: id,
    title: title,
    emoji: '📜',
    bundle: _validBundle,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    metadata: {},
  );
}
