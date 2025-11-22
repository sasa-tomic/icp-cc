import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import '../test_helpers/test_keypair_factory.dart';

void main() {
  // Initialize secure storage mock for tests
  FlutterSecureStorage.setMockInitialValues({});

  group('AccountController - Remove Public Key', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('successfully removes public key from account', () async {
      final signingKeypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'testuser';
      final keyToRemove = 'key-2';

      final mockClient = MockClient((request) async {
        if (request.url.path
                .contains('/api/v1/accounts/$username/keys/$keyToRemove') &&
            request.method == 'DELETE') {
          // Mock successful key removal - return the disabled key
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': keyToRemove,
                'public_key': 'cmVtb3ZlZA==',
                'ic_principal': 'removed-principal-aa',
                'is_active': false,
                'added_at': DateTime.now().toIso8601String(),
                'disabled_at': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        // Mock account fetch after removal
        if (request.url.path.endsWith('/api/v1/accounts/$username')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-123',
                'username': username,
                'display_name': 'Test User',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'public_key': signingKeypair.publicKey,
                    'ic_principal': 'signing-principal-aa',
                    'is_active': true,
                    'added_at': DateTime.now().toIso8601String(),
                  },
                  {
                    'id': 'key-2',
                    'public_key': 'cmVtb3ZlZA==',
                    'ic_principal': 'removed-principal-aa',
                    'is_active': false,
                    'added_at': DateTime.now().toIso8601String(),
                    'disabled_at': DateTime.now().toIso8601String(),
                  }
                ],
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      // Act: Remove public key
      await controller.removePublicKey(
        username: username,
        keyId: keyToRemove,
        signingKeypair: signingKeypair,
      );

      // Success - removal completed without error
    });

    test('throws error when removing last active key', () async {
      final signingKeypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'testuser';
      final keyToRemove = 'key-1';

      final mockClient = MockClient((request) async {
        if (request.url.path
            .endsWith('/api/v1/accounts/$username/keys/$keyToRemove')) {
          // Mock error for removing last active key
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'Cannot remove last active key',
            }),
            400,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      // Act & Assert: Should throw error
      expect(
        () => controller.removePublicKey(
          username: username,
          keyId: keyToRemove,
          signingKeypair: signingKeypair,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
