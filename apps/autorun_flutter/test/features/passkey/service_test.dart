import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:autorun_flutter/services/passkey_service.dart';

/// Unit tests for PasskeyService
/// 
/// These tests mock HTTP responses to test the service layer.
/// Integration tests with the real backend are in test/integration/.
void main() {
  late PasskeyService service;

  setUp(() {
    service = PasskeyService();
  });

  group('PasskeyService HTTP layer', () {
    test('createVault sends correct request', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/vault'));
        expect(request.method, equals('POST'));
        
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['account_id'], equals('test-account'));
        expect(body['password'], equals('StrongP@ssw0rd!'));
        
        return http.Response(
          jsonEncode({'success': true, 'data': {}}),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      await service.createVault(
        accountId: 'test-account',
        password: 'StrongP@ssw0rd!',
        data: '{}',
      );
    });

    test('getVault returns null when vault not found', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'Vault not found'}),
          404,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.getVault('test-account');
      expect(result, isNull);
    });

    test('getVault returns VaultData when found', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'encrypted_data': 'ZW5jcnlwdGVk',
              'salt': 'c2FsdA==',
              'nonce': 'bm9uY2U=',
            },
          }),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.getVault('test-account');
      expect(result, isNotNull);
      expect(result!.encryptedData, equals('ZW5jcnlwdGVk'));
      expect(result.salt, equals('c2FsdA=='));
      expect(result.nonce, equals('bm9uY2U='));
    });

    test('updateVault sends correct request', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('PUT'));
        
        return http.Response(
          jsonEncode({'success': true, 'data': {}}),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      await service.updateVault(
        accountId: 'test-account',
        password: 'StrongP@ssw0rd!',
        data: '{"key":"value"}',
      );
    });

    test('generateRecoveryCodes returns list of codes', () async {
      final mockCodes = [
        'ABCD-EFGH-IJKL',
        'MNOP-QRST-UVWX',
        'YZ12-3456-7890',
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'codes': mockCodes,
              'remaining_unused': 3,
            },
          }),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.generateRecoveryCodes('test-account');
      expect(result.codes, equals(mockCodes));
      expect(result.remainingUnused, equals(3));
    });

    test('verifyRecoveryCode returns true for valid code', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['code'], equals('ABCD-EFGH-IJKL'));
        
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'valid': true},
          }),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.verifyRecoveryCode(
        accountId: 'test-account',
        code: 'ABCD-EFGH-IJKL',
      );
      expect(result, isTrue);
    });

    test('verifyRecoveryCode returns false for invalid code', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'valid': false},
          }),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.verifyRecoveryCode(
        accountId: 'test-account',
        code: 'INVALID-CODE',
      );
      expect(result, isFalse);
    });

    test('listPasskeys returns list of passkeys', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 'pk-1',
                'device_name': 'iPhone',
                'device_type': 'platform',
                'created_at': '2024-01-01T00:00:00Z',
                'last_used_at': '2024-01-15T12:00:00Z',
              },
              {
                'id': 'pk-2',
                'device_name': 'YubiKey',
                'device_type': 'cross-platform',
                'created_at': '2024-01-02T00:00:00Z',
                'last_used_at': null,
              },
            ],
          }),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      final result = await service.listPasskeys('test-account');
      expect(result, hasLength(2));
      expect(result[0].deviceName, equals('iPhone'));
      expect(result[0].deviceType, equals('platform'));
      expect(result[1].deviceName, equals('YubiKey'));
    });

    test('deletePasskey sends correct request', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('DELETE'));
        expect(request.url.path, contains('/passkey/pk-123'));
        
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['account_id'], equals('test-account'));
        
        return http.Response(
          jsonEncode({'success': true, 'data': {}}),
          200,
        );
      });

      service.overrideHttpClient(mockClient);

      await service.deletePasskey(
        passkeyId: 'pk-123',
        accountId: 'test-account',
      );
    });

    test('throws PasskeyException on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'Unauthorized'}),
          401,
        );
      });

      service.overrideHttpClient(mockClient);

      expect(
        () => service.listPasskeys('test-account'),
        throwsA(isA<PasskeyException>()),
      );
    });

    test('throws PasskeyException on network error', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      service.overrideHttpClient(mockClient);

      expect(
        () => service.listPasskeys('test-account'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PasskeyException', () {
    test('has meaningful message', () {
      final exception = PasskeyException('Something went wrong');
      expect(exception.message, equals('Something went wrong'));
      expect(exception.toString(), contains('Something went wrong'));
    });
  });

  group('Model parsing', () {
    test('PasskeyInfo.fromJson handles all fields', () {
      final json = {
        'id': 'pk-123',
        'device_name': 'Test Device',
        'device_type': 'platform',
        'created_at': '2024-01-01T00:00:00Z',
        'last_used_at': '2024-01-15T12:00:00Z',
      };

      final info = PasskeyInfo.fromJson(json);
      expect(info.id, equals('pk-123'));
      expect(info.deviceName, equals('Test Device'));
      expect(info.deviceType, equals('platform'));
      expect(info.createdAt, equals('2024-01-01T00:00:00Z'));
      expect(info.lastUsedAt, equals('2024-01-15T12:00:00Z'));
    });

    test('PasskeyInfo.fromJson handles null fields', () {
      final json = {
        'id': 'pk-123',
        'device_name': null,
        'device_type': null,
        'created_at': '2024-01-01T00:00:00Z',
        'last_used_at': null,
      };

      final info = PasskeyInfo.fromJson(json);
      expect(info.id, equals('pk-123'));
      expect(info.deviceName, isNull);
      expect(info.deviceType, isNull);
      expect(info.lastUsedAt, isNull);
    });

    test('PasskeyRegistrationResult.fromJson parses correctly', () {
      final json = {
        'id': 'pk-new',
        'device_name': 'New Device',
        'device_type': 'platform',
        'created_at': '2024-01-01T00:00:00Z',
      };

      final result = PasskeyRegistrationResult.fromJson(json);
      expect(result.id, equals('pk-new'));
      expect(result.deviceName, equals('New Device'));
      expect(result.deviceType, equals('platform'));
      expect(result.createdAt, equals('2024-01-01T00:00:00Z'));
    });

    test('RecoveryCodesResult.fromJson parses correctly', () {
      final json = {
        'codes': ['CODE-1', 'CODE-2', 'CODE-3'],
        'remaining_unused': 3,
      };

      final result = RecoveryCodesResult.fromJson(json);
      expect(result.codes, hasLength(3));
      expect(result.codes[0], equals('CODE-1'));
      expect(result.remainingUnused, equals(3));
    });

    test('VaultData.fromJson parses correctly', () {
      final json = {
        'encrypted_data': 'ZW5jcnlwdGVk',
        'salt': 'c2FsdA==',
        'nonce': 'bm9uY2U=',
      };

      final data = VaultData.fromJson(json);
      expect(data.encryptedData, equals('ZW5jcnlwdGVk'));
      expect(data.salt, equals('c2FsdA=='));
      expect(data.nonce, equals('bm9uY2U='));
    });
  });
}
