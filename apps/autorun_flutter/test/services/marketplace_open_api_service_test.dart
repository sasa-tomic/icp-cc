import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('MarketplaceOpenApiService', () {
    late MarketplaceOpenApiService service;
    late bool hasRealMarketplace;

    setUpAll(() async {
      // Configure test environment (assumes wrangler is running externally)
      await WranglerManager.initialize();
      
      // Suppress debug output during tests to avoid confusing messages
      suppressDebugOutput = true;

      // Check if we have a real marketplace instance available
      // Use a simple search with a timeout to detect connectivity
      service = MarketplaceOpenApiService();
      try {
        await service.searchScripts(query: 'test', limit: 1)
            .timeout(Duration(seconds: 5));
        hasRealMarketplace = true;
      } catch (e) {
        hasRealMarketplace = false;
      }
    });

    tearDownAll(() async {
      // Re-enable debug output after tests
      suppressDebugOutput = false;
      
      // Cleanup test configuration
      await WranglerManager.cleanup();
    });

    setUp(() {
      service = MarketplaceOpenApiService();
    });

    test('should validate canister ID format via search method', () {
      // Test canister ID validation through the public search method
      // Invalid canister IDs should throw exceptions
      expect(
        () => service.searchScriptsByCanisterId('invalid-id'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => service.searchScriptsByCanisterId('RRKAH-FQAAA-AAAAA-AAAAQ-CAI'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => service.searchScriptsByCanisterId(''),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle connection errors gracefully for valid canister IDs', () async {
      // Test that valid canister IDs are formatted correctly but connection errors are handled
      try {
        await service.searchScriptsByCanisterId('rrkah-fqaaa-aaaaa-aaaaq-cai');
        // If this succeeds, the marketplace is available and working correctly
        if (!hasRealMarketplace) {
          fail('Expected marketplace to be unavailable, but search succeeded');
        }
      } catch (e) {
        if (hasRealMarketplace) {
          // If we detected a real marketplace, this should not fail
          fail('Marketplace was detected as available but search failed: $e');
        } else {
          expect(e, isA<Exception>());
          // Should fail with a meaningful error about connectivity or server issues
          expect(e.toString(), anyOf([
            contains('Connection refused'),
            contains('Connection error'),
            contains('Network is unreachable'),
            contains('No address associated with hostname'),
            contains('Connection timeout'),
            contains('HTTP'),
          ]));
        }
      }
    });

    test('should return correct categories list', () {
      final categories = service.getCategories();

      expect(categories, contains('All'));
      expect(categories, contains('Gaming'));
      expect(categories, contains('Finance'));
      expect(categories, contains('DeFi'));
      expect(categories, contains('NFT'));
      expect(categories, contains('Social'));
      expect(categories, contains('Utilities'));
      expect(categories, contains('Development'));
      expect(categories, contains('Education'));
      expect(categories, contains('Entertainment'));
      expect(categories, contains('Business'));
      expect(categories.length, equals(11));
    });

    test('should handle marketplace stats correctly', () async {
      final stats = await service.getMarketplaceStats();

      // Should either return real data or fallback defaults
      expect(stats.totalScripts, isA<int>());
      expect(stats.totalAuthors, isA<int>());
      expect(stats.totalDownloads, isA<int>());
      expect(stats.averageRating, isA<double>());

      // Stats should be non-negative
      expect(stats.totalScripts, greaterThanOrEqualTo(0));
      expect(stats.totalAuthors, greaterThanOrEqualTo(0));
      expect(stats.totalDownloads, greaterThanOrEqualTo(0));
      expect(stats.averageRating, greaterThanOrEqualTo(0.0));
    });

    test('should handle script validation correctly', () async {
      final result = await service.validateScript('function test() unclosed brace {');

      expect(result.isValid, isFalse);
      expect(result.errors, isA<List<String>>());
      expect(result.errors.isNotEmpty, isTrue);
      expect(result.warnings, isA<List<String>>());
    });

    group('Search functionality', () {
      test('should handle search without query (get all scripts)', () async {
        // Test that searching with null or empty query returns all scripts
        try {
          final result = await service.searchScripts(query: null);
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should handle search with empty string query', () async {
        try {
          final result = await service.searchScripts(query: '');
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should handle search with query string', () async {
        try {
          final result = await service.searchScripts(
            query: 'gaming',
            limit: 10,
            offset: 0,
          );
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
          expect(result.limit, equals(10));
          expect(result.offset, equals(0));
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should handle search with canister ID filter', () async {
        try {
          final result = await service.searchScripts(
            canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
            limit: 5,
          );
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should handle search with category filter', () async {
        try {
          final result = await service.searchScripts(
            category: 'Gaming',
            sortBy: 'rating',
            sortOrder: 'desc',
          );
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should handle search with all filters combined', () async {
        try {
          final result = await service.searchScripts(
            query: 'script',
            category: 'Utilities',
            minRating: 3.0,
            maxPrice: 10.0,
            canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
            sortBy: 'createdAt',
            sortOrder: 'desc',
            limit: 20,
            offset: 0,
          );
          expect(result.scripts, isA<List<MarketplaceScript>>());
          expect(result.total, isA<int>());
          expect(result.hasMore, isA<bool>());
        } catch (e) {
          if (hasRealMarketplace) {
            fail('Search failed despite marketplace being available: $e');
          } else {
            // Expected to fail when no marketplace is available
            expect(e, isA<Exception>());
          }
        }
      });

      test('should validate search parameters without making HTTP calls', () {
        // Test that search method accepts various parameter combinations
        // Parameters are validated server-side, client should not crash on valid input
        expect(() => service.searchScripts, returnsNormally);
        expect(MarketplaceOpenApiService.defaultSearchLimit, equals(20));
      });
    });
  });

  group('MarketplaceScript Model', () {
    test('should create script from JSON correctly', () {
      final json = {
        '\$id': 'script123',
        'title': 'Test Script',
        'description': 'A test Lua script',
        'category': 'Gaming',
        'tags': ['test', 'gaming'],
        'authorName': 'Test Author',
        'authorId': 'author123',
        'downloads': 100,
        'rating': 4.5,
        'reviewCount': 10,
        'price': 0.0,
        'luaSource': 'print("Hello, ICP!")',
        'iconUrl': 'https://example.com/icon.png',
        'screenshots': ['https://example.com/screenshot1.png'],
        'canisterIds': ['rrkah-fqaaa-aaaaa-aaaaq-cai'],
        'isPublic': true,
        'createdAt': '2024-01-01T00:00:00Z',
        'version': '1.0.0',
        'compatibility': 'ICP v1.0+',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.id, equals('script123'));
      expect(script.title, equals('Test Script'));
      expect(script.description, equals('A test Lua script'));
      expect(script.category, equals('Gaming'));
      expect(script.tags, equals(['test', 'gaming']));
      expect(script.authorName, equals('Test Author'));
      expect(script.authorId, equals('author123'));
      expect(script.downloads, equals(100));
      expect(script.rating, equals(4.5));
      expect(script.reviewCount, equals(10));
      expect(script.price, equals(0.0));
      expect(script.luaSource, equals('print("Hello, ICP!")'));
      expect(script.iconUrl, equals('https://example.com/icon.png'));
      expect(script.screenshots, equals(['https://example.com/screenshot1.png']));
      expect(script.canisterIds, equals(['rrkah-fqaaa-aaaaa-aaaaq-cai']));
      expect(script.isPublic, isTrue);
      expect(script.version, equals('1.0.0'));
      expect(script.compatibility, equals('ICP v1.0+'));
    });

    test('should handle missing optional fields gracefully', () {
      final json = {
        '\$id': 'script123',
        'title': 'Test Script',
        'description': 'A test Lua script',
        'category': 'Gaming',
        'authorName': 'Test Author',
        'authorId': 'author123',
        'luaSource': 'print("Hello, ICP!")',
        'isPublic': true,
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.id, equals('script123'));
      expect(script.title, equals('Test Script'));
      expect(script.tags, isEmpty);
      expect(script.downloads, equals(0));
      expect(script.rating, equals(0.0));
      expect(script.reviewCount, equals(0));
      expect(script.price, equals(0.0));
      expect(script.iconUrl ?? '', isEmpty);
      expect(script.screenshots ?? [], isEmpty);
      expect(script.canisterIds, isEmpty);
      expect(script.version ?? '', isEmpty);
      expect(script.compatibility ?? '', isEmpty);
    });
  });

  group('MarketplaceStats Model', () {
    test('should create stats from JSON correctly', () {
      final json = <String, dynamic>{
        'total_scripts': 150,
        'total_authors': 25,
        'total_downloads': 5000,
        'average_rating': 4.2,
      };

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(150));
      expect(stats.totalAuthors, equals(25));
      expect(stats.totalDownloads, equals(5000));
      expect(stats.averageRating, equals(4.2));
    });

    test('should handle missing fields with defaults', () {
      final json = <String, dynamic>{};

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(0));
      expect(stats.totalAuthors, equals(0));
      expect(stats.totalDownloads, equals(0));
      expect(stats.averageRating, equals(0.0));
    });
  });

  group('ScriptValidationResult Model', () {
    test('should create validation result from JSON correctly', () {
      final json = <String, dynamic>{
        'is_valid': false,
        'errors': ['Unexpected symbol near "invalid"'],
        'warnings': ['Unused variable "test"'],
      };

      final result = ScriptValidationResult.fromJson(json);

      expect(result.isValid, isFalse);
      expect(result.errors, equals(['Unexpected symbol near "invalid"']));
      expect(result.warnings, equals(['Unused variable "test"']));
    });

    test('should handle missing fields with defaults', () {
      final json = <String, dynamic>{};

      final result = ScriptValidationResult.fromJson(json);

      expect(result.isValid, isFalse);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });
}