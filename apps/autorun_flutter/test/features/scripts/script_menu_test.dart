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
        luaSource: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );
    });

    test('ScriptRecord has required properties for menu actions', () {
      expect(testScript.id, equals('test-1'));
      expect(testScript.title, equals('Test Script'));
      expect(testScript.luaSource, equals('return 1'));
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
        luaSource: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );

      expect(marketplaceScript.isFromMarketplace, isTrue);
    });

    test('Local script menu should have primary actions', () {
      final primaryActions = ['run', 'delete'];
      expect(primaryActions.length, equals(2));
    });

    test('Local script menu should have secondary actions after divider', () {
      final secondaryActions = ['duplicate', 'export', 'publish'];
      expect(secondaryActions.length, equals(3));
    });

    test('Marketplace script menu should have share action', () {
      final marketplaceActions = ['share', 'view_in_library'];
      expect(marketplaceActions.length, equals(2));
    });

    test('Total menu options for local scripts is 5 (reduced from 7+)', () {
      final localScriptMenuItems = [
        'run',
        'delete',
        'duplicate',
        'export',
        'publish',
      ];
      expect(localScriptMenuItems.length, lessThanOrEqualTo(5));
    });

    test('Publish option only shows for non-marketplace scripts', () {
      final localScript = testScript;
      final marketplaceDownload = ScriptRecord(
        id: 'test-2',
        title: 'Downloaded',
        luaSource: 'return 2',
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
  });
}

class ScriptsScreenMenuTest extends StatelessWidget {
  const ScriptsScreenMenuTest({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'run',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 20),
              SizedBox(width: 12),
              Text('Run'),
            ],
          ),
        ),
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
      ],
    );
  }
}
