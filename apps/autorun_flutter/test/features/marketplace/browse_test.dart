import 'package:flutter_test/flutter_test.dart';
import 'package:autorun_flutter/services/marketplace_open_api_service.dart';
import 'package:autorun_flutter/models/marketplace_script.dart';

import '../shared/test_helpers.dart';

/// E2E test: User can browse marketplace scripts
/// 
/// This test covers the complete user flow for discovering scripts:
/// 1. Search scripts by query
/// 2. Filter by category
/// 3. Sort results
/// 4. View script details
void main() {
  late MarketplaceOpenApiService service;

  setUpAll(() async {
    service = await ApiServiceManager.createTestService();
  });

  group('browse marketplace scripts', () {
    test('user can search scripts by query', () async {
      final result = await service.searchScripts(
        query: 'nns',
        limit: 10,
      );

      expect(result, isNotNull);
      expect(result.scripts, isA<List<MarketplaceScript>>());
      
      // Verify search results contain the query term
      for (final script in result.scripts) {
        final matchesQuery = 
          script.title.toLowerCase().contains('nns') ||
          script.description.toLowerCase().contains('nns');
        expect(matchesQuery, isTrue, 
          reason: 'Script "${script.title}" should match query "nns"');
      }
    });

    test('user can filter scripts by category', () async {
      final result = await service.searchScripts(
        category: 'Finance',
        limit: 10,
      );

      expect(result, isNotNull);
      for (final script in result.scripts) {
        expect(script.category, equals('Finance'),
          reason: 'Script "${script.title}" should be in Finance category');
      }
    });

    test('user can sort scripts by rating', () async {
      final result = await service.searchScripts(
        sortBy: 'rating',
        sortOrder: 'desc',
        limit: 10,
      );

      expect(result, isNotNull);
      final ratings = result.scripts.map((s) => s.rating).toList();
      
      // Verify descending order
      for (int i = 1; i < ratings.length; i++) {
        expect(ratings[i], lessThanOrEqualTo(ratings[i - 1]),
          reason: 'Scripts should be sorted by rating descending');
      }
    });

    test('user can get featured scripts', () async {
      final featured = await service.getFeaturedScripts();

      expect(featured, isA<List<MarketplaceScript>>());
      expect(featured.length, lessThanOrEqualTo(10),
        reason: 'Featured scripts should be limited');
    });

    test('user can get script details by id', () async {
      // First get a script from search
      final searchResult = await service.searchScripts(limit: 1);
      assumeTrue(searchResult.scripts.isNotEmpty, 'Need at least one script');
      
      final scriptId = searchResult.scripts.first.id;
      final details = await service.getScriptDetails(scriptId);

      expect(details, isNotNull);
      expect(details.id, equals(scriptId));
      expect(details.title, isNotEmpty);
      expect(details.luaSource, isNotEmpty,
        reason: 'Script details should include source code');
    });
  });
}
