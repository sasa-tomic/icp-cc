import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Real-service tests for [MarketplaceOpenApiService].
///
/// An earlier version of this file also held ~13 "Search / Retrieval /
/// Performance" groups that drove a standalone in-memory re-implementation
/// (`MockMarketplaceOpenApiService`) and asserted on *its* behaviour — the
/// Wave-4 mock-the-mock antipattern (the test encodes expected behaviour into
/// the mock, then asserts the mock reproduces it; a real `fromJson` / URL /
/// error regression ships green). Those groups were removed because they added
/// zero signal about the real service. Every assertion below drives the real
/// [MarketplaceOpenApiService] through a boundary [MockClient].
void main() {
  group('MarketplaceOpenApiService', () {
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
                'bundle': capturedBody!['bundle'],
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
          bundle: 'globalThis.init=()=>({state:{},effects:[]});',
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
        expect(capturedBody!['bundle'], isNotEmpty);
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
            bundle: 'globalThis.init=()=>({});',
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

    group('Fail-fast error handling', () {
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

      test('getFeaturedScripts throws on HTTP error', () async {
        final client = MockClient((request) async {
          return http.Response('Server error', 500,
              reasonPhrase: 'Internal Server Error');
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.getFeaturedScripts(),
          throwsA(isA<Exception>()),
        );
      });

      test('getTrendingScripts throws on HTTP error', () async {
        final client = MockClient((request) async {
          return http.Response('Server error', 503,
              reasonPhrase: 'Service Unavailable');
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.getTrendingScripts(),
          throwsA(isA<Exception>()),
        );
      });

      test('getMarketplaceStats throws on HTTP error', () async {
        final client = MockClient((request) async {
          return http.Response('Server error', 502,
              reasonPhrase: 'Bad Gateway');
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.getMarketplaceStats(),
          throwsA(isA<Exception>()),
        );
      });

      test('searchScripts throws on connection failure', () async {
        final client = MockClient((request) async {
          throw Exception('Connection refused');
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.searchScripts(),
          throwsA(isA<Exception>()),
        );
      });

      test('getFeaturedScripts throws on API error response', () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'success': false, 'error': 'Database unavailable'}),
            200,
          );
        });
        service.overrideHttpClient(client);
        addTearDown(client.close);

        expect(
          () => service.getFeaturedScripts(),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message',
              contains('Database unavailable'))),
        );
      });
    });
  });
}
