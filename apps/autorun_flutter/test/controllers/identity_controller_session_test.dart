import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/controllers/identity_controller.dart';
import 'package:icp_autorun/models/identity_profile.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/secure_identity_repository.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureIdentityRepository implements SecureIdentityRepository {
  _FakeSecureIdentityRepository(List<IdentityRecord> seed) : _identities = List.of(seed);

  List<IdentityRecord> _identities;

  @override
  Future<List<IdentityRecord>> loadIdentities() async => List<IdentityRecord>.from(_identities);

  @override
  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    _identities = List<IdentityRecord>.from(identities);
  }

  @override
  Future<void> deleteIdentitySecureData(String identityId) async {}

  @override
  Future<void> deleteAllSecureData() async {
    _identities = <IdentityRecord>[];
  }

  @override
  Future<String?> getPrivateKey(String identityId) async => 'private-key-$identityId';
}

IdentityRecord _sampleIdentity({String id = 'identity-1', String label = 'Primary'}) {
  return IdentityRecord(
    id: id,
    label: label,
    algorithm: KeyAlgorithm.ed25519,
    publicKey: base64Encode(List<int>.filled(32, 1)),
    privateKey: base64Encode(List<int>.filled(32, 2)),
    mnemonic: 'sample mnemonic words twelve',
    createdAt: DateTime.utc(2024, 1, 1),
  );
}

MarketplaceOpenApiService _mockProfileService(IdentityProfile profile) {
  final MarketplaceOpenApiService service = MarketplaceOpenApiService();
  final MockClient client = MockClient((http.Request request) async {
    if (request.url.path.endsWith('/identities/profile')) {
      return http.Response(
        jsonEncode({
          'success': true,
          'data': profile.toJsonWrapper(),
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (request.url.path.contains('/identities/') && request.url.path.endsWith('/profile')) {
      return http.Response(
        jsonEncode({
          'success': true,
          'data': profile.toJsonWrapper(),
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    }
    return http.Response('Not Found', 404);
  });
  service.overrideHttpClient(client);
  return service;
}

extension on IdentityProfile {
  Map<String, dynamic> toJsonWrapper() {
    return {
      'profile': {
        'id': id,
        'principal': principal,
        'displayName': displayName,
        'username': username,
        'contactEmail': contactEmail,
        'contactTelegram': contactTelegram,
        'contactTwitter': contactTwitter,
        'contactDiscord': contactDiscord,
        'websiteUrl': websiteUrl,
        'bio': bio,
        'metadata': metadata,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IdentityController session management', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('loads identities and persists active selection', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final IdentityController controller = IdentityController(
        secureRepository: _FakeSecureIdentityRepository(<IdentityRecord>[
          _sampleIdentity(id: 'id-1', label: 'Primary Identity'),
          _sampleIdentity(id: 'id-2', label: 'Secondary Identity'),
        ]),
        marketplaceService: MarketplaceOpenApiService(),
        preferences: prefs,
      );

      await controller.ensureLoaded();
      expect(controller.identities, hasLength(2));
      expect(controller.activeIdentity, isNull);

      await controller.setActiveIdentity(controller.identities.last.id);
      expect(controller.activeIdentityId, equals('id-2'));
      expect(prefs.getString('active_identity_id'), equals('id-2'));

      await controller.setActiveIdentity(null);
      expect(controller.activeIdentity, isNull);
      expect(prefs.getString('active_identity_id'), isNull);
    });

    test('setActiveIdentity throws when id is unknown', () async {
      final IdentityController controller = IdentityController(
        secureRepository: _FakeSecureIdentityRepository(<IdentityRecord>[_sampleIdentity()]),
        marketplaceService: MarketplaceOpenApiService(),
        preferences: await SharedPreferences.getInstance(),
      );
      await controller.ensureLoaded();

      expect(
        () => controller.setActiveIdentity('missing'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('saveProfile caches profile and marks identity complete', () async {
      final IdentityRecord record = _sampleIdentity();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final IdentityProfile profile = IdentityProfile(
        id: 'profile-1',
        principal: PrincipalUtils.textFromRecord(record),
        displayName: 'ICP Builder',
        username: 'icp_builder',
        contactEmail: 'dev@example.com',
        contactTelegram: '@icp',
        contactTwitter: '@dfinity',
        contactDiscord: 'icp#1234',
        websiteUrl: 'https://internetcomputer.org',
        bio: 'Building unstoppable apps',
        metadata: const <String, dynamic>{'team': 'Core'},
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );
      final IdentityController controller = IdentityController(
        secureRepository: _FakeSecureIdentityRepository(<IdentityRecord>[record]),
        marketplaceService: _mockProfileService(profile),
        preferences: prefs,
      );
      await controller.ensureLoaded();
      await controller.setActiveIdentity(record.id);

      final IdentityProfile saved = await controller.saveProfile(
        identity: record,
        draft: IdentityProfileDraft(
          principal: profile.principal,
          displayName: profile.displayName,
          username: profile.username,
        ),
      );

      expect(saved.displayName, equals('ICP Builder'));
      expect(controller.profileForRecord(record)?.displayName, equals('ICP Builder'));
      expect(controller.isProfileComplete(record), isTrue);
    });
  });
}
