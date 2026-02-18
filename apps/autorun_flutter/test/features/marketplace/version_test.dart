import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

void main() {
  group('ScriptVersion', () {
    test('parses version from JSON', () {
      final json = {
        'version': '2.1.0',
        'changelog': 'Added new features',
        'created_at': '2025-01-15T10:00:00Z',
        'downloads': 150,
        'is_latest': true,
      };

      final version = ScriptVersion.fromJson(json);

      expect(version.version, equals('2.1.0'));
      expect(version.changelog, equals('Added new features'));
      expect(version.downloads, equals(150));
      expect(version.isLatest, isTrue);
    });

    test('handles missing optional fields', () {
      final json = {'version': '1.0.0'};

      final version = ScriptVersion.fromJson(json);

      expect(version.version, equals('1.0.0'));
      expect(version.changelog, isNull);
      expect(version.downloads, equals(0));
      expect(version.isLatest, isFalse);
    });

    test('converts to JSON', () {
      final version = ScriptVersion(
        version: '3.0.0',
        changelog: 'Major update',
        createdAt: DateTime.parse('2025-02-01T00:00:00Z'),
        downloads: 500,
        isLatest: true,
      );

      final json = version.toJson();

      expect(json['version'], equals('3.0.0'));
      expect(json['changelog'], equals('Major update'));
      expect(json['downloads'], equals(500));
      expect(json['isLatest'], isTrue);
    });
  });

  group('ScriptRecord version fields', () {
    test('extracts marketplace metadata', () {
      final record = ScriptRecord(
        id: 'test-id',
        title: 'Test Script',
        luaSource: 'print("hello")',
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
        luaSource: 'print("hello")',
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
              'lua_source': 'print("latest")',
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
              'lua_source': 'print("version 1.5.0")',
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

      expect(
        () => service.getScriptVersion('script-123', 'nonexistent'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Script version nonexistent not found'),
        )),
      );
    });

    test('getScriptVersions returns parsed versions', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            equals('https://mock.api/api/v1/scripts/script-123/versions'));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'version': '2.0.0',
                'changelog': 'Major release',
                'created_at': '2025-02-01T00:00:00Z',
                'downloads': 100,
                'is_latest': true,
              },
              {
                'version': '1.5.0',
                'changelog': 'Bug fixes',
                'created_at': '2025-01-15T00:00:00Z',
                'downloads': 250,
                'is_latest': false,
              },
              {
                'version': '1.0.0',
                'changelog': 'Initial release',
                'created_at': '2025-01-01T00:00:00Z',
                'downloads': 500,
                'is_latest': false,
              },
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final versions = await service.getScriptVersions('script-123');

      expect(versions.length, equals(3));
      expect(versions[0].version, equals('2.0.0'));
      expect(versions[0].isLatest, isTrue);
      expect(versions[1].version, equals('1.5.0'));
      expect(versions[2].version, equals('1.0.0'));
      expect(versions[2].downloads, equals(500));
    });

    test('getScriptVersions returns empty list on 404', () async {
      final client = MockClient((request) async {
        return http.Response('Not found', 404);
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final versions = await service.getScriptVersions('nonexistent');
      expect(versions, isEmpty);
    });

    test('getScriptVersions throws on server error', () async {
      final client = MockClient((request) async {
        return http.Response('Server error', 500);
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.getScriptVersions('script-123'),
        throwsA(isA<Exception>()),
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
        'lua_source': 'code',
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
        'lua_source': 'code',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final script = MarketplaceScript.fromJson(json);
      expect(script.version, isNull);
    });
  });
}
