import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';

void main() {
  group('ScriptListItem', () {
    late ScriptRecord localScript;
    late ScriptRecord marketplaceDownloaded;
    late MarketplaceScript marketplaceScript;

    setUp(() {
      final now = DateTime.now().toUtc();

      localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        emoji: '📜',
        luaSource: 'return 1',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 1)),
        metadata: {},
      );

      marketplaceDownloaded = ScriptRecord(
        id: 'local-2',
        title: 'Downloaded Script (Marketplace)',
        emoji: '📦',
        luaSource: 'return 2',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 12)),
        metadata: {
          'marketplace_id': 'mp-123',
          'marketplace_version': '1.0.0',
          'marketplace_author': 'Test Author',
        },
      );

      marketplaceScript = MarketplaceScript(
        id: 'mp-456',
        title: 'Marketplace Script',
        description: 'A script from marketplace',
        category: 'Utilities',
        luaSource: 'return 3',
        authorName: 'Another Author',
        version: '2.0.0',
        downloads: 150,
        rating: 4.5,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );
    });

    group('factory constructors', () {
      test('fromLocal creates item with correct properties', () {
        final item = ScriptListItem.fromLocal(localScript, runCount: 5);

        expect(item.source, equals(ScriptSource.local));
        expect(item.isInstalled, isTrue);
        expect(item.runCount, equals(5));
        expect(item.id, equals('local-1'));
        expect(item.title, equals('Local Script'));
        expect(item.emoji, equals('📜'));
        expect(item.isFromMarketplace, isFalse);
      });

      test('fromLocal with lastRunAt uses provided timestamp', () {
        final lastRun = DateTime(2024, 1, 15);
        final item = ScriptListItem.fromLocal(
          localScript,
          runCount: 3,
          lastRunAt: lastRun,
        );

        expect(item.lastRunAt, equals(lastRun));
      });

      test('fromMarketplace creates item with correct properties', () {
        final item = ScriptListItem.fromMarketplace(marketplaceScript);

        expect(item.source, equals(ScriptSource.marketplace));
        expect(item.isInstalled, isFalse);
        expect(item.id, equals('mp-456'));
        expect(item.title, equals('Marketplace Script'));
        expect(item.author, equals('Another Author'));
        expect(item.version, equals('2.0.0'));
        expect(item.downloads, equals(150));
        expect(item.rating, equals(4.5));
        expect(item.isFromMarketplace, isTrue);
      });

      test('fromMarketplace with isInstalled=true sets installed flag', () {
        final item = ScriptListItem.fromMarketplace(
          marketplaceScript,
          isInstalled: true,
        );

        expect(item.isInstalled, isTrue);
      });
    });

    group('property accessors', () {
      test('author returns marketplace_author for downloaded scripts', () {
        final item = ScriptListItem.fromLocal(marketplaceDownloaded);

        expect(item.author, equals('Test Author'));
        expect(item.isFromMarketplace, isTrue);
      });

      test('version returns marketplace_version for downloaded scripts', () {
        final item = ScriptListItem.fromLocal(marketplaceDownloaded);

        expect(item.version, equals('1.0.0'));
      });

      test('description returns null for local scripts', () {
        final item = ScriptListItem.fromLocal(localScript);

        expect(item.description, isNull);
      });

      test('description returns description for marketplace scripts', () {
        final item = ScriptListItem.fromMarketplace(marketplaceScript);

        expect(item.description, equals('A script from marketplace'));
      });
    });

    group('createHybridList', () {
      test('combines local and marketplace scripts', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [localScript],
          marketplaceScripts: [marketplaceScript],
          installedMarketplaceIds: {},
        );

        expect(items.length, equals(2));
        expect(items.any((i) => i.source == ScriptSource.local), isTrue);
        expect(items.any((i) => i.source == ScriptSource.marketplace), isTrue);
      });

      test('deduplicates marketplace scripts already installed locally', () {
        final mpAlreadyInstalled = MarketplaceScript(
          id: 'mp-123',
          title: 'Same as Downloaded',
          description: 'desc',
          category: 'Utilities',
          luaSource: 'return 2',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        final items = ScriptListItem.createHybridList(
          localScripts: [marketplaceDownloaded],
          marketplaceScripts: [mpAlreadyInstalled],
          installedMarketplaceIds: {'mp-123'},
        );

        expect(items.length, equals(1));
        expect(items.first.source, equals(ScriptSource.local));
      });

      test('marks marketplace scripts as installed when in set', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [],
          marketplaceScripts: [marketplaceScript],
          installedMarketplaceIds: {'mp-456'},
        );

        expect(items.length, equals(1));
        expect(items.first.isInstalled, isTrue);
      });

      test('applies run counts and lastRunAt from maps', () {
        final lastRun = DateTime(2024, 1, 20);
        final items = ScriptListItem.createHybridList(
          localScripts: [localScript],
          marketplaceScripts: [],
          installedMarketplaceIds: {},
          runCounts: {'local-1': 10},
          lastRunAt: {'local-1': lastRun},
        );

        expect(items.first.runCount, equals(10));
        expect(items.first.lastRunAt, equals(lastRun));
      });
    });

    group('sortItems', () {
      late List<ScriptListItem> testItems;

      setUp(() {
        final now = DateTime.now().toUtc();

        final script1 = ScriptRecord(
          id: '1',
          title: 'Alpha Script',
          luaSource: 'return 1',
          createdAt: now,
          updatedAt: now.subtract(const Duration(days: 3)),
          metadata: {},
        );

        final script2 = ScriptRecord(
          id: '2',
          title: 'Beta Script',
          luaSource: 'return 2',
          createdAt: now,
          updatedAt: now.subtract(const Duration(days: 1)),
          metadata: {},
        );

        final script3 = ScriptRecord(
          id: '3',
          title: 'Gamma Script',
          luaSource: 'return 3',
          createdAt: now,
          updatedAt: now,
          metadata: {},
        );

        testItems = [
          ScriptListItem.fromLocal(script1,
              runCount: 5, lastRunAt: now.subtract(const Duration(hours: 2))),
          ScriptListItem.fromLocal(script2,
              runCount: 10, lastRunAt: now.subtract(const Duration(hours: 1))),
          ScriptListItem.fromLocal(script3, runCount: 3, lastRunAt: now),
        ];
      });

      test('sorts by lastRunAt descending by default', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.lastRun,
        );

        expect(sorted[0].id, equals('3'));
        expect(sorted[1].id, equals('2'));
        expect(sorted[2].id, equals('1'));
      });

      test('sorts by lastRunAt ascending when specified', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.lastRun,
          ascending: true,
        );

        expect(sorted[0].id, equals('1'));
        expect(sorted[1].id, equals('2'));
        expect(sorted[2].id, equals('3'));
      });

      test('sorts by name', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.name,
        );

        expect(sorted[0].title, equals('Gamma Script'));
        expect(sorted[1].title, equals('Beta Script'));
        expect(sorted[2].title, equals('Alpha Script'));
      });

      test('sorts by name ascending', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.name,
          ascending: true,
        );

        expect(sorted[0].title, equals('Alpha Script'));
        expect(sorted[1].title, equals('Beta Script'));
        expect(sorted[2].title, equals('Gamma Script'));
      });

      test('sorts by runCount descending', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.runCount,
        );

        expect(sorted[0].runCount, equals(10));
        expect(sorted[1].runCount, equals(5));
        expect(sorted[2].runCount, equals(3));
      });

      test('sorts by updatedAt descending', () {
        final sorted = ScriptListItem.sortItems(
          testItems,
          ScriptSortOption.updatedAt,
        );

        expect(sorted[0].id, equals('3'));
        expect(sorted[1].id, equals('2'));
        expect(sorted[2].id, equals('1'));
      });

      test('sorts by source with installed first', () {
        final mp1 = MarketplaceScript(
          id: 'mp-1',
          title: 'Not Installed',
          description: '',
          category: 'Utilities',
          luaSource: '',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        final mp2 = MarketplaceScript(
          id: 'mp-2',
          title: 'Also Not Installed',
          description: '',
          category: 'Utilities',
          luaSource: '',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        final mixedItems = [
          ScriptListItem.fromMarketplace(mp1, isInstalled: false),
          ...testItems,
          ScriptListItem.fromMarketplace(mp2, isInstalled: false),
        ];

        final sorted = ScriptListItem.sortItems(
          mixedItems,
          ScriptSortOption.source,
        );

        expect(sorted.where((i) => i.isInstalled).length, equals(3));
        expect(sorted.where((i) => !i.isInstalled).length, equals(2));

        for (var i = 0; i < 3; i++) {
          expect(sorted[i].isInstalled, isTrue);
        }
        for (var i = 3; i < 5; i++) {
          expect(sorted[i].isInstalled, isFalse);
        }
      });

      test('does not modify original list', () {
        final originalOrder = testItems.map((i) => i.id).toList();

        ScriptListItem.sortItems(testItems, ScriptSortOption.name);

        expect(testItems.map((i) => i.id).toList(), equals(originalOrder));
      });
    });

    group('equality', () {
      test('equal items have same hashCode', () {
        final item1 = ScriptListItem.fromLocal(localScript);
        final item2 = ScriptListItem.fromLocal(localScript);

        expect(item1, equals(item2));
        expect(item1.hashCode, equals(item2.hashCode));
      });

      test('different items are not equal', () {
        final item1 = ScriptListItem.fromLocal(localScript);
        final item2 = ScriptListItem.fromMarketplace(marketplaceScript);

        expect(item1, isNot(equals(item2)));
      });
    });
  });
}
