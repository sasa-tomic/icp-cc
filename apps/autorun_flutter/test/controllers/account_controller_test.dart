import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import '../shared/test_keypair_factory.dart';

void main() {
  // Initialize secure storage mock for tests
  FlutterSecureStorage.setMockInitialValues({});

  group('AccountController - registerAccount', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('successfully registers account with valid data', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'testuser';
      final displayName = 'Test User';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts') &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['username'], username);
          expect(body['displayName'], displayName);
          expect(body['publicKeyB64'], isNotEmpty);
          expect(body['signature'], isNotEmpty);
          expect(body['timestamp'], isNotNull);
          expect(body['nonce'], isNotNull);

          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-123',
                'username': username,
                'displayName': displayName,
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': keypair.principal ?? 'test-principal',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final account = await controller.registerAccount(
        keypair: keypair,
        username: username,
        displayName: displayName,
      );

      expect(account.username, username);
      expect(account.displayName, displayName);
      expect(account.publicKeys.length, 1);
      expect(controller.getAccount(username), isNotNull);
    });

    test('throws error when username is invalid', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      mockService = MarketplaceOpenApiService();
      controller = AccountController(marketplaceService: mockService);

      // 'invalid username!' fails the charset rule (space + '!'), so the
      // controller surfaces the validator's specific message — not a generic
      // Exception. Asserting the concrete message proves the validation path
      // ran (a stray network/format error would not contain it).
      expect(
        () => controller.registerAccount(
          keypair: keypair,
          username: 'invalid username!',
          displayName: 'Test User',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'validation message',
          contains('Username can only contain'),
        )),
      );
    });

    test('throws error when username is already taken', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'takenuser';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts') &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'Username already taken',
            }),
            409,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      // The 409 envelope's `error` field is carried verbatim into the thrown
      // message, prefixed with the endpoint's status banner — assert both the
      // status and the server detail so a different failure mode can't pass.
      expect(
        () => controller.registerAccount(
          keypair: keypair,
          username: username,
          displayName: 'Test User',
        ),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'status banner',
                contains('Account registration failed (HTTP 409)'))
            .having((e) => e.toString(), 'server detail',
                contains('Username already taken'))),
      );
    });

    test('normalizes username to lowercase', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'TestUser';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/accounts') &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['username'], 'testuser');

          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-123',
                'username': 'testuser',
                'displayName': 'Test',
                'publicKeys': [],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final account = await controller.registerAccount(
        keypair: keypair,
        username: username,
        displayName: 'Test',
      );

      expect(account.username, 'testuser');
    });
  });

  group('AccountController - fetchAccount', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('successfully fetches existing account', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'existinguser';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-456',
                'username': username,
                'displayName': 'Existing User',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-abc',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final account = await controller.fetchAccount(username);

      expect(account, isNotNull);
      expect(account!.username, username);
      expect(account.displayName, 'Existing User');
    });

    test('returns null for non-existent account', () async {
      final username = 'nonexistent';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response('Not Found', 404);
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final account = await controller.fetchAccount(username);

      expect(account, isNull);
    });

    test('caches fetched account', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'cacheduser';
      var fetchCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          fetchCount++;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-789',
                'username': username,
                'displayName': 'Cached User',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-xyz',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      await controller.fetchAccount(username);
      expect(fetchCount, 1);

      final cachedAccount = controller.getAccount(username);
      expect(cachedAccount, isNotNull);
      expect(cachedAccount!.username, username);
    });

    test('throws on network error', () async {
      final username = 'networkerror';

      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      // The transport error propagates verbatim — assert the concrete message
      // so a different exception type/message cannot satisfy the test.
      expect(
        () => controller.fetchAccount(username),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'network error message',
          contains('Network error'),
        )),
      );
    });
  });

  group('AccountController - refreshAccount', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('clears cache and fetches fresh account', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'refreshuser';
      var fetchCount = 0;
      String displayName = 'Old Name';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          fetchCount++;
          final currentName = displayName;
          if (fetchCount > 1) {
            displayName = 'New Name';
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-refresh',
                'username': username,
                'displayName': currentName,
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-refresh',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final firstFetch = await controller.fetchAccount(username);
      expect(firstFetch!.displayName, 'Old Name');
      expect(fetchCount, 1);

      displayName = 'New Name';

      final refreshed = await controller.refreshAccount(username);
      expect(refreshed!.displayName, 'New Name');
      expect(fetchCount, 2);
    });

    test('returns null after refresh if account deleted', () async {
      final username = 'deleteduser';
      var shouldReturnAccount = true;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          if (shouldReturnAccount) {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'id': 'account-delete',
                  'username': username,
                  'displayName': 'User',
                  'publicKeys': [],
                  'createdAt': DateTime.now().toIso8601String(),
                  'updatedAt': DateTime.now().toIso8601String(),
                }
              }),
              200,
            );
          } else {
            return http.Response('Not Found', 404);
          }
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      await controller.fetchAccount(username);
      shouldReturnAccount = false;

      final refreshed = await controller.refreshAccount(username);
      expect(refreshed, isNull);
    });
  });

  group('AccountController - isUsernameAvailable', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('returns true for available username', () async {
      final username = 'availableuser';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response('Not Found', 404);
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final isAvailable = await controller.isUsernameAvailable(username);
      expect(isAvailable, isTrue);
    });

    test('returns false for taken username', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'takenusername';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-taken',
                'username': username,
                'displayName': 'Taken',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-taken',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final isAvailable = await controller.isUsernameAvailable(username);
      expect(isAvailable, isFalse);
    });

    test('caches availability result', () async {
      final username = 'cachedavailability';
      var checkCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          checkCount++;
          return http.Response('Not Found', 404);
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      await controller.isUsernameAvailable(username);
      expect(checkCount, 1);

      await controller.isUsernameAvailable(username);
      expect(checkCount, 1);
    });

    test('clears availability cache when account is registered', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'registertestuser';
      var checkCount = 0;

      final mockClient = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/api/v1/accounts')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-new',
                'username': username,
                'displayName': 'New User',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': keypair.principal ?? 'test-principal',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          checkCount++;
          return http.Response('Not Found', 404);
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      await controller.isUsernameAvailable(username);
      expect(checkCount, 1);

      await controller.registerAccount(
        keypair: keypair,
        username: username,
        displayName: 'New User',
      );

      await controller.isUsernameAvailable(username);
      expect(checkCount, 2);
    });
  });

  group('AccountController - addKeypairToAccount', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('throws StateError when ProfileController is not provided', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      controller = AccountController(marketplaceService: mockService);

      final profile = Profile(
        id: 'profile-1',
        name: 'Test Profile',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => controller.addKeypairToAccount(
          profile: profile,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when profile has no username', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final mockProfileController = _MockProfileController();
      controller = AccountController(
        marketplaceService: mockService,
        profileController: mockProfileController,
      );

      final profile = Profile(
        id: 'profile-1',
        name: 'Unregistered Profile',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => controller.addKeypairToAccount(
          profile: profile,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AccountController - getAccountForProfile', () {
    late AccountController controller;
    late MarketplaceOpenApiService mockService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      mockService = MarketplaceOpenApiService();
    });

    tearDown(() {
      controller.clearCache();
    });

    test('returns null for unregistered profile', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      controller = AccountController(marketplaceService: mockService);

      final profile = Profile(
        id: 'profile-1',
        name: 'Unregistered',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final account = await controller.getAccountForProfile(profile);
      expect(account, isNull);
    });

    test('returns cached account if available', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'cachedprofile';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-cached',
                'username': username,
                'displayName': 'Cached Profile',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-cached',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final profile = Profile(
        id: 'profile-1',
        name: 'Cached Profile',
        keypairs: [keypair],
        username: username,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await controller.fetchAccount(username);

      final account = await controller.getAccountForProfile(profile);
      expect(account, isNotNull);
      expect(account!.username, username);
    });

    test('fetches from backend if not cached', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final username = 'uncachedprofile';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/accounts/$username')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'account-uncached',
                'username': username,
                'displayName': 'Uncached Profile',
                'publicKeys': [
                  {
                    'id': 'key-1',
                    'publicKey': keypair.publicKey,
                    'icPrincipal': 'principal-uncached',
                    'isActive': true,
                    'addedAt': DateTime.now().toIso8601String(),
                  }
                ],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockService.overrideHttpClient(mockClient);
      controller = AccountController(marketplaceService: mockService);

      final profile = Profile(
        id: 'profile-1',
        name: 'Uncached Profile',
        keypairs: [keypair],
        username: username,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final account = await controller.getAccountForProfile(profile);
      expect(account, isNotNull);
      expect(account!.username, username);
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

      // Act & Assert: The 400 envelope's `error` field surfaces with the
      // endpoint status banner — assert both so the failure is pinned to the
      // "cannot remove last key" path, not any generic exception.
      expect(
        () => controller.removePublicKey(
          username: username,
          keyId: keyToRemove,
          signingKeypair: signingKeypair,
        ),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'status banner',
                contains('Remove key failed (HTTP 400)'))
            .having((e) => e.toString(), 'server detail',
                contains('Cannot remove last active key'))),
      );
    });
  });
}

