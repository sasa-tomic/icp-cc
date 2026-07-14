import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

void main() {
  group('ScriptRecord version fields', () {
    test('extracts marketplace metadata', () {
      final record = ScriptRecord(
        id: 'test-id',
        title: 'Test Script',
        bundle: 'print("hello")',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'marketplace_id': 'mp-123',
          'marketplace_version': '2.0.0',
          'marketplace_author': 'Test Author',
          'sha256_checksum': 'abc123',
        },
      );

      expect(record.marketplaceId, equals('mp-123'));
      expect(record.marketplaceVersion, equals('2.0.0'));
      expect(record.marketplaceAuthor, equals('Test Author'));
      expect(record.sha256Checksum, equals('abc123'));
      expect(record.isFromMarketplace, isTrue);
    });

    test('returns null for non-marketplace scripts', () {
      final record = ScriptRecord(
        id: 'test-id',
        title: 'Local Script',
        bundle: 'print("hello")',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(record.marketplaceId, isNull);
      expect(record.marketplaceVersion, isNull);
      expect(record.marketplaceAuthor, isNull);
      expect(record.sha256Checksum, isNull);
      expect(record.isFromMarketplace, isFalse);
    });
  });

  group('MarketplaceOpenApiService version support', () {
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

    test('downloadScript calls getScriptDetails when no version specified',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            equals('https://mock.api/api/v1/scripts/script-123'));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'script-123',
              'title': 'Test Script',
              'description': 'A test',
              'category': 'Test',
              'bundle': 'print("latest")',
              'version': '2.0.0',
              'price': 0,
              'is_public': true,
              'created_at': '2025-01-01T00:00:00Z',
              'updated_at': '2025-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final source = await service.downloadScript('script-123');
      expect(source, equals('print("latest")'));
    });

    test('downloadScript calls getScriptVersion when version specified',
        () async {
      final client = MockClient((request) async {
        expect(
            request.url.toString(),
            equals(
                'https://mock.api/api/v1/scripts/script-123/versions/1.5.0'));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'script-123',
              'title': 'Test Script',
              'description': 'A test',
              'category': 'Test',
              'bundle': 'print("version 1.5.0")',
              'version': '1.5.0',
              'price': 0,
              'is_public': true,
              'created_at': '2025-01-01T00:00:00Z',
              'updated_at': '2025-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final source =
          await service.downloadScript('script-123', version: '1.5.0');
      expect(source, equals('print("version 1.5.0")'));
    });

    test('getScriptVersion throws on 404', () async {
      final client = MockClient((request) async {
        return http.Response('Not found', 404);
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      // A 404 must surface as a typed Exception carrying the version — never
      // a FormatException that masks it. Asserting the version in the message
      // pins the contract (a generic isA<Exception>() would pass for the
      // wrong error too).
      expect(
        () => service.getScriptVersion('script-123', 'nonexistent'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Script version nonexistent not found'),
        )),
      );
    });
  });

  group('MarketplaceScript version field', () {
    test('parses version from JSON', () {
      final json = {
        'id': 'script-1',
        'title': 'Test',
        'description': 'Test',
        'category': 'Test',
        'bundle': 'code',
        'version': '3.2.1',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final script = MarketplaceScript.fromJson(json);
      expect(script.version, equals('3.2.1'));
    });

    test('version is null when not provided', () {
      final json = {
        'id': 'script-2',
        'title': 'Test',
        'description': 'Test',
        'category': 'Test',
        'bundle': 'code',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final script = MarketplaceScript.fromJson(json);
      expect(script.version, isNull);
    });
  });
}
