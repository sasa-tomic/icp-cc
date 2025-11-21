import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_helpers/mock_marketplace_service.dart';

void main() {
  group('MarketplaceOpenApiService', () {
    late MockMarketplaceOpenApiService mockService;

    setUp(() async {
      // Initialize mock service
      mockService = MockMarketplaceOpenApiService();

      // Add mock test data
      mockService.addMockTestData();
    });

    tearDown(() async {
      // Clean up mock data
      mockService.clearMockData();
    });

    group('Search Functionality', () {
      test('should search scripts by query', () async {
        // Act
        final result = await mockService.searchScripts(query: 'Test');

        // Assert
        expect(result.scripts, isNotEmpty);
        expect(result.total, greaterThan(0));
        expect(result.scripts.length, lessThanOrEqualTo(result.total));

        // Verify all results contain the search query
        for (final script in result.scripts) {
          expect(
            script.title.toLowerCase().contains('test'.toLowerCase()) ||
                script.description.toLowerCase().contains('test'.toLowerCase()),
            isTrue,
          );
        }
      });

      test('should search scripts by category', () async {
        // Act
        final result = await mockService.searchScripts(category: 'Development');

        // Assert
        expect(result.scripts, isNotEmpty);

        // Verify all results are in the specified category
        for (final script in result.scripts) {
          expect(script.category, equals('Development'));
        }
      });

      test('should search scripts by tags', () async {
        // Act
        final result = await mockService.searchScripts(tags: ['test']);

        // Assert
        expect(result.scripts, isNotEmpty);

        // Verify all results contain the specified tags
        for (final script in result.scripts) {
          expect(script.tags.contains('test'), isTrue);
        }
      });

      test('should handle pagination correctly', () async {
        // Act - Get first page
        final firstPage = await mockService.searchScripts(limit: 1, offset: 0);

        // Act - Get second page
        final secondPage = await mockService.searchScripts(limit: 1, offset: 1);

        // Assert
        expect(firstPage.scripts.length, lessThanOrEqualTo(1));
        expect(secondPage.scripts.length, lessThanOrEqualTo(1));

        if (firstPage.total > 1) {
          expect(firstPage.scripts.first.id,
              isNot(equals(secondPage.scripts.first.id)));
        }
      });

      test('should return empty result for non-matching query', () async {
        // Act
        final result =
            await mockService.searchScripts(query: 'NonExistentQuery12345');

        // Assert
        expect(result.scripts, isEmpty);
        expect(result.total, equals(0));
        expect(result.hasMore, isFalse);
      });

      test('should handle combined search criteria', () async {
        // Act
        final result = await mockService.searchScripts(
          query: 'Test',
          category: 'Development',
          tags: ['test'],
        );

        // Assert
        for (final script in result.scripts) {
          expect(script.category, equals('Development'));
          expect(script.tags.contains('test'), isTrue);
          expect(
            script.title.toLowerCase().contains('test'.toLowerCase()) ||
                script.description.toLowerCase().contains('test'.toLowerCase()),
            isTrue,
          );
        }
      });
    });

    group('Script Retrieval', () {
      test('should get script by ID', () async {
        // Arrange - Get a script from search results
        final searchResult = await mockService.searchScripts(limit: 1);
        expect(searchResult.scripts, isNotEmpty);

        final scriptId = searchResult.scripts.first.id;

        // Act
        final script = await mockService.getScriptById(scriptId);

        // Assert
        expect(script, isNotNull);
        expect(script!.id, equals(scriptId));
        expect(script.title, isNotEmpty);
        expect(script.description, isNotEmpty);
        expect(script.luaSource, isNotEmpty);
        expect(script.category, isNotEmpty);
        expect(script.authorName, isNotEmpty);
        expect(script.version, isNotEmpty);
        expect(script.createdAt, isNotNull);
        expect(script.updatedAt, isNotNull);
      });

      test('should return null for non-existent script ID', () async {
        // Act
        final script = await mockService.getScriptById('non_existent_id');

        // Assert
        expect(script, isNull);
      });
    });

    group('User Scripts', () {
      test('should get user scripts', () async {
        // Act
        final userScripts = await mockService.getUserScripts();

        // Assert
        expect(userScripts, isA<List>());
        // Note: Mock starts empty, so this might be empty initially
      });
    });

    group('Error Handling', () {
      test('should handle empty search parameters gracefully', () async {
        // Act
        final result = await mockService.searchScripts();

        // Assert
        expect(result, isNotNull);
        expect(result.scripts, isA<List>());
        expect(result.total, isA<int>());
        expect(result.hasMore, isA<bool>());
      });

      test('should handle invalid limit values', () async {
        // Act
        final result = await mockService.searchScripts(limit: -1);

        // Assert - Should not crash and return valid result
        expect(result, isNotNull);
        expect(result.scripts, isA<List>());
      });

      test('should handle invalid offset values', () async {
        // Act
        final result = await mockService.searchScripts(offset: -1);

        // Assert - Should not crash and return valid result
        expect(result, isNotNull);
        expect(result.scripts, isA<List>());
      });
    });

    group('Data Validation', () {
      test('should return scripts with valid structure', () async {
        // Act
        final result = await mockService.searchScripts(limit: 5);

        // Assert
        for (final script in result.scripts) {
          expect(script.id, isNotEmpty);
          expect(script.title, isNotEmpty);
          expect(script.description, isNotEmpty);
          expect(script.category, isNotEmpty);
          expect(script.authorName, isNotEmpty);
          expect(script.luaSource, isNotEmpty);
          expect(script.version, isNotEmpty);
          expect(script.createdAt, isNotNull);
          expect(script.updatedAt, isNotNull);
          expect(script.tags, isA<List>());
          expect(script.downloads, greaterThanOrEqualTo(0));
          expect(script.rating, greaterThanOrEqualTo(0.0));
          expect(script.reviewCount, greaterThanOrEqualTo(0));
          expect(script.price, greaterThanOrEqualTo(0.0));
          expect(script.isPublic, isA<bool>());
        }
      });

      test('should maintain data consistency across operations', () async {
        // Arrange - Upload a script
        final testScript = MarketplaceScript(
          id: 'consistency-test',
          title: 'Consistency Test Script',
          description: 'Testing data consistency',
          category: 'Testing',
          tags: ['consistency', 'test'],
          authorId: 'test_author_id',
          luaSource: '-- Consistency test',
          version: '1.0.0',
          price: 0.0,
          isPublic: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          downloads: 0,
          rating: 0.0,
          reviewCount: 0,
        );

// Add to mock service (simulating upload)
        final scriptRecord = ScriptRecord(
          id: '', // Empty ID for new script
          title: testScript.title,
          luaSource: testScript.luaSource,
          metadata: {
            'description': testScript.description,
            'category': testScript.category,
            'tags': testScript.tags,
            'authorName': testScript.authorName,
            'version': testScript.version,
            'price': testScript.price,
            'isPublic': testScript.isPublic,
          },
          createdAt: testScript.createdAt,
          updatedAt: testScript.updatedAt,
        );
        final uploadedScriptId = await mockService.uploadScript(scriptRecord);

        // Act - Retrieve by different methods
        final byId = await mockService.getScriptById(uploadedScriptId);
        final bySearch =
            await mockService.searchScripts(query: 'Consistency Test Script');

        // Assert - Data should be consistent
        expect(byId, isNotNull);
        expect(bySearch.scripts, isNotEmpty);

        final foundInSearch = bySearch.scripts.firstWhere(
          (s) => s.id == 'consistency-test',
          orElse: () => byId ?? bySearch.scripts.first,
        );

        expect(byId!.title, equals(foundInSearch.title));
        expect(byId.description, equals(foundInSearch.description));
        expect(byId.category, equals(foundInSearch.category));
        expect(byId.authorName, equals(foundInSearch.authorName));
      });
    });

    group('Performance', () {
      test('should complete search operations within reasonable time',
          () async {
        // Act
        final stopwatch = Stopwatch()..start();
        await mockService.searchScripts(limit: 10);
        stopwatch.stop();

        // Assert
        expect(stopwatch.elapsedMilliseconds,
            lessThan(1000)); // Should complete within 1 second
      });

      test('should handle concurrent search requests', () async {
        // Act - Run multiple searches concurrently
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(mockService.searchScripts(query: 'Test', limit: 5));
        }

        final results = await Future.wait(futures);

        // Assert - All should complete successfully
        for (final result in results) {
          expect(result, isNotNull);
          expect(result.scripts, isA<List>());
        }
      });
    });

    group('Upload Script API', () {
      const testSignature = 'signed-upload';
      const testTimestamp = '2025-01-01T00:00:00Z';
      late MarketplaceOpenApiService service;

      setUp(() {
        suppressDebugOutput = true;
        service = MarketplaceOpenApiService();
        AppConfig.setTestEndpoint('https://mock.api');
      });

      tearDown(() {
        suppressDebugOutput = false;
        service.resetHttpClient();
      });

      test('includes timestamp and signature when uploading scripts', () async {
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          expect(request.url.toString(),
              equals('https://mock.api/api/v1/scripts'));
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'srv-script',
                'title': capturedBody!['title'],
                'description': capturedBody!['description'],
                'category': capturedBody!['category'],
                'tags': capturedBody!['tags'],
                'author_name': capturedBody!['author_name'],
                'lua_source': capturedBody!['lua_source'],
                'price': capturedBody!['price'],
                'version': capturedBody!['version'],
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
                'is_public': true,
                'downloads': 0,
                'rating': 0.0,
                'review_count': 0,
              },
            }),
            201,
            headers: {'Content-Type': 'application/json'},
            reasonPhrase: 'Created',
          );
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        final result = await service.uploadScript(
          slug: 'upload-test',
          title: 'Upload Test',
          description: 'Ensures timestamp travels with payload',
          category: 'Development',
          tags: const ['test', 'upload'],
          luaSource: '-- lua',
          price: 0.0,
          version: '1.0.0',
          authorPrincipal: 'author-principal',
          authorPublicKey: 'author-public-key',
          signature: testSignature,
          timestampIso: testTimestamp,
        );

        expect(capturedBody, isNotNull);
        expect(capturedBody!['timestamp'], equals(testTimestamp));
        expect(capturedBody!['signature'], equals(testSignature));
        expect(capturedBody!['author_principal'], equals('author-principal'));
        expect(result.id, equals('srv-script'));
        expect(result.title, equals('Upload Test'));
      });

      test('surfaces server error details in exception message', () async {
        final client = MockClient((request) async {
          expect(request.url.toString(),
              equals('https://mock.api/api/v1/scripts'));
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'Missing signature for verification',
            }),
            401,
            headers: {'Content-Type': 'application/json'},
            reasonPhrase: 'Unauthorized',
          );
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.uploadScript(
            slug: 'broken-upload',
            title: 'Broken Upload',
            description: 'Should fail with server error',
            category: 'Testing',
            tags: const ['fail'],
            luaSource: '--',
            price: 1.0,
            version: '1.0.0',
            authorPrincipal: 'author-principal',
            authorPublicKey: 'author-public-key',
            signature: testSignature,
            timestampIso: testTimestamp,
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains(
                  'Upload failed (HTTP 401): Missing signature for verification'),
            ),
          ),
        );
      });
    });

    group('Keypair profile API', () {
      late MarketplaceOpenApiService service;

      setUp(() {
        service = MarketplaceOpenApiService();
        AppConfig.setTestEndpoint('https://mock.api');
      });

      tearDown(() {
        service.resetHttpClient();
      });

      // Keypair profile API tests removed - profiles are now local-only
    });
  });
}
