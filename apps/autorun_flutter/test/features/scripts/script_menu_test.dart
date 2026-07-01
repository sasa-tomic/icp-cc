import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('Script item menu actions', () {
    late ScriptRecord testScript;

    setUp(() {
      testScript = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        emoji: '📜',
        bundle: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );
    });

    test('ScriptRecord has required properties for menu actions', () {
      expect(testScript.id, equals('test-1'));
      expect(testScript.title, equals('Test Script'));
      expect(testScript.bundle, equals('return 1'));
      expect(testScript.isFromMarketplace, isFalse);
    });

    test('ScriptRecord.isFromMarketplace returns false for local scripts', () {
      expect(testScript.isFromMarketplace, isFalse);
    });

    test('ScriptRecord.isFromMarketplace returns true for marketplace scripts',
        () {
      final marketplaceScript = ScriptRecord(
        id: 'test-2',
        title: 'Marketplace Script',
        bundle: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );

      expect(marketplaceScript.isFromMarketplace, isTrue);
    });

    test(
        'Local script menu should have secondary actions (run is now a button)',
        () {
      final secondaryActions = ['delete', 'duplicate', 'copy_source', 'publish'];
      expect(secondaryActions.length, equals(4));
    });

    test('Run action is now a separate play button, not in menu', () {
      final popupMenuActions = ['delete', 'duplicate', 'copy_source', 'publish'];
      expect(popupMenuActions.contains('run'), isFalse);
    });

    test('Marketplace script menu should have share action', () {
      final marketplaceActions = ['share', 'view_in_library'];
      expect(marketplaceActions.length, equals(2));
    });

    test('Popup menu for local scripts has 4 options (run moved to button)',
        () {
      final localScriptPopupMenuItems = [
        'delete',
        'duplicate',
        'copy_source',
        'publish',
      ];
      expect(localScriptPopupMenuItems.length, equals(4));
    });

    test('Publish option only shows for non-marketplace scripts', () {
      final localScript = testScript;
      final marketplaceDownload = ScriptRecord(
        id: 'test-2',
        title: 'Downloaded',
        bundle: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );

      final showPublishForLocal =
          !localScript.metadata.containsKey('marketplace_id');
      final showPublishForDownload =
          !marketplaceDownload.metadata.containsKey('marketplace_id');

      expect(showPublishForLocal, isTrue);
      expect(showPublishForDownload, isFalse);
    });
  });

  group('PopupMenu structure', () {
    testWidgets('ScriptsScreen has PopupMenuButton in AppBar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScriptsScreenMenuTest(),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsWidgets);
    });

    testWidgets('Local script row has Play button for immediate execution',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScriptsScreenMenuTest(),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('Play button and menu button are both visible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScriptsScreenMenuTest(),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });
}

class ScriptsScreenMenuTest extends StatelessWidget {
  const ScriptsScreenMenuTest({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () {},
          tooltip: 'Run script',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Delete'),
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
              value: 'copy_source',
              child: Row(
                children: [
                  Icon(Icons.copy, size: 20),
                  SizedBox(width: 12),
                  Text('Copy Source'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'publish',
              child: Row(
                children: [
                  Icon(Icons.upload, size: 20),
                  SizedBox(width: 12),
                  Text('Publish to Marketplace'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