class _MockProfileController extends ProfileController {
  @override
  Future<Profile> addKeypairToProfile({
    required String profileId,
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
  }) {
    throw UnimplementedError();
  }

  @override
  Profile? get activeProfile => throw UnimplementedError();

  @override
  String? get activeProfileId => throw UnimplementedError();

  @override
  ProfileKeypair? get activeKeypair => throw UnimplementedError();

  @override
  Future<Profile> createProfile({
    required String profileName,
    required KeyAlgorithm algorithm,
    String? mnemonic,
    bool setAsActive = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProfile(String profileId) {
    throw UnimplementedError();
  }

  @override
  Future<void> ensureLoaded() {
    throw UnimplementedError();
  }

  @override
  Profile? findById(String id) {
    throw UnimplementedError();
  }

  @override
  List<Profile> get profiles => throw UnimplementedError();

  @override
  Future<void> setActiveProfile(String? id) {
    throw UnimplementedError();
  }

  @override
  bool get isBusy => throw UnimplementedError();

  @override
  bool get hasActiveProfile => throw UnimplementedError();

  @override
  Future<void> refresh() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateProfileName({
    required String profileId,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateProfileUsername({
    required String profileId,
    required String username,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setActiveKeypair({
    required String profileId,
    required String keypairId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateKeypairLabel({
    required String profileId,
    required String keypairId,
    required String label,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteKeypair({
    required String profileId,
    required String keypairId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> exportProfileBackup(String profileId, String password) {
    throw UnimplementedError();
  }

  @override
  Future<Profile> importProfileBackup(String encryptedJson, String password) {
    throw UnimplementedError();
  }

  @override
  Profile? findByKeypairId(String keypairId) {
    throw UnimplementedError();
  }
}
