import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Marketplace 404 Error Handling', () {
    setUpAll(() async {
      // Configure test environment (assumes wrangler is running externally)
      await WranglerManager.initialize();
    });

    tearDownAll(() async {
      // Cleanup test configuration
      await WranglerManager.cleanup();
    });
    test('should handle HTTP 404 gracefully when opening Marketplace', () async {
      final service = MarketplaceOpenApiService();

      try {
        // This should fail with HTTP 404 when API server is not deployed
        await service.getMarketplaceStats();
        fail('Expected an HTTP 404 error but got a successful response');
      } catch (e) {
        // Should handle the 404 error gracefully
        expect(e, isA<Exception>());
        expect(e.toString(), contains('HTTP 404'));
      }
    });

    test('should handle HTTP 404 for script search', () async {
      final service = MarketplaceOpenApiService();

      try {
        // This should fail with HTTP 404 when API server is not deployed
        await service.searchScripts();
        fail('Expected an HTTP 404 error but got a successful response');
      } catch (e) {
        // Should handle the 404 error gracefully
        expect(e, isA<Exception>());
        expect(e.toString(), contains('HTTP 404'));
      }
    });

    test('should handle HTTP 404 for featured scripts', () async {
      final service = MarketplaceOpenApiService();

      try {
        // This should fail with HTTP 404 when API server is not deployed
        await service.getFeaturedScripts();
        fail('Expected an HTTP 404 error but got a successful response');
      } catch (e) {
        // Should handle the 404 error gracefully
        expect(e, isA<Exception>());
        expect(e.toString(), contains('HTTP 404'));
      }
    });

    test('should provide user-friendly error message for 404', () async {
      final service = MarketplaceOpenApiService();

      try {
        await service.getMarketplaceStats();
        fail('Expected an HTTP 404 error but got a successful response');
      } catch (e) {
        // The error should be user-friendly and mention marketplace availability
        expect(e.toString(), anyOf([
          contains('HTTP 404'),
          contains('Not Found'),
          contains('marketplace'),
        ]));
      }
    });
  });
}