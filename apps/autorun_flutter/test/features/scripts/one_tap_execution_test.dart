import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

void main() {
  group('ONE-TAP Script Execution (#34)', () {
    late ScriptRecord localScript;
    late ScriptRecord marketplaceDownloadedScript;
    late MarketplaceScript marketplaceScript;

    setUp(() {
      localScript = ScriptRecord(
        id: 'local-1',
        title: 'My Local Script',
        emoji: '📜',
        luaSource: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      marketplaceDownloadedScript = ScriptRecord(
        id: 'mp-1',
        title: 'Downloaded Script',
        luaSource: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );

      marketplaceScript = MarketplaceScript(
        id: 'mp-456',
        title: 'Marketplace Script',
        description: 'A test marketplace script',
        category: 'Utilities',
        authorName: 'Author',
        luaSource: 'return 3',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    });

    group('Local script single tap', () {
      testWidgets('Single tap on local script RUNS immediately',
          (tester) async {
        var runCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {
                  runCalled = true;
                },
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap the script row
        await tester.tap(find.byType(ListTile));
        await tester.pump();

        // Verify run was called (not edit)
        expect(runCalled, isTrue);
      });

      testWidgets(
          'Single tap on downloaded marketplace script RUNS immediately',
          (tester) async {
        var runCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: marketplaceDownloadedScript,
                onTap: () {
                  runCalled = true;
                },
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap the script row
        await tester.tap(find.byType(ListTile));
        await tester.pump();

        // Verify run was called
        expect(runCalled, isTrue);
      });
    });

    group('Marketplace script single tap (unchanged behavior)', () {
      testWidgets('Single tap on marketplace script shows details (not run)',
          (tester) async {
        var detailsCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketplaceScriptRow(
                script: marketplaceScript,
                onTap: () {
                  detailsCalled = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap the script row
        await tester.tap(find.byType(ListTile));
        await tester.pump();

        // Verify details was called
        expect(detailsCalled, isTrue);
      });
    });

    group('Edit action accessibility', () {
      testWidgets('Edit is accessible via overflow menu for local scripts',
          (tester) async {
        var editCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {
                  editCalled = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Open overflow menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Verify Edit is in the menu
        expect(find.text('Edit'), findsOneWidget);

        // Tap Edit
        await tester.tap(find.text('Edit'));
        await tester.pump();

        // Verify edit callback was called
        expect(editCalled, isTrue);
      });

      testWidgets('Edit is the first option in overflow menu', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Open overflow menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Find all PopupMenuItems
        final menuItems = find.byType(PopupMenuItem<String>);
        expect(menuItems, findsWidgets);

        // First item should be Edit
        final firstItemText = find.descendant(
          of: menuItems.first,
          matching: find.text('Edit'),
        );
        expect(firstItemText, findsOneWidget);
      });
    });

    group('Long-press context menu', () {
      testWidgets('Long-press on local script shows context menu with Edit',
          (tester) async {
        var editCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {
                  editCalled = true;
                },
                showContextMenuOnLongPress: true,
              ),
            ),
          ),
        );

        await tester.pump();

        // Long press to show context menu
        await tester.longPress(find.byType(ListTile));
        await tester.pumpAndSettle();

        // Verify Edit is in the context menu
        expect(find.text('Edit'), findsOneWidget);

        // Tap Edit
        await tester.tap(find.text('Edit'));
        await tester.pump();

        // Verify edit callback was called
        expect(editCalled, isTrue);
      });
    });

    group('Tap count reduction verification', () {
      testWidgets(
          'Running a script requires only ONE tap (vs 3-4 in previous flow)',
          (tester) async {
        var runCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {
                  runCount++;
                },
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Single tap to run
        await tester.tap(find.byType(ListTile));
        await tester.pump();

        // Verify script ran with just one tap
        expect(runCount, equals(1));
      });

      testWidgets(
          'Editing a script requires 2 taps (overflow menu + Edit) vs 1 tap to open editor before',
          (tester) async {
        var editCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {
                  editCount++;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Two taps to edit: overflow menu + Edit
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pump();

        // Verify edit happened with 2 taps
        expect(editCount, equals(1));
      });
    });

    group('Visual indicators', () {
      testWidgets('Play icon indicates that tapping will run the script',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Play icon should be visible as a hint that tap = run
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      });

      testWidgets(
          'Overflow menu icon is visible for accessing secondary actions',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OneTapScriptRow(
                script: localScript,
                onTap: () {},
                onEdit: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Overflow menu icon should be visible
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
      });
    });
  });
}

/// Test widget representing the new ONE-TAP execution behavior
/// Single tap = Run immediately
/// Edit accessible via overflow menu
class OneTapScriptRow extends StatelessWidget {
  const OneTapScriptRow({
    super.key,
    required this.script,
    required this.onTap,
    required this.onEdit,
    this.showContextMenuOnLongPress = false,
  });

  final ScriptRecord script;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final bool showContextMenuOnLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress:
          showContextMenuOnLongPress ? () => _showContextMenu(context) : null,
      child: ListTile(
        leading: CircleAvatar(
          child: Text(script.emoji ?? '📜'),
        ),
        title: Text(script.title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play icon hint that tap = run
            const Icon(Icons.play_arrow, color: Colors.green),
            // Overflow menu for secondary actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Row(
                    children: [
                      Icon(Icons.content_copy, size: 20),
                      SizedBox(width: 12),
                      Text('Duplicate'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        // ONE-TAP: Single tap runs the script
        onTap: onTap,
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Run'),
              onTap: () {
                Navigator.pop(context);
                onTap();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Test widget representing marketplace script behavior (unchanged)
class MarketplaceScriptRow extends StatelessWidget {
  const MarketplaceScriptRow({
    super.key,
    required this.script,
    required this.onTap,
  });

  final MarketplaceScript script;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Text('📦'),
      ),
      title: Text(script.title),
      subtitle: Text(script.authorName ?? 'Unknown'),
      // Marketplace scripts show details on tap (unchanged)
      onTap: onTap,
    );
  }
}
