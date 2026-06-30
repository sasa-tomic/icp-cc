import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

void main() {
  group('Selection Mode Removal - POC Tests', () {
    Future<void> pumpScriptsScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('POC: ScriptsScreen renders without selection mode',
        (tester) async {
      await pumpScriptsScreen(tester);
      expect(find.byType(ScriptsScreen), findsOneWidget);
    });
  });

  group('Selection Mode Removal - State Machine Tests', () {
    test('ScriptsViewMachine source has no isSelectionMode getter', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('isSelectionMode'),
        isFalse,
        reason: 'isSelectionMode should not exist in scripts_screen_state.dart',
      );
    });

    test('ScriptsViewMachine source has no selectedScriptIds getter', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('selectedScriptIds'),
        isFalse,
        reason:
            'selectedScriptIds should not exist in scripts_screen_state.dart',
      );
    });

    test('ScriptsViewMachine source has no toggleScriptSelection method', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('toggleScriptSelection'),
        isFalse,
        reason:
            'toggleScriptSelection should not exist in scripts_screen_state.dart',
      );
    });

    test('ScriptsViewMachine source has no exitSelectionMode method', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('exitSelectionMode'),
        isFalse,
        reason:
            'exitSelectionMode should not exist in scripts_screen_state.dart',
      );
    });

    test('ScriptsViewMachine source has no setSelectionMode method', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('setSelectionMode'),
        isFalse,
        reason:
            'setSelectionMode should not exist in scripts_screen_state.dart',
      );
    });

    test('ScriptsViewMachine source has no selectAllLocalScripts method', () {
      final sourceFile = File('lib/screens/scripts_screen_state.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('selectAllLocalScripts'),
        isFalse,
        reason:
            'selectAllLocalScripts should not exist in scripts_screen_state.dart',
      );
    });
  });

  group('Selection Mode Removal - ScriptsScreen Tests', () {
    test('ScriptsScreen source has no _isSelectionMode state variable', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_isSelectionMode'),
        isFalse,
        reason: '_isSelectionMode should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _selectedScriptIds state variable', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_selectedScriptIds'),
        isFalse,
        reason: '_selectedScriptIds should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _selectionHintDismissed state variable',
        () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_selectionHintDismissed'),
        isFalse,
        reason:
            '_selectionHintDismissed should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _enterSelectionMode method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_enterSelectionMode'),
        isFalse,
        reason: '_enterSelectionMode should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _exitSelectionMode method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_exitSelectionMode'),
        isFalse,
        reason: '_exitSelectionMode should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _toggleScriptSelection method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_toggleScriptSelection'),
        isFalse,
        reason:
            '_toggleScriptSelection should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _confirmAndBulkDeleteScripts method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_confirmAndBulkDeleteScripts'),
        isFalse,
        reason:
            '_confirmAndBulkDeleteScripts should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _bulkExportScripts method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_bulkExportScripts'),
        isFalse,
        reason: '_bulkExportScripts should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _SelectionHintBanner widget', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_SelectionHintBanner'),
        isFalse,
        reason: '_SelectionHintBanner should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _buildSelectionModeAppBar method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_buildSelectionModeAppBar'),
        isFalse,
        reason:
            '_buildSelectionModeAppBar should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _buildSelectableListItem method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_buildSelectableListItem'),
        isFalse,
        reason:
            '_buildSelectableListItem should not exist in scripts_screen.dart',
      );
    });

    test('ScriptsScreen source has no _shouldShowSelectionHint method', () {
      final sourceFile = File('lib/screens/scripts_screen.dart');
      final content = sourceFile.readAsStringSync();

      expect(
        content.contains('_shouldShowSelectionHint'),
        isFalse,
        reason:
            '_shouldShowSelectionHint should not exist in scripts_screen.dart',
      );
    });
  });

  group('Selection Mode Removal - UI Tests', () {
    testWidgets('ScriptsScreen has no selection hint banner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.text('Tip: Long-press to select multiple scripts'),
        findsNothing,
        reason: 'Selection hint banner should not exist',
      );
    });

    testWidgets('ScriptsScreen always shows normal app bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Scripts'), findsOneWidget,
          reason: 'Normal app bar with "Scripts" title should always be shown');
    });

    testWidgets('ScriptsScreen has no select all button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.select_all), findsNothing,
          reason: 'Select all button should not exist');
    });

    testWidgets('ScriptsScreen has no deselect button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.deselect), findsNothing,
          reason: 'Deselect button should not exist');
    });

    testWidgets('ScriptsScreen has no bulk export button in app bar',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.file_download_outlined), findsNothing,
          reason: 'Bulk export button should not exist in app bar');
    });
  });
}
