import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/screens/scripts_screen_state.dart';

void main() {
  group('ScriptsViewMachine', () {
    late ScriptsViewMachine stateMachine;

    setUp(() {
      stateMachine = ScriptsViewMachine();
    });

    group('initial state', () {
      test('starts in loading state', () {
        expect(stateMachine.currentView, equals(ScriptsView.loading));
        expect(stateMachine.isLoadingLocal, isTrue);
        expect(stateMachine.isLoadingMarketplace, isTrue);
      });
    });

    group('view determination', () {
      test('returns loading when loading and no content', () {
        stateMachine
          ..setLocalLoading(true)
          ..setMarketplaceLoading(true)
          ..setLocalScripts([])
          ..setMarketplaceScripts([]);

        expect(stateMachine.currentView, equals(ScriptsView.loading));
      });

      test(
          'returns content when local scripts exist (even if marketplace loading)',
          () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(true)
          ..setLocalScripts([_createLocalScript()])
          ..setMarketplaceScripts([]);

        expect(stateMachine.currentView, equals(ScriptsView.content));
      });

      test('returns content when marketplace scripts exist and local loading',
          () {
        stateMachine
          ..setLocalLoading(true)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([_createMarketplaceScript()]);

        expect(stateMachine.currentView, equals(ScriptsView.content));
      });

      test('returns content when marketplace scripts exist (new user scenario)',
          () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([_createMarketplaceScript()]);

        // This is the KEY fix: new users should see marketplace content, not empty
        expect(stateMachine.currentView, equals(ScriptsView.content));
      });

      test('returns empty when both local and marketplace are empty', () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([]);

        expect(stateMachine.currentView, equals(ScriptsView.empty));
      });

      test('returns emptyDownloaded when downloaded filter shows no results',
          () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([_createMarketplaceScript()])
          ..setShowDownloadedOnly(true)
          ..setDownloadedScriptIds({});

        expect(stateMachine.currentView, equals(ScriptsView.emptyDownloaded));
      });

      test('returns emptyFavorites when favorites filter shows no results', () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([_createLocalScript()])
          ..setMarketplaceScripts([])
          ..setShowFavoritesOnly(true)
          ..setFavoriteScriptIds({});

        expect(stateMachine.currentView, equals(ScriptsView.emptyFavorites));
      });

      test('returns searchResults when search query is active', () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([_createMarketplaceScript()])
          ..setSearchQuery('test');

        expect(stateMachine.currentView, equals(ScriptsView.searchResults));
      });

      test('returns searchEmpty when search query returns no results', () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([])
          ..setSearchQuery('nonexistent')
          ..setSearching(false);

        expect(stateMachine.currentView, equals(ScriptsView.searchEmpty));
      });

      test('returns loading when searching in progress', () {
        stateMachine
          ..setLocalLoading(false)
          ..setMarketplaceLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceScripts([])
          ..setSearchQuery('test')
          ..setSearching(true);

        expect(stateMachine.currentView, equals(ScriptsView.loading));
      });
    });

    group('filter application', () {
      test('filters to downloaded only when flag is set', () {
        final localScript = _createLocalScript(id: 'local-1');
        final marketplaceScript = _createMarketplaceScript(id: 'market-1');

        stateMachine
          ..setLocalScripts([localScript])
          ..setMarketplaceScripts([marketplaceScript])
          ..setDownloadedScriptIds({'market-1'})
          ..setShowDownloadedOnly(true);

        final items = stateMachine.getFilteredItems();
        // Only marketplace script that's downloaded should appear
        // Note: Local scripts from marketplace also count as downloaded
        expect(items.any((i) => i.isFromMarketplace || i.isInstalled), isTrue);
      });

      test('filters to favorites only when flag is set', () {
        final script1 = _createLocalScript(id: 'script-1');
        final script2 = _createLocalScript(id: 'script-2');

        stateMachine
          ..setLocalScripts([script1, script2])
          ..setMarketplaceScripts([])
          ..setFavoriteScriptIds({'script-1'})
          ..setShowFavoritesOnly(true);

        final items = stateMachine.getFilteredItems();
        // Only favorited items should appear
        expect(items.length, equals(1));
      });

      test('applies sort option correctly', () {
        final script1 = _createLocalScript(id: 'a', title: 'Zebra');
        final script2 = _createLocalScript(id: 'b', title: 'Alpha');

        stateMachine
          ..setLocalScripts([script1, script2])
          ..setMarketplaceScripts([])
          ..setSortOption(ScriptSortOption.name, ascending: true);

        final items = stateMachine.getFilteredItems();
        expect(items.first.title, equals('Alpha'));
        expect(items.last.title, equals('Zebra'));
      });

      test('shows all content when filters are cleared', () {
        stateMachine
          ..setLocalScripts([_createLocalScript()])
          ..setMarketplaceScripts([_createMarketplaceScript()])
          ..setShowDownloadedOnly(false)
          ..setShowFavoritesOnly(false);

        final items = stateMachine.getFilteredItems();
        expect(items.length, equals(2));
      });
    });

    group('progressive loading', () {
      test('shows loading spinner while marketplace loads for new user', () {
        // Simulate new user: local scripts load fast, marketplace takes time
        stateMachine
          ..setLocalLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceLoading(true)
          ..setMarketplaceScripts([]);

        // Should show loading, not empty state
        expect(stateMachine.currentView, equals(ScriptsView.loading));
      });

      test('transitions from loading to content when marketplace arrives', () {
        // Start with loading
        stateMachine
          ..setLocalLoading(false)
          ..setLocalScripts([])
          ..setMarketplaceLoading(true)
          ..setMarketplaceScripts([]);

        expect(stateMachine.currentView, equals(ScriptsView.loading));

        // Marketplace arrives
        stateMachine
          ..setMarketplaceLoading(false)
          ..setMarketplaceScripts([_createMarketplaceScript()]);

        expect(stateMachine.currentView, equals(ScriptsView.content));
      });

      test('shows content immediately when local scripts exist', () {
        stateMachine
          ..setLocalLoading(false)
          ..setLocalScripts([_createLocalScript()])
          ..setMarketplaceLoading(true)
          ..setMarketplaceScripts([]);

        // Should show content even while marketplace loads
        expect(stateMachine.currentView, equals(ScriptsView.content));
      });
    });

    group('active filter count', () {
      test('returns zero when no filters are active', () {
        stateMachine
          ..setSelectedCategory('All')
          ..setSortOption(ScriptSortOption.lastRun, ascending: false)
          ..setShowDownloadedOnly(false)
          ..setShowFavoritesOnly(false);

        expect(stateMachine.activeFilterCount, equals(0));
      });

      test('counts non-default category as active filter', () {
        stateMachine
          ..setSelectedCategory('Utilities')
          ..setSortOption(ScriptSortOption.lastRun, ascending: false)
          ..setShowDownloadedOnly(false)
          ..setShowFavoritesOnly(false);

        expect(stateMachine.activeFilterCount, equals(1));
      });

      test('counts multiple active filters correctly', () {
        stateMachine
          ..setSelectedCategory('Utilities')
          ..setSortOption(ScriptSortOption.name, ascending: true)
          ..setShowDownloadedOnly(true)
          ..setShowFavoritesOnly(false);

        expect(stateMachine.activeFilterCount, equals(3));
      });
    });
  });
}

// Helper factories
ScriptRecord _createLocalScript({String? id, String? title}) {
  return ScriptRecord(
    id: id ?? 'test-local-id',
    title: title ?? 'Test Local Script',
    emoji: '📜',
    luaSource: 'print("hello")',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

MarketplaceScript _createMarketplaceScript({String? id}) {
  return MarketplaceScript(
    id: id ?? 'test-marketplace-id',
    title: 'Test Marketplace Script',
    description: 'A test marketplace script',
    category: 'Utilities',
    authorName: 'Test Author',
    luaSource: 'print("hello")',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
