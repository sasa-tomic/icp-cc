import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/controllers/identity_controller.dart';
import 'package:icp_autorun/models/identity_profile.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_identity_repository.dart';
import '../test_helpers/test_identity_factory.dart';

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
      final identity1 = await TestIdentityFactory.fromSeed(1);
      final identity2 = await TestIdentityFactory.fromSeed(2);
      final IdentityController controller = IdentityController(
        secureRepository: FakeSecureIdentityRepository(<IdentityRecord>[
          identity1,
          identity2,
        ]),
        marketplaceService: MarketplaceOpenApiService(),
        preferences: prefs,
      );

      await controller.ensureLoaded();
      expect(controller.identities, hasLength(2));
      expect(controller.activeIdentity, isNull);

      await controller.setActiveIdentity(controller.identities.last.id);
      expect(controller.activeIdentityId, equals(identity2.id));
      expect(prefs.getString('active_identity_id'), equals(identity2.id));

      await controller.setActiveIdentity(null);
      expect(controller.activeIdentity, isNull);
      expect(prefs.getString('active_identity_id'), isNull);
    });

    test('setActiveIdentity throws when id is unknown', () async {
      final identity = await TestIdentityFactory.getEd25519Identity();
      final IdentityController controller = IdentityController(
        secureRepository: FakeSecureIdentityRepository(<IdentityRecord>[identity]),
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
      final IdentityRecord record = await TestIdentityFactory.getEd25519Identity();
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
        secureRepository: FakeSecureIdentityRepository(<IdentityRecord>[record]),
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

    test('createIdentityWithProfile creates identity and profile atomically', () async {
      final IdentityRecord newIdentity = await TestIdentityFactory.fromSeed(42);
      final String principal = PrincipalUtils.textFromRecord(newIdentity);
      final IdentityProfile expectedProfile = IdentityProfile(
        id: 'profile-new',
        principal: principal,
        displayName: 'Alice Developer',
        username: 'alice_dev',
        contactEmail: 'alice@example.com',
        contactTelegram: '@alice',
        contactTwitter: '@alice_dev',
        contactDiscord: 'alice#5678',
        websiteUrl: 'https://alice.dev',
        bio: 'Building decentralized apps',
        metadata: const <String, dynamic>{'role': 'Developer'},
        createdAt: DateTime.utc(2024, 2, 1),
        updatedAt: DateTime.utc(2024, 2, 1),
      );

      final FakeSecureIdentityRepository repository = FakeSecureIdentityRepository(<IdentityRecord>[]);
      final IdentityController controller = IdentityController(
        secureRepository: repository,
        marketplaceService: _mockProfileService(expectedProfile),
        preferences: await SharedPreferences.getInstance(),
      );
      await controller.ensureLoaded();

      expect(controller.identities, isEmpty);

      final IdentityRecord created = await controller.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: principal,
          displayName: 'Alice Developer',
          username: 'alice_dev',
          contactEmail: 'alice@example.com',
          contactTelegram: '@alice',
          contactTwitter: '@alice_dev',
          contactDiscord: 'alice#5678',
          websiteUrl: 'https://alice.dev',
          bio: 'Building decentralized apps',
        ),
        identity: newIdentity,
      );

      expect(created.id, equals(newIdentity.id));
      expect(controller.identities, hasLength(1));
      expect(controller.identities.first.id, equals(newIdentity.id));
      expect(controller.activeIdentityId, equals(newIdentity.id));
      expect(controller.profileForRecord(created)?.displayName, equals('Alice Developer'));
      expect(controller.isProfileComplete(created), isTrue);
      expect(repository.identities, hasLength(1));
    });
  });
}
