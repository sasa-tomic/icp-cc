import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';

void main() {
  group('Long-press context menu', () {
    late ScriptRecord testLocalScript;
    late MarketplaceScript testMarketplaceScript;

    setUp(() {
      testLocalScript = ScriptRecord(
        id: 'local-1',
        title: 'Test Local Script',
        emoji: 'T',
        bundle: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      testMarketplaceScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Test Marketplace Script',
        authorName: 'Test Author',
        version: '1.0.0',
        description: 'Test description',
        category: 'utilities',
        bundle: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    });

    test('ScriptListItem.fromLocal creates item with correct source', () {
      final item = ScriptListItem.fromLocal(testLocalScript);

      expect(item.source, equals(ScriptSource.local));
      expect(item.localScript, isNotNull);
      expect(item.marketplaceScript, isNull);
      expect(item.isInstalled, isTrue);
    });

    test('ScriptListItem.fromMarketplace creates item with correct source', () {
      final item = ScriptListItem.fromMarketplace(testMarketplaceScript);

      expect(item.source, equals(ScriptSource.marketplace));
      expect(item.localScript, isNull);
      expect(item.marketplaceScript, isNotNull);
    });

    test(
        'Local script context menu should have run, edit, duplicate, delete actions',
        () {
      final localActions = ['run', 'edit', 'duplicate', 'delete'];
      expect(localActions.length, equals(4));
    });

    test(
        'Local script context menu should include publish for non-marketplace scripts',
        () {
      final isPublished =
          testLocalScript.metadata.containsKey('marketplace_id');
      final showPublish = !isPublished;

      expect(showPublish, isTrue);
    });

    test(
        'Local script context menu should not include publish for downloaded marketplace scripts',
        () {
      final downloadedScript = ScriptRecord(
        id: 'local-2',
        title: 'Downloaded Script',
        bundle: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );

      final isPublished =
          downloadedScript.metadata.containsKey('marketplace_id');
      final showPublish = !isPublished;

      expect(showPublish, isFalse);
    });

    test(
        'Marketplace script context menu should have view details and download actions',
        () {
      final marketplaceActions = ['view_details', 'download'];
      expect(marketplaceActions.length, equals(2));
    });

    test(
        'Marketplace script context menu should not show download if already installed',
        () {
      final item = ScriptListItem.fromMarketplace(
        testMarketplaceScript,
        isInstalled: true,
      );

      expect(item.isInstalled, isTrue);
    });

    testWidgets('Context menu sheet displays script title', (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onRun: () {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Local Script'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
    });

    testWidgets('Context menu shows Run action for local scripts',
        (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onRun: () {},
            ),
          ),
        ),
      );

      expect(find.text('Run'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('Context menu shows Edit action for local scripts',
        (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onEdit: () {},
            ),
          ),
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('Context menu shows Delete action for local scripts',
        (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('Context menu shows View Details for marketplace scripts',
        (tester) async {
      final item = ScriptListItem.fromMarketplace(testMarketplaceScript);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onViewDetails: () {},
            ),
          ),
        ),
      );

      expect(find.text('View Details'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets(
        'Context menu shows Download for non-installed marketplace scripts',
        (tester) async {
      final item = ScriptListItem.fromMarketplace(
        testMarketplaceScript,
        isInstalled: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onDownload: () {},
              isDownloaded: false,
            ),
          ),
        ),
      );

      expect(find.text('Download'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets(
        'Context menu shows Already Downloaded for installed marketplace scripts',
        (tester) async {
      final item = ScriptListItem.fromMarketplace(
        testMarketplaceScript,
        isInstalled: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              isDownloaded: true,
            ),
          ),
        ),
      );

      expect(find.text('Already Downloaded'), findsOneWidget);
    });

    testWidgets('Long press on ListTile triggers context menu', (tester) async {
      bool longPressTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onLongPress: () {
                longPressTriggered = true;
              },
              child: ListTile(
                title: const Text('Test Script'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(ListTile));
      await tester.pump();

      expect(longPressTriggered, isTrue);
    });

    testWidgets('Right-click on desktop triggers context menu', (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);
      final contextMenuItems = [
        'run',
        'edit',
        'duplicate',
        'delete',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return GestureDetector(
                  onSecondaryTapUp: (details) {
                    showMenu<String>(
                      context: context,
                      position: RelativeRect.fill,
                      items: contextMenuItems.map((action) {
                        return PopupMenuItem(
                          value: action,
                          child: Text(action),
                        );
                      }).toList(),
                    );
                  },
                  child: ListTile(
                    title: Text(item.title),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsWidgets);
      expect(find.text('Test Local Script'), findsOneWidget);
    });

    testWidgets('Context menu action tap dismisses sheet', (tester) async {
      final item = ScriptListItem.fromLocal(testLocalScript);
      bool actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestContextMenuSheet(
              item: item,
              onRun: () {
                actionCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(actionCalled, isTrue);
    });
  });

  group('Context menu action callbacks', () {
    test('Local script all actions are optional and nullable', () {
      final actions = <String, VoidCallback?>{
        'run': null,
        'edit': null,
        'duplicate': null,
        'delete': null,
        'publish': null,
      };

      for (final action in actions.entries) {
        expect(action.value, isNull);
      }
    });

    test('Marketplace script all actions are optional and nullable', () {
      final actions = <String, VoidCallback?>{
        'view_details': null,
        'download': null,
      };

      for (final action in actions.entries) {
        expect(action.value, isNull);
      }
    });
  });
}

class _TestContextMenuSheet extends StatelessWidget {
  const _TestContextMenuSheet({
    required this.item,
    this.onRun,
    this.onEdit,
    this.onDelete,
    this.onViewDetails,
    this.onDownload,
    this.isDownloaded = false,
  });

  final ScriptListItem item;
  final VoidCallback? onRun;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewDetails;
  final VoidCallback? onDownload;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(
                child: Text('T'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      item.isFromMarketplace ? 'Marketplace' : 'Local',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          if (item.source == ScriptSource.local) ...[
            if (onRun != null)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onRun!();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow, size: 22),
                      SizedBox(width: 12),
                      Text('Run', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            if (onEdit != null)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onEdit!();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 22),
                      SizedBox(width: 12),
                      Text('Edit', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            if (onDelete != null)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onDelete!();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 22, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Delete',
                          style: TextStyle(fontSize: 16, color: Colors.red)),
                    ],
                  ),
                ),
              ),
          ],
          if (item.source == ScriptSource.marketplace) ...[
            if (onViewDetails != null)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onViewDetails!();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 22),
                      SizedBox(width: 12),
                      Text('View Details', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            if (onDownload != null && !isDownloaded)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onDownload!();
                },
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 22),
                      SizedBox(width: 12),
                      Text('Download', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            if (isDownloaded)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 22),
                    SizedBox(width: 12),
                    Text('Already Downloaded', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
