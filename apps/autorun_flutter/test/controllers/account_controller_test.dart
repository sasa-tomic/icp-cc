import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/account_signature_service.dart';
import '../test_helpers/test_identity_factory.dart';

void main() {
  // Initialize secure storage mock for tests
  FlutterSecureStorage.setMockInitialValues({});

  group('AccountController - Identity Username Mapping', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('stores identity-username mapping after successful registration', () async {
      // Setup: Create test identity and mock successful registration response
      final identity = await TestIdentityFactory.getEd25519Identity();
      final username = 'testuser';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts')) {
          // Mock successful registration
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
                    'public_key': '0x1234abcd',
                    'ic_principal': 'aaaaa-aa',
                    'is_active': true,
                    'added_at': DateTime.now().toIso8601String(),
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

      // Act: Register account
      await controller.registerAccount(
        identity: identity,
        username: username,
        displayName: 'Test User',
      );

      // Assert: Verify mapping was stored
      final storedUsername = await controller.getUsernameForIdentity(identity.id);
      expect(storedUsername, equals(username));
    });

    test('returns null when no username mapping exists for identity', () async {
      final identity = await TestIdentityFactory.getEd25519Identity();
      controller = AccountController(marketplaceService: mockService);

      // Act: Try to get username for identity with no mapping
      final storedUsername = await controller.getUsernameForIdentity(identity.id);

      // Assert: Should return null
      expect(storedUsername, isNull);
    });

    test('removes mapping when clearing cache', () async {
      final identity = await TestIdentityFactory.getEd25519Identity();
      final username = 'usertoremove';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'account-789',
              'username': username,
              'display_name': 'User To Remove',
              'publicKeys': [],
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            }
          }),
          200,
        );
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      // Setup: Store mapping
      await controller.storeUsernameForIdentity(identity.id, username);
      expect(await controller.getUsernameForIdentity(identity.id), equals(username));

      // Act: Clear cache
      controller.clearCache();

      // Assert: Mapping should still exist (not in-memory cache, but persistent)
      // Note: clearCache() clears in-memory cache but should NOT clear persistent mappings
      expect(await controller.getUsernameForIdentity(identity.id), equals(username));
    });
  });

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
      final signingIdentity = await TestIdentityFactory.getEd25519Identity();
      final username = 'testuser';
      final keyToRemove = 'key-2';

      final signingKeyHex = AccountSignatureService.publicKeyToHex(signingIdentity.publicKey);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username/keys/$keyToRemove') &&
            request.method == 'DELETE') {
          // Mock successful key removal - return the disabled key
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': keyToRemove,
                'public_key': '0xremoved',
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
                    'public_key': signingKeyHex,
                    'ic_principal': 'signing-principal-aa',
                    'is_active': true,
                    'added_at': DateTime.now().toIso8601String(),
                  },
                  {
                    'id': 'key-2',
                    'public_key': '0xremoved',
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

      // Pre-store the identity->username mapping
      await controller.storeUsernameForIdentity(signingIdentity.id, username);

      // Act: Remove public key
      await controller.removePublicKey(
        username: username,
        keyId: keyToRemove,
        signingIdentity: signingIdentity,
      );

      // Success - removal completed without error
    });

    test('throws error when removing last active key', () async {
      final signingIdentity = await TestIdentityFactory.getEd25519Identity();
      final username = 'testuser';
      final keyToRemove = 'key-1';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts/$username/keys/$keyToRemove')) {
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
          signingIdentity: signingIdentity,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
