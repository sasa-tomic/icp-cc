import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/script_editor.dart';

void main() {
  group('ScriptEditor dirty state tracking', () {
    testWidgets('isDirty is false initially', (tester) async {
      final editorKey = GlobalKey<ScriptEditorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                key: editorKey,
                initialCode: 'print("hello")',
                language: 'lua',
                minLines: 4,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(editorKey.currentState?.isDirty, isFalse);
    });

    testWidgets('isDirty becomes true when code changes', (tester) async {
      final editorKey = GlobalKey<ScriptEditorState>();
      String currentCode = 'print("hello")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                key: editorKey,
                initialCode: 'print("hello")',
                language: 'lua',
                minLines: 4,
                onCodeChanged: (code) {
                  currentCode = code;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Simulate code change via the state's method
      editorKey.currentState?.updateCode('print("world")');
      await tester.pump();

      expect(editorKey.currentState?.isDirty, isTrue);
    });

    testWidgets('isDirty becomes false when code matches initial again',
        (tester) async {
      final editorKey = GlobalKey<ScriptEditorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                key: editorKey,
                initialCode: 'print("hello")',
                language: 'lua',
                minLines: 4,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Change code
      editorKey.currentState?.updateCode('print("world")');
      await tester.pump();
      expect(editorKey.currentState?.isDirty, isTrue);

      // Revert code
      editorKey.currentState?.updateCode('print("hello")');
      await tester.pump();
      expect(editorKey.currentState?.isDirty, isFalse);
    });

    testWidgets('isDirty is false for identical initial code', (tester) async {
      final editorKey = GlobalKey<ScriptEditorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScriptEditor(
                key: editorKey,
                initialCode: 'print("hello")',
                language: 'lua',
                minLines: 4,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Set same code
      editorKey.currentState?.updateCode('print("hello")');
      await tester.pump();
      expect(editorKey.currentState?.isDirty, isFalse);
    });
  });

  group('UnsavedChangesDialog', () {
    testWidgets('shows discard and cancel buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnsavedChangesDialog(
              onDiscard: () {},
              onKeepEditing: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Unsaved Changes'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Discard button calls onDiscard callback', (tester) async {
      bool discardCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnsavedChangesDialog(
              onDiscard: () {
                discardCalled = true;
              },
              onKeepEditing: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.tap(find.text('Discard'));
      await tester.pump();

      expect(discardCalled, isTrue);
    });

    testWidgets('Cancel button calls onKeepEditing callback', (tester) async {
      bool keepEditingCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnsavedChangesDialog(
              onDiscard: () {},
              onKeepEditing: () {
                keepEditingCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(keepEditingCalled, isTrue);
    });
  });

  group('showUnsavedChangesDialog helper', () {
    testWidgets('returns true when Discard is tapped', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showUnsavedChangesDialog(context);
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false when Cancel is tapped', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showUnsavedChangesDialog(context);
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('returns false when dialog is dismissed by tapping outside',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showUnsavedChangesDialog(context);
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsOneWidget);

      // Tap outside the dialog to dismiss it
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
