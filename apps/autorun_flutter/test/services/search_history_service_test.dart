import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/search_history_service.dart';

void main() {
  group('SearchHistoryService', () {
    late SearchHistoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = SearchHistoryService();
    });

    tearDown(() async {
      await service.clearHistory();
    });

    group('addSearchQuery', () {
      test('should add search query to history', () async {
        await service.addSearchQuery('test query');

        final history = await service.getRecentSearches();
        expect(history.length, 1);
        expect(history.first, 'test query');
      });

      test('should handle multiple search queries', () async {
        await service.addSearchQuery('query 1');
        await service.addSearchQuery('query 2');
        await service.addSearchQuery('query 3');

        final history = await service.getRecentSearches();
        expect(history.length, 3);
        expect(history[0], 'query 3');
        expect(history[1], 'query 2');
        expect(history[2], 'query 1');
      });

      test('should return searches in reverse chronological order', () async {
        await service.addSearchQuery('first');
        await service.addSearchQuery('second');
        await service.addSearchQuery('third');

        final history = await service.getRecentSearches();
        expect(history.first, 'third');
        expect(history.last, 'first');
      });

      test('should move existing query to front when searched again', () async {
        await service.addSearchQuery('query 1');
        await service.addSearchQuery('query 2');
        await service.addSearchQuery('query 1');

        final history = await service.getRecentSearches();
        expect(history.length, 2);
        expect(history.first, 'query 1');
        expect(history.last, 'query 2');
      });

      test('should enforce max 10 items limit', () async {
        for (int i = 1; i <= 15; i++) {
          await service.addSearchQuery('query $i');
        }

        final history = await service.getRecentSearches();
        expect(history.length, 10);
        expect(history.first, 'query 15');
        expect(history.last, 'query 6');
      });

      test('should not add empty queries', () async {
        await service.addSearchQuery('');
        await service.addSearchQuery('   ');

        final history = await service.getRecentSearches();
        expect(history, isEmpty);
      });

      test('should trim whitespace from queries', () async {
        await service.addSearchQuery('  trimmed query  ');

        final history = await service.getRecentSearches();
        expect(history.first, 'trimmed query');
      });

      test('should handle case-insensitive duplicates', () async {
        await service.addSearchQuery('Test Query');
        await service.addSearchQuery('test query');

        final history = await service.getRecentSearches();
        expect(history.length, 1);
        expect(history.first, 'test query');
      });
    });

    group('getRecentSearches', () {
      test('should return empty list when no searches', () async {
        final history = await service.getRecentSearches();
        expect(history, isEmpty);
      });

      test('should return unmodifiable list', () async {
        await service.addSearchQuery('query');
        final history = await service.getRecentSearches();

        expect(() => history.add('new'), throwsUnsupportedError);
      });
    });

    group('clearHistory', () {
      test('should clear all search history', () async {
        await service.addSearchQuery('query 1');
        await service.addSearchQuery('query 2');

        await service.clearHistory();

        final history = await service.getRecentSearches();
        expect(history, isEmpty);
      });

      test('should handle clearing empty history', () async {
        await service.clearHistory();

        final history = await service.getRecentSearches();
        expect(history, isEmpty);
      });
    });

    group('removeSearchQuery', () {
      test('should remove specific search query', () async {
        await service.addSearchQuery('query 1');
        await service.addSearchQuery('query 2');
        await service.addSearchQuery('query 3');

        await service.removeSearchQuery('query 2');

        final history = await service.getRecentSearches();
        expect(history.length, 2);
        expect(history, containsAll(['query 1', 'query 3']));
        expect(history, isNot(contains('query 2')));
      });

      test('should handle removing non-existent query', () async {
        await service.addSearchQuery('query 1');

        await service.removeSearchQuery('non-existent');

        final history = await service.getRecentSearches();
        expect(history.length, 1);
      });
    });

    group('persistence', () {
      test('should persist data across service instances', () async {
        await service.addSearchQuery('persistent query');

        final newService = SearchHistoryService();
        final history = await newService.getRecentSearches();

        expect(history.length, 1);
        expect(history.first, 'persistent query');
      });
    });

    group('getSearchCount', () {
      test('should return 0 for no searches', () async {
        expect(await service.getSearchCount(), 0);
      });

      test('should return correct count for searches', () async {
        await service.addSearchQuery('query 1');
        await service.addSearchQuery('query 2');

        expect(await service.getSearchCount(), 2);
      });
    });
  });
}
