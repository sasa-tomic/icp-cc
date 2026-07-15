import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/screens/script_editor_dialog.dart';
import 'package:icp_autorun/widgets/script_editor.dart';

import '../../shared/mock_script_repository.dart';

/// W7-18: `ScriptEditorDialog` (the dialog BOUNDARY around `ScriptEditor`) had
/// no tests — the sibling `test/widgets/script_editor_unsaved_test.dart` and
/// `test/script_editor_test.dart` exercise the inline editor widget only, not
/// this dialog's open/save/cancel/error wiring.
///
/// These tests pin the dialog's I/O boundary (the `ScriptController.updateSource`
/// call) using a REAL `ScriptController` over the in-memory
/// `MockScriptRepository` — no crypto, no network; the controller is the seam.
/// Edits are driven through the real text-input path (`enterText`). Because
/// `flutter_code_editor`'s `CodeController` transforms raw input (modifier /
/// read-only-section logic), the save assertion compares against the editor's
/// OWN current content (`CodeField.controller.fullText`) rather than the typed
/// literal — proving Save persists exactly what the editor holds.
void main() {
  late ScriptController controller;
  late MockScriptRepository repository;

  setUp(() {
    repository = MockScriptRepository();
    controller = ScriptController(repository);
  });

  tearDown(() => controller.dispose());

  /// Opens [dialog] via the production `showDialog` entry point.
  Future<void> pumpDialog(WidgetTester tester, ScriptEditorDialog dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => dialog,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  /// The single [CodeField]'s current full text — the editor's source of truth.
  String editorFullText(WidgetTester tester) =>
      tester
          .widget<CodeField>(find.byType(CodeField))
          .controller
          .fullText;

  group('ScriptEditorDialog open state', () {
    testWidgets('renders the record title and loads its source into the editor',
        (tester) async {
      final record = await controller.createScript(
        title: 'My Script',
        bundleOverride: 'const original = 1;',
      );

      await pumpDialog(
          tester, ScriptEditorDialog(controller: controller, record: record));

      // Header mirrors the record's title.
      expect(find.text('My Script'), findsOneWidget);
      // The editor received the record's bundle verbatim.
      expect(find.byType(ScriptEditor), findsOneWidget);
      expect(
        tester.widget<ScriptEditor>(find.byType(ScriptEditor)).initialCode,
        'const original = 1;',
      );
      expect(editorFullText(tester), 'const original = 1;');
      // No edits yet → not dirty.
      expect(_editorState(tester).isDirty, isFalse);
    });
  });

  group('ScriptEditorDialog save', () {
    testWidgets(
        'editing + Save persists the editor content via the controller, pops '
        'the dialog, and shows the success snackbar', (tester) async {
      const original = 'const original = 1;';
      final record = await controller.createScript(
        title: 'Editable',
        bundleOverride: original,
      );

      await pumpDialog(
          tester, ScriptEditorDialog(controller: controller, record: record));

      // Drive a real edit through the text-input path.
      await tester.enterText(find.byType(EditableText), 'const edited = 2;');
      await tester.pump();
      final expectedSaved = editorFullText(tester);
      expect(expectedSaved, isNot(equals(original)),
          reason: 'the edit must have changed the editor content');
      expect(_editorState(tester).isDirty, isTrue);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The controller (the I/O boundary) received exactly the editor content.
      expect(controller.scripts.single.bundle, expectedSaved);
      // The dialog dismissed itself.
      expect(find.byType(ScriptEditorDialog), findsNothing);
      // The user-visible confirmation appeared.
      expect(find.text('Script saved successfully!'), findsOneWidget);
    });

    testWidgets('Save failure surfaces an error and keeps the dialog open',
        (tester) async {
      // A record whose id is NOT in the controller → updateSource throws
      // ArgumentError('Script not found'). This exercises the dialog's catch
      // branch at the I/O boundary without fabricating a fake controller.
      final orphanedRecord = ScriptRecord(
        id: 'not-in-controller',
        title: 'Orphan',
        bundle: 'const x = 0;',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );
      expect(controller.scripts, isEmpty);

      await pumpDialog(tester,
          ScriptEditorDialog(controller: controller, record: orphanedRecord));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The error surfaced to the user (not swallowed).
      expect(find.textContaining('Save failed'), findsOneWidget);
      // The dialog stayed open so the user can retry / fix.
      expect(find.byType(ScriptEditorDialog), findsOneWidget);
      // Nothing was persisted.
      expect(controller.scripts, isEmpty);
    });
  });

  group('ScriptEditorDialog cancel', () {
    testWidgets('Cancel with no changes pops immediately without saving',
        (tester) async {
      const original = 'const original = 1;';
      final record = await controller.createScript(
        title: 'Untouched',
        bundleOverride: original,
      );

      await pumpDialog(
          tester, ScriptEditorDialog(controller: controller, record: record));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptEditorDialog), findsNothing);
      // Nothing was persisted — the bundle is unchanged.
      expect(controller.scripts.single.bundle, original);
    });

    testWidgets(
        'Cancel with unsaved edits shows the discard-confirm, and Discard '
        'then closes without saving', (tester) async {
      const original = 'const original = 1;';
      final record = await controller.createScript(
        title: 'Dirty',
        bundleOverride: original,
      );

      await pumpDialog(
          tester, ScriptEditorDialog(controller: controller, record: record));

      // Make the editor dirty via a real edit.
      await tester.enterText(find.byType(EditableText), 'const unsaved = 2;');
      await tester.pump();
      expect(_editorState(tester).isDirty, isTrue);

      // Cancel must intercept with the unsaved-changes guard.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsOneWidget);

      // Discard → the dialog closes; the edit is NOT persisted.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptEditorDialog), findsNothing);
      expect(controller.scripts.single.bundle, original);
    });

    testWidgets(
        'Cancel with unsaved edits then "Cancel" on the guard keeps the '
        'dialog open (keep editing)', (tester) async {
      const original = 'const original = 1;';
      final record = await controller.createScript(
        title: 'Keep Editing',
        bundleOverride: original,
      );

      await pumpDialog(
          tester, ScriptEditorDialog(controller: controller, record: record));

      await tester.enterText(find.byType(EditableText), 'const unsaved = 3;');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Guard is showing; its Cancel returns false → editor dialog stays.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsNothing);
      expect(find.byType(ScriptEditorDialog), findsOneWidget,
          reason: 'choosing "keep editing" must not discard the editor');
    });
  });
}

ScriptEditorState _editorState(WidgetTester tester) =>
    tester.state<ScriptEditorState>(find.byType(ScriptEditor));
