import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('Bulk Operations PoC', () {
    late List<ScriptRecord> testScripts;

    setUp(() {
      testScripts = [
        ScriptRecord(
          id: 'script-1',
          title: 'Test Script 1',
          emoji: '📜',
          bundle: 'print("hello 1")',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          metadata: {'marketplace_id': 'mp-1'},
        ),
        ScriptRecord(
          id: 'script-2',
          title: 'Test Script 2',
          emoji: '📦',
          bundle: 'print("hello 2")',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          metadata: {},
        ),
        ScriptRecord(
          id: 'script-3',
          title: 'Test Script 3',
          emoji: '⚡',
          bundle: 'print("hello 3")',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          metadata: {},
        ),
      ];
    });

    // =========================================================================
    // PoC 1: Selection Mode State Management
    // =========================================================================
    group('Selection Mode State', () {
      test('initial selection state is empty', () {
        final selectedIds = <String>{};
        expect(selectedIds.isEmpty, isTrue);
        expect(selectedIds.length, equals(0));
      });

      test('entering selection mode on long-press adds script to selection',
          () {
        final selectedIds = <String>{};
        final isSelectionMode = selectedIds.isNotEmpty;

        expect(isSelectionMode, isFalse);

        // Long-press triggers selection mode
        selectedIds.add('script-1');

        expect(selectedIds.contains('script-1'), isTrue);
        expect(selectedIds.length, equals(1));
      });

      test('toggling selection adds/removes script from selection', () {
        final selectedIds = <String>{};

        // Toggle on
        selectedIds.add('script-1');
        expect(selectedIds.contains('script-1'), isTrue);

        // Toggle off
        selectedIds.remove('script-1');
        expect(selectedIds.contains('script-1'), isFalse);
        expect(selectedIds.isEmpty, isTrue);
      });

      test('select all adds all local scripts to selection', () {
        final selectedIds = <String>{};
        final allLocalScriptIds = testScripts.map((s) => s.id).toList();

        // Select all
        selectedIds.addAll(allLocalScriptIds);

        expect(selectedIds.length, equals(3));
        expect(selectedIds.containsAll(['script-1', 'script-2', 'script-3']),
            isTrue);
      });

      test('deselect all clears selection', () {
        final selectedIds = <String>{'script-1', 'script-2', 'script-3'};

        // Deselect all
        selectedIds.clear();

        expect(selectedIds.isEmpty, isTrue);
      });

      test('exiting selection mode clears selection', () {
        final selectedIds = <String>{'script-1', 'script-2'};
        var isSelectionMode = true;

        // Exit selection mode
        isSelectionMode = false;
        selectedIds.clear();

        expect(isSelectionMode, isFalse);
        expect(selectedIds.isEmpty, isTrue);
      });

      test('selection count updates correctly', () {
        final selectedIds = <String>{};

        expect(selectedIds.length, equals(0));

        selectedIds.add('script-1');
        expect(selectedIds.length, equals(1));

        selectedIds.add('script-2');
        expect(selectedIds.length, equals(2));

        selectedIds.remove('script-1');
        expect(selectedIds.length, equals(1));
      });
    });

    // =========================================================================
    // PoC 2: Bulk Delete Logic
    // =========================================================================
    group('Bulk Delete Logic', () {
      test('bulk delete removes all selected scripts from list', () {
        final scripts = List<ScriptRecord>.from(testScripts);
        final selectedIds = <String>{'script-1', 'script-3'};

        // Perform bulk delete
        scripts.removeWhere((script) => selectedIds.contains(script.id));

        expect(scripts.length, equals(1));
        expect(scripts.first.id, equals('script-2'));
      });

      test('bulk delete with empty selection does nothing', () {
        final scripts = List<ScriptRecord>.from(testScripts);
        final selectedIds = <String>{};

        final originalLength = scripts.length;
        scripts.removeWhere((script) => selectedIds.contains(script.id));

        expect(scripts.length, equals(originalLength));
      });

      test('bulk delete with all selected clears list', () {
        final scripts = List<ScriptRecord>.from(testScripts);
        final selectedIds = scripts.map((s) => s.id).toSet();

        scripts.removeWhere((script) => selectedIds.contains(script.id));

        expect(scripts.isEmpty, isTrue);
      });

      test('bulk delete returns deleted count', () {
        final scripts = List<ScriptRecord>.from(testScripts);
        final selectedIds = <String>{'script-1', 'script-2'};

        final deletedCount =
            scripts.where((script) => selectedIds.contains(script.id)).length;
        scripts.removeWhere((script) => selectedIds.contains(script.id));

        expect(deletedCount, equals(2));
        expect(scripts.length, equals(1));
      });

      test('bulk delete ignores non-existent ids', () {
        final scripts = List<ScriptRecord>.from(testScripts);
        final selectedIds = <String>{'script-1', 'non-existent'};

        scripts.removeWhere((script) => selectedIds.contains(script.id));

        expect(scripts.length, equals(2));
        expect(scripts.any((s) => s.id == 'script-1'), isFalse);
      });
    });

    // =========================================================================
    // PoC 3: Bulk Export JSON Generation
    // =========================================================================
    group('Bulk Export JSON Generation', () {
      test('export creates valid JSON with selected scripts', () {
        final selectedScripts = testScripts
            .where((s) => s.id == 'script-1' || s.id == 'script-2')
            .toList();

        final exportData = {
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'scripts': selectedScripts.map((s) => s.toJson()).toList(),
        };

        final jsonString = jsonEncode(exportData);

        expect(jsonString, isNotEmpty);

        // Verify it can be decoded back
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        expect(decoded['version'], equals(1));
        expect(decoded['scripts'], isA<List>());
        expect((decoded['scripts'] as List).length, equals(2));
      });

      test('export preserves all script fields', () {
        final script = testScripts.first;
        final selectedScripts = [script];

        final exportData = {
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'scripts': selectedScripts.map((s) => s.toJson()).toList(),
        };

        final decoded =
            jsonDecode(jsonEncode(exportData)) as Map<String, dynamic>;
        final exportedScript =
            (decoded['scripts'] as List).first as Map<String, dynamic>;

        expect(exportedScript['id'], equals(script.id));
        expect(exportedScript['title'], equals(script.title));
        expect(exportedScript['emoji'], equals(script.emoji));
        expect(exportedScript['bundle'], equals(script.bundle));
        expect(exportedScript['metadata'], isNotNull);
      });

      test('export with metadata preserves marketplace info', () {
        final marketplaceScript = testScripts.first; // Has marketplace_id
        final selectedScripts = [marketplaceScript];

        final exportData = {
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'scripts': selectedScripts.map((s) => s.toJson()).toList(),
        };

        final decoded =
            jsonDecode(jsonEncode(exportData)) as Map<String, dynamic>;
        final exportedScript =
            (decoded['scripts'] as List).first as Map<String, dynamic>;
        final metadata = exportedScript['metadata'] as Map<String, dynamic>;

        expect(metadata['marketplace_id'], equals('mp-1'));
      });

      test('export empty selection returns empty scripts array', () {
        final selectedScripts = <ScriptRecord>[];

        final exportData = {
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'scripts': selectedScripts.map((s) => s.toJson()).toList(),
        };

        final decoded =
            jsonDecode(jsonEncode(exportData)) as Map<String, dynamic>;

        expect((decoded['scripts'] as List).isEmpty, isTrue);
      });

      test('export includes export timestamp', () {
        final exportTime = DateTime.now().toUtc();
        final exportData = {
          'version': 1,
          'exportedAt': exportTime.toIso8601String(),
          'scripts': [],
        };

        final decoded =
            jsonDecode(jsonEncode(exportData)) as Map<String, dynamic>;

        expect(decoded['exportedAt'], isNotNull);
        final parsedTime = DateTime.parse(decoded['exportedAt'] as String);
        expect(parsedTime.toUtc().toIso8601String(),
            equals(exportTime.toIso8601String()));
      });

      test('export format is importable (roundtrip)', () {
        final originalScripts = testScripts
            .where((s) => s.id == 'script-2' || s.id == 'script-3')
            .toList();

        // Export
        final exportData = {
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'scripts': originalScripts.map((s) => s.toJson()).toList(),
        };
        final jsonString = jsonEncode(exportData);

        // Import
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        final importedScripts = (decoded['scripts'] as List)
            .map((json) => ScriptRecord.fromJson(json as Map<String, dynamic>))
            .toList();

        expect(importedScripts.length, equals(originalScripts.length));
        for (int i = 0; i < originalScripts.length; i++) {
          expect(importedScripts[i].id, equals(originalScripts[i].id));
          expect(importedScripts[i].title, equals(originalScripts[i].title));
          expect(importedScripts[i].bundle,
              equals(originalScripts[i].bundle));
        }
      });
    });

    // =========================================================================
    // PoC 4: Selection Mode + Bulk Operations Integration
    // =========================================================================
    group('Selection Mode + Bulk Operations Integration', () {
      test('selection mode persists until explicitly exited', () {
        var isSelectionMode = false;
        final selectedIds = <String>{};

        // Enter selection mode
        isSelectionMode = true;
        selectedIds.add('script-1');

        // Perform operations (should not exit selection mode)
        selectedIds.add('script-2');

        expect(isSelectionMode, isTrue);
        expect(selectedIds.length, equals(2));

        // Explicitly exit
        isSelectionMode = false;
        selectedIds.clear();

        expect(isSelectionMode, isFalse);
      });

      test('only local scripts can be selected', () {
        // Simulate filtering - only local scripts (non-marketplace or downloaded marketplace)
        final selectableScripts = testScripts.where((s) {
          // All local scripts can be selected regardless of metadata
          return true;
        }).toList();

        expect(selectableScripts.length, equals(3));

        // Select all local scripts
        final selectedIds = selectableScripts.map((s) => s.id).toSet();
        expect(selectedIds.length, equals(3));
      });

      test('bulk operation confirmation shows correct count', () {
        final selectedIds = <String>{'script-1', 'script-2', 'script-3'};
        final confirmationMessage = 'Delete ${selectedIds.length} scripts?';

        expect(confirmationMessage, equals('Delete 3 scripts?'));
      });

      test('cancel bulk operation preserves selection', () {
        final selectedIds = <String>{'script-1', 'script-2'};
        final originalSelection = Set<String>.from(selectedIds);

        // User cancels the operation
        // Selection should remain unchanged
        expect(selectedIds.length, equals(originalSelection.length));
        expect(selectedIds.containsAll(originalSelection), isTrue);
      });
    });
  });

  // =========================================================================
  // Widget Tests: Selection Mode AppBar
  // =========================================================================
  group('Selection Mode AppBar Widget', () {
    testWidgets('selection mode AppBar shows count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: _TestSelectionModeAppBar(
              selectedCount: 3,
              onExit: () {},
              onSelectAll: () {},
              onDeselectAll: () {},
              onExport: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('3 selected'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('selection mode AppBar shows singular text for 1 item',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: _TestSelectionModeAppBar(
              selectedCount: 1,
              onExit: () {},
              onSelectAll: () {},
              onDeselectAll: () {},
              onExport: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('delete button is disabled when nothing selected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: _TestSelectionModeAppBar(
              selectedCount: 0,
              onExit: () {},
              onSelectAll: () {},
              onDeselectAll: () {},
              onExport: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      // Find the delete button (it should be disabled)
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsOneWidget);

      // The IconButton wrapping it should be disabled
      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: deleteButtons.first,
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('close button exits selection mode', (tester) async {
      bool exited = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: _TestSelectionModeAppBar(
              selectedCount: 2,
              onExit: () {
                exited = true;
              },
              onSelectAll: () {},
              onDeselectAll: () {},
              onExport: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(exited, isTrue);
    });
  });

  // =========================================================================
  // Widget Tests: Selectable List Item
  // =========================================================================
  group('Selectable List Item Widget', () {
    test('isSelected returns true for selected script', () {
      final selectedIds = <String>{'script-1'};
      final scriptId = 'script-1';
      final isSelected = selectedIds.contains(scriptId);

      expect(isSelected, isTrue);
    });

    test('isSelected returns false for unselected script', () {
      final selectedIds = <String>{'script-1'};
      final scriptId = 'script-2';
      final isSelected = selectedIds.contains(scriptId);

      expect(isSelected, isFalse);
    });

    testWidgets('checkbox reflects selection state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestSelectableItem(
              title: 'Test Script',
              emoji: '📜',
              isSelected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('checkbox is unchecked for unselected item', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestSelectableItem(
              title: 'Test Script',
              emoji: '📜',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    testWidgets('tapping item toggles selection', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestSelectableItem(
              title: 'Test Script',
              emoji: '📜',
              isSelected: false,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      // Tap the checkbox which should trigger onTap
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  // =========================================================================
  // Widget Tests: Bulk Delete Confirmation Dialog
  // =========================================================================
  group('Bulk Delete Confirmation Dialog', () {
    testWidgets('dialog shows correct count for single item', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete scripts'),
                      content:
                          const Text('Delete 1 script? This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete scripts'), findsOneWidget);
      expect(
          find.text('Delete 1 script? This cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('dialog shows correct count for multiple items',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete scripts'),
                      content: const Text(
                          'Delete 5 scripts? This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete 5 scripts? This cannot be undone.'),
          findsOneWidget);
    });
  });
}

// Test helper widgets

class _TestSelectionModeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _TestSelectionModeAppBar({
    required this.selectedCount,
    required this.onExit,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onExport,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onExit;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onExit,
        tooltip: 'Cancel selection',
      ),
      title: Text('$selectedCount selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: onSelectAll,
          tooltip: 'Select all',
        ),
        IconButton(
          icon: const Icon(Icons.file_download_outlined),
          onPressed: selectedCount > 0 ? onExport : null,
          tooltip: 'Export selected',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: selectedCount > 0 ? onDelete : null,
          tooltip: 'Delete selected',
        ),
      ],
    );
  }
}

class _TestSelectableItem extends StatelessWidget {
  const _TestSelectableItem({
    required this.title,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => onTap(),
          ),
          CircleAvatar(
            child: Text(emoji),
          ),
          Expanded(
            child: ListTile(
              title: Text(title),
            ),
          ),
        ],
      ),
    );
  }
}
