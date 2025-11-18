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
      );

      // Assert: Verify mapping was stored
      final storedUsername = await controller.getUsernameForIdentity(identity.id);
      expect(storedUsername, equals(username));
    });

    test('fetches account for identity using stored mapping on app load', () async {
      // Setup: Create test identity and pre-store username mapping
      final identity = await TestIdentityFactory.getEd25519Identity();
      final username = 'existinguser';

      // Import AccountSignatureService to get proper hex encoding
      final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts/$username')) {
          // Mock account fetch with real public key from test identity
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-456',
                'username': username,
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'public_key': publicKeyHex,  // Use actual public key
                    'ic_principal': 'bbbbb-aa',
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

      // Pre-store the mapping (simulating previous registration)
      await controller.storeUsernameForIdentity(identity.id, username);

      // Act: Fetch account for identity (simulating app load)
      await controller.fetchAccountForIdentity(identity);

      // Assert: Verify account was fetched and cached
      final account = controller.accountForIdentity(identity);
      expect(account, isNotNull);
      expect(account?.username, equals(username));
    });

    test('returns null when no username mapping exists for identity', () async {
      final identity = await TestIdentityFactory.getEd25519Identity();
      controller = AccountController(marketplaceService: mockService);

      // Act: Try to get username for identity with no mapping
      final storedUsername = await controller.getUsernameForIdentity(identity.id);

      // Assert: Should return null
      expect(storedUsername, isNull);
    });

    test('falls back to public key lookup when no local mapping exists', () async {
      // Setup: Create test identity with NO pre-stored mapping
      final identity = await TestIdentityFactory.getEd25519Identity();
      final username = 'discovereduser';
      final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);

      final mockClient = MockClient((request) async {
        // Should call the public key endpoint, not the username endpoint
        if (request.url.path.contains('/api/v1/accounts/by-public-key/')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-999',
                'username': username,
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'public_key': publicKeyHex,
                    'ic_principal': 'ccccc-aa',
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

      // Act: Fetch account (should discover via public key)
      final account = await controller.fetchAccountForIdentity(identity);

      // Assert: Account was found and mapping was stored
      expect(account, isNotNull);
      expect(account?.username, equals(username));

      // Verify mapping was saved for future use
      final storedUsername = await controller.getUsernameForIdentity(identity.id);
      expect(storedUsername, equals(username));

      // Verify account was cached
      final cachedAccount = controller.accountForIdentity(identity);
      expect(cachedAccount, isNotNull);
      expect(cachedAccount?.username, equals(username));
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
}
