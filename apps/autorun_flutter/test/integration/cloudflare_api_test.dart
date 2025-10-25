import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

void main() {
  group('Cloudflare Workers API Integration Tests', () {
    late MarketplaceOpenApiService apiService;

    setUpAll(() {
      // Configure for local Cloudflare Workers testing
      AppConfig.debugPrintConfig();
      apiService = MarketplaceOpenApiService();
    });

    test('should get marketplace stats from Cloudflare Workers', () async {
      try {
        final stats = await apiService.getMarketplaceStats();
        print('Marketplace stats: $stats');
        expect(stats.totalScripts, greaterThanOrEqualTo(0));
      } catch (e) {
        fail('Failed to get marketplace stats: $e');
      }
    });

    test('should search scripts from Cloudflare Workers', () async {
      try {
        final result = await apiService.searchScripts(
          query: 'test',
          limit: 5,
        );
        print('Search results: ${result.scripts.length} scripts found');
        expect(result.scripts, isA<List>());
      } catch (e) {
        fail('Failed to search scripts: $e');
      }
    });

    test('should get featured scripts from Cloudflare Workers', () async {
      try {
        final scripts = await apiService.getFeaturedScripts(limit: 5);
        print('Featured scripts: ${scripts.length} scripts found');
        expect(scripts, isA<List>());
      } catch (e) {
        fail('Failed to get featured scripts: $e');
      }
    });

    test('should get trending scripts from Cloudflare Workers', () async {
      try {
        final scripts = await apiService.getTrendingScripts(limit: 5);
        print('Trending scripts: ${scripts.length} scripts found');
        expect(scripts, isA<List>());
      } catch (e) {
        fail('Failed to get trending scripts: $e');
      }
    });

    test('should validate script using Cloudflare Workers', () async {
      try {
        final result = await apiService.validateScript('print("Hello World")');
        print('Validation result: ${result.isValid}');
        expect(result.isValid, isTrue);
      } catch (e) {
        fail('Failed to validate script: $e');
      }
    });
  });
}