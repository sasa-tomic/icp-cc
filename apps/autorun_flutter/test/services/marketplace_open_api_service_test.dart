import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

import 'marketplace_open_api_service_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  group('MarketplaceOpenApiService', () {
    late MarketplaceOpenApiService service;
    late MockClient mockClient;

    setUp(() {
      service = MarketplaceOpenApiService();
      mockClient = MockClient();
    });

    test('should validate canister ID format correctly', () {
      // Valid canister IDs
      expect(service._isValidCanisterId('rrkah-fqaaa-aaaaa-aaaaq-cai'), isTrue);
      expect(service._isValidCanisterId('be2us-64aaa-aaaaa-qaabq-cai'), isTrue);

      // Invalid canister IDs
      expect(service._isValidCanisterId('invalid-id'), isFalse);
      expect(service._isValidCanisterId('RRKAH-FQAAA-AAAAA-AAAAQ-CAI'), isFalse); // Uppercase
      expect(service._isValidCanisterId(''), isFalse);
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

    test('should handle empty marketplace stats gracefully', () async {
      // Test would need mocking of HTTP client
      // For now, just test the fallback behavior
      final stats = await service.getMarketplaceStats();

      expect(stats.totalScripts, equals(0));
      expect(stats.totalAuthors, equals(0));
      expect(stats.totalDownloads, equals(0));
      expect(stats.averageRating, equals(0.0));
    });

    test('should handle script validation errors correctly', () async {
      // Test would need mocking of HTTP client
      final result = await service.validateScript('invalid lua syntax here');

      expect(result.isValid, isFalse);
      expect(result.errors.isNotEmpty, isTrue);
    });

    test('should throw exception for invalid canister ID in search', () async {
      expect(
        () => service.searchScriptsByCanisterId('invalid-id'),
        throwsA(isA<Exception>()),
      );
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
        'isApproved': true,
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
      expect(script.isApproved, isTrue);
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
        'isApproved': true,
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.id, equals('script123'));
      expect(script.title, equals('Test Script'));
      expect(script.tags, isEmpty);
      expect(script.downloads, equals(0));
      expect(script.rating, equals(0.0));
      expect(script.reviewCount, equals(0));
      expect(script.price, equals(0.0));
      expect(script.iconUrl, isEmpty);
      expect(script.screenshots, isEmpty);
      expect(script.canisterIds, isEmpty);
      expect(script.version, isEmpty);
      expect(script.compatibility, isEmpty);
    });
  });

  group('MarketplaceStats Model', () {
    test('should create stats from JSON correctly', () {
      final json = {
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
      final json = {};

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(0));
      expect(stats.totalAuthors, equals(0));
      expect(stats.totalDownloads, equals(0));
      expect(stats.averageRating, equals(0.0));
    });
  });

  group('ScriptValidationResult Model', () {
    test('should create validation result from JSON correctly', () {
      final json = {
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
      final json = {};

      final result = ScriptValidationResult.fromJson(json);

      expect(result.isValid, isFalse);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });
}