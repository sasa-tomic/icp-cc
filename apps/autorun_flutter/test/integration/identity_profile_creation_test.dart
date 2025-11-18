import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/identity_controller.dart';
import 'package:icp_autorun/models/identity_profile.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/utils/identity_generator.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/api_service_manager.dart';
import '../test_helpers/fake_secure_identity_repository.dart';

void main() {
  group('Identity profile creation integration', () {
    late MarketplaceOpenApiService marketplaceService;
    late FakeSecureIdentityRepository secureRepository;
    late IdentityController identityController;
    String? createdPrincipal;

    setUpAll(() async {
      suppressDebugOutput = true;
      SharedPreferences.setMockInitialValues({});
      await ApiServiceManager.initialize();
    });

    setUp(() async {
      marketplaceService = MarketplaceOpenApiService();
      secureRepository = FakeSecureIdentityRepository([]);
      identityController = IdentityController(
        secureRepository: secureRepository,
        marketplaceService: marketplaceService,
        preferences: await SharedPreferences.getInstance(),
      );
      await identityController.ensureLoaded();
      createdPrincipal = null;
    });

    tearDown(() async {
      // Clean up: delete the created profile from the backend
      if (createdPrincipal != null) {
        try {
          // Note: Backend doesn't currently have a delete profile endpoint
          // This is a placeholder for future cleanup
          // await marketplaceService.deleteIdentityProfile(createdPrincipal!);
        } catch (e) {
          // Silently ignore cleanup errors
        }
      }
    });

    test('creates identity with profile and persists to backend', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final displayName = 'Test User $uniqueSuffix';
      final username = 'test_user_$uniqueSuffix';
      final contactEmail = 'test$uniqueSuffix@example.com';

      // Generate a new identity
      final identity = await IdentityGenerator.generate(
        algorithm: KeyAlgorithm.ed25519,
        label: displayName,
        identityCount: 0,
      );
      createdPrincipal = PrincipalUtils.textFromRecord(identity);

      expect(identityController.identities, isEmpty);

      // Create identity with profile
      final createdIdentity = await identityController.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: createdPrincipal!,
          displayName: displayName,
          username: username,
          contactEmail: contactEmail,
          contactTelegram: '@test_tg',
          contactTwitter: '@test_tw',
          contactDiscord: 'test#1234',
          websiteUrl: 'https://test.example.com',
          bio: 'Integration test user',
        ),
        identity: identity,
      );

      // Verify identity was added to controller
      expect(identityController.identities, hasLength(1));
      expect(identityController.identities.first.id, equals(createdIdentity.id));
      expect(identityController.activeIdentityId, equals(createdIdentity.id));

      // Verify profile is cached locally
      final cachedProfile = identityController.profileForRecord(createdIdentity);
      expect(cachedProfile, isNotNull);
      expect(cachedProfile!.displayName, equals(displayName));
      expect(cachedProfile.username, equals(username));
      expect(cachedProfile.contactEmail, equals(contactEmail));
      expect(cachedProfile.contactTelegram, equals('@test_tg'));
      expect(cachedProfile.contactTwitter, equals('@test_tw'));
      expect(cachedProfile.contactDiscord, equals('test#1234'));
      expect(cachedProfile.websiteUrl, equals('https://test.example.com'));
      expect(cachedProfile.bio, equals('Integration test user'));

      // Verify identity persisted to secure storage
      expect(secureRepository.identities, hasLength(1));
      expect(secureRepository.identities.first.id, equals(createdIdentity.id));

      // Verify profile can be fetched from backend
      final fetchedProfile = await marketplaceService.fetchIdentityProfile(principal: createdPrincipal!);
      expect(fetchedProfile, isNotNull);
      expect(fetchedProfile!.displayName, equals(displayName));
      expect(fetchedProfile.username, equals(username));
      expect(fetchedProfile.contactEmail, equals(contactEmail));
    });

    test('created identity shows display name in list', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final displayName = 'Alice Builder $uniqueSuffix';

      final identity = await IdentityGenerator.generate(
        algorithm: KeyAlgorithm.ed25519,
        label: displayName,
        identityCount: 0,
      );
      createdPrincipal = PrincipalUtils.textFromRecord(identity);

      await identityController.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: createdPrincipal!,
          displayName: displayName,
          username: 'alice_$uniqueSuffix',
        ),
        identity: identity,
      );

      final createdIdentity = identityController.identities.first;
      final profile = identityController.profileForRecord(createdIdentity);

      // Verify the display name from profile is used
      expect(profile?.displayName, equals(displayName));
      // Verify it matches the identity label
      expect(createdIdentity.label, equals(displayName));
    });

    test('creates identity with minimal profile (display name only)', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final displayName = 'Minimal User $uniqueSuffix';

      final identity = await IdentityGenerator.generate(
        algorithm: KeyAlgorithm.ed25519,
        label: displayName,
        identityCount: 0,
      );
      createdPrincipal = PrincipalUtils.textFromRecord(identity);

      await identityController.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: createdPrincipal!,
          displayName: displayName,
        ),
        identity: identity,
      );

      final createdIdentity = identityController.identities.first;
      final profile = identityController.profileForRecord(createdIdentity);

      expect(profile, isNotNull);
      expect(profile!.displayName, equals(displayName));
      expect(profile.username, isNull);
      expect(profile.contactEmail, isNull);
      expect(profile.contactTelegram, isNull);
      expect(profile.contactTwitter, isNull);
      expect(profile.contactDiscord, isNull);
      expect(profile.websiteUrl, isNull);
      expect(profile.bio, isNull);

      // Verify backend has the minimal profile
      final fetchedProfile = await marketplaceService.fetchIdentityProfile(principal: createdPrincipal!);
      expect(fetchedProfile, isNotNull);
      expect(fetchedProfile!.displayName, equals(displayName));
    });

    test('multiple identities can be created with different profiles', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;

      // Create first identity
      final identity1 = await IdentityGenerator.generate(
        algorithm: KeyAlgorithm.ed25519,
        label: 'User One $uniqueSuffix',
        identityCount: 0,
      );
      final principal1 = PrincipalUtils.textFromRecord(identity1);

      await identityController.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: principal1,
          displayName: 'User One $uniqueSuffix',
          username: 'user_one_$uniqueSuffix',
        ),
        identity: identity1,
      );

      // Create second identity
      final identity2 = await IdentityGenerator.generate(
        algorithm: KeyAlgorithm.ed25519,
        label: 'User Two $uniqueSuffix',
        identityCount: 1,
      );
      final principal2 = PrincipalUtils.textFromRecord(identity2);
      createdPrincipal = principal2; // Track for cleanup

      await identityController.createIdentityWithProfile(
        profileDraft: IdentityProfileDraft(
          principal: principal2,
          displayName: 'User Two $uniqueSuffix',
          username: 'user_two_$uniqueSuffix',
        ),
        identity: identity2,
      );

      // Verify both identities exist
      expect(identityController.identities, hasLength(2));

      // Verify both profiles are cached
      final profile1 = identityController.profileForRecord(
        identityController.identities.firstWhere((i) => PrincipalUtils.textFromRecord(i) == principal1),
      );
      final profile2 = identityController.profileForRecord(
        identityController.identities.firstWhere((i) => PrincipalUtils.textFromRecord(i) == principal2),
      );

      expect(profile1?.displayName, equals('User One $uniqueSuffix'));
      expect(profile2?.displayName, equals('User Two $uniqueSuffix'));

      // Verify active identity is the last created one
      expect(identityController.activeIdentityId, equals(identity2.id));
    });
  });
}
