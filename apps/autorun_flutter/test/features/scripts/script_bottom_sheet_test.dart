import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';

const _validLuaScript = '''
function init(arg)
  return { message = "Hello World" }, {}
end
function view(state)
  return { type = "message", content = state.message }
end
''';

/// Tests for bottom sheet script execution (item #32)
///
/// Problem: Running a script navigates to full screen, losing context.
/// Solution: Show script output in bottom sheet with "Expand to full screen" option.
void main() {
  group('ScriptExecutionBottomSheet widget', () {
    testWidgets('shows script title in header', (tester) async {
      final script = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        emoji: '📜',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Test Script'), findsOneWidget,
          reason: 'Bottom sheet header should show script title');
    });

    testWidgets('contains ScriptAppHost for script execution', (tester) async {
      final script = ScriptRecord(
        id: 'test-2',
        title: 'Script with Host',
        emoji: '🧪',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptAppHost), findsOneWidget,
          reason: 'Bottom sheet should contain ScriptAppHost');
    });

    testWidgets('has expand to full screen button', (tester) async {
      final script = ScriptRecord(
        id: 'test-3',
        title: 'Expandable Script',
        emoji: '↗️',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.open_in_full), findsOneWidget,
          reason: 'Bottom sheet should have expand button');
    });

    testWidgets('has close button', (tester) async {
      final script = ScriptRecord(
        id: 'test-4',
        title: 'Closable Script',
        emoji: '❌',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'Bottom sheet should have close button');
    });

    testWidgets('can be dismissed by tapping close button', (tester) async {
      final script = ScriptRecord(
        id: 'test-5',
        title: 'Dismissible Script',
        emoji: '👇',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptExecutionBottomSheet), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptExecutionBottomSheet), findsNothing,
          reason: 'Bottom sheet should close after tapping close button');
    });

    testWidgets('output is scrollable via SingleChildScrollView',
        (tester) async {
      final script = ScriptRecord(
        id: 'test-6',
        title: 'Scrollable Script',
        emoji: '📜',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets,
          reason: 'Script output should be scrollable');
    });
  });

  group('Script execution bottom sheet integration', () {
    testWidgets('shows loading indicator during script initialization',
        (tester) async {
      final script = ScriptRecord(
        id: 'test-7',
        title: 'Loading Script',
        emoji: '⏳',
        luaSource: _validLuaScript,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScriptExecutionBottomSheet(
                context: context,
                script: script,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'Should show loading indicator during script init');
    });
  });
}
