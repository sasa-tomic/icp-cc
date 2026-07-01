import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

void main() {
  group('Simplified script row actions', () {
    late ScriptRecord localScript;
    late MarketplaceScript marketplaceScript;

    setUp(() {
      localScript = ScriptRecord(
        id: 'local-1',
        title: 'My Local Script',
        emoji: '📜',
        bundle: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      marketplaceScript = MarketplaceScript(
        id: 'mp-456',
        title: 'Marketplace Script',
        description: 'A test marketplace script',
        category: 'Utilities',
        authorName: 'Author',
        bundle: 'return 3',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    });

    group('Local script row', () {
      testWidgets('Shows exactly ONE primary action button (Play)',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Play button should be visible
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        // Overflow menu button should be visible
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
      });

      testWidgets('Inline share button is NOT visible', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Share button should NOT be visible as an inline button
        expect(find.byIcon(Icons.share), findsNothing);
      });

      testWidgets('Play button triggers run callback', (tester) async {
        var runCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {
                  runCalled = true;
                },
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();

        expect(runCalled, isTrue);
      });

      testWidgets('Overflow menu contains Edit action', (tester) async {
        var editCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {
                  editCalled = true;
                },
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Open the overflow menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Verify Edit is in the menu
        expect(find.text('Edit'), findsOneWidget);

        // Test Edit action works
        await tester.tap(find.text('Edit'));
        await tester.pump();
        expect(editCalled, isTrue);
      });

      testWidgets('Overflow menu contains Delete action', (tester) async {
        var deleteCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {
                  deleteCalled = true;
                },
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(find.text('Delete'), findsOneWidget);

        await tester.tap(find.text('Delete'));
        await tester.pump();
        expect(deleteCalled, isTrue);
      });

      testWidgets(
          'Overflow menu contains Share to Marketplace action for local scripts',
          (tester) async {
        var publishCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {
                  publishCalled = true;
                },
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(find.text('Share to Marketplace'), findsOneWidget);

        await tester.tap(find.text('Share to Marketplace'));
        await tester.pump();
        expect(publishCalled, isTrue);
      });

      testWidgets('Overflow menu contains Duplicate and Copy Source actions',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(find.text('Duplicate'), findsOneWidget);
        expect(find.text('Copy Source'), findsOneWidget);
      });
    });

    group('Marketplace script row', () {
      testWidgets(
          'Shows exactly ONE primary action button (Download) for not-installed scripts',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: false,
                onViewDetails: () {},
                onDownload: () {},
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Primary action (Download) should be visible
        expect(find.byIcon(Icons.download), findsOneWidget);

        // Overflow menu button should be visible
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
      });

      testWidgets('Shows View as primary action for already downloaded scripts',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: true,
                onViewDetails: () {},
                onDownload: () {},
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Primary action should be View (info_outline) for downloaded scripts
        expect(find.byIcon(Icons.info_outline), findsOneWidget);

        // Overflow menu button should be visible
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
      });

      testWidgets('Primary download button triggers download callback',
          (tester) async {
        var downloadCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: false,
                onViewDetails: () {},
                onDownload: () {
                  downloadCalled = true;
                },
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.download));
        await tester.pump();

        expect(downloadCalled, isTrue);
      });

      testWidgets('Share action is in overflow menu, not inline',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: false,
                onViewDetails: () {},
                onDownload: () {},
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // No inline share button
        expect(find.byIcon(Icons.share), findsNothing);

        // Tap overflow menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Share should be in the menu
        expect(find.text('Share'), findsOneWidget);
      });

      testWidgets('View Details action is in overflow menu', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: false,
                onViewDetails: () {},
                onDownload: () {},
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // View Details should be in the menu
        expect(find.text('View Details'), findsOneWidget);
      });
    });

    group('Visual noise reduction verification', () {
      testWidgets('Local script row has Play button + overflow menu only',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedLocalScriptRowTest(
                script: localScript,
                onRun: () {},
                onEdit: () {},
                onDuplicate: () {},
                onDelete: () {},
                onPublish: () {},
                onExport: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Verify we have exactly 2 action icons visible: Play and More (overflow)
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);

        // Verify no other action buttons are visible
        expect(find.byIcon(Icons.share), findsNothing);
        expect(find.byIcon(Icons.edit), findsNothing);
        expect(find.byIcon(Icons.delete), findsNothing);
        expect(find.byIcon(Icons.content_copy), findsNothing);
      });

      testWidgets('Marketplace script row has Download + overflow menu only',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SimplifiedMarketplaceScriptRowTest(
                script: marketplaceScript,
                isDownloaded: false,
                onViewDetails: () {},
                onDownload: () {},
                onShare: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        // Verify we have exactly 2 action icons visible: Download and More (overflow)
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);

        // Verify no other action buttons are visible
        expect(find.byIcon(Icons.share), findsNothing);
        expect(find.byIcon(Icons.info_outline), findsNothing);
      });
    });
  });
}

/// Simplified local script row widget for testing
/// Shows ONLY: Play button (primary) + overflow menu (all secondary actions)
class SimplifiedLocalScriptRowTest extends StatelessWidget {
  const SimplifiedLocalScriptRowTest({
    super.key,
    required this.script,
    required this.onRun,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onPublish,
    required this.onExport,
  });

  final ScriptRecord script;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onPublish;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final canPublish = !script.isFromMarketplace;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PRIMARY ACTION: Play button
        IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: onRun,
          tooltip: 'Run script',
        ),
        // OVERFLOW MENU: All secondary actions
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'duplicate':
                onDuplicate();
                break;
              case 'delete':
                onDelete();
                break;
              case 'publish':
                onPublish();
                break;
              case 'copy_source':
                onExport();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text('Edit'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'duplicate',
              child: Text('Duplicate'),
            ),
            if (canPublish)
              const PopupMenuItem(
                value: 'publish',
                child: Text('Share to Marketplace'),
              ),
            const PopupMenuItem(
              value: 'copy_source',
              child: Text('Copy Source'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Simplified marketplace script row widget for testing
/// Shows ONLY: View/Download button (primary) + overflow menu (all secondary actions)
class SimplifiedMarketplaceScriptRowTest extends StatelessWidget {
  const SimplifiedMarketplaceScriptRowTest({
    super.key,
    required this.script,
    required this.isDownloaded,
    required this.onViewDetails,
    required this.onDownload,
    required this.onShare,
  });

  final MarketplaceScript script;
  final bool isDownloaded;
  final VoidCallback onViewDetails;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PRIMARY ACTION: Download (if not downloaded) or View (if downloaded)
        IconButton(
          icon: Icon(
            isDownloaded ? Icons.info_outline : Icons.download,
          ),
          onPressed: isDownloaded ? onViewDetails : onDownload,
          tooltip: isDownloaded ? 'View details' : 'Download',
        ),
        // OVERFLOW MENU: All secondary actions
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'view_details':
                onViewDetails();
                break;
              case 'download':
                onDownload();
                break;
              case 'share':
                onShare();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view_details',
              child: Text('View Details'),
            ),
            if (!isDownloaded)
              const PopupMenuItem(
                value: 'download',
                child: Text('Download'),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'share',
              child: Text('Share'),
            ),
          ],
        ),
      ],
    );
  }
}
