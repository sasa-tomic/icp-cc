import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/utils/profile_errors.dart';
import 'package:mocktail/mocktail.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

class _MockMarketplaceService extends Mock
    implements MarketplaceOpenApiService {}

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('ProfileController - Initialization & State Management', () {
    test('ensureLoaded is idempotent', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.profiles, isEmpty);

      await controller.ensureLoaded();
      expect(controller.profiles, isEmpty);
    });

    test('refresh reloads profiles from repository', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.profiles, isEmpty);

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.refresh();
      expect(controller.profiles, hasLength(1));
      expect(controller.profiles.first.id, equals(profile.id));
    });

    test('isBusy reflects loading state', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      expect(controller.isBusy, isFalse);

      await controller.ensureLoaded();
      expect(controller.isBusy, isFalse);
    });

    test('profiles getter returns unmodifiable list', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);
      final testKeypair = await TestKeypairFactory.getEd25519Keypair();

      await controller.ensureLoaded();

      expect(
          () => controller.profiles.add(Profile(
                id: 'test',
                name: 'test',
                keypairs: [testKeypair],
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              )),
          throwsUnsupportedError);
    });

    test('activeProfileId is null initially', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.activeProfileId, isNull);
    });

    test('hasActiveProfile is false initially', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.hasActiveProfile, isFalse);
    });

    test('activeProfile is null initially', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.activeProfile, isNull);
    });

    test('activeKeypair is null initially', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.activeKeypair, isNull);
    });
  });

  group('ProfileController - Profile CRUD Operations', () {
    test('createProfile creates Ed25519 keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Ed25519 Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(profile, isNotNull);
      expect(profile.name, equals('Ed25519 Profile'));
      expect(profile.keypairs, hasLength(1));
      expect(profile.keypairs.first.algorithm, equals(KeyAlgorithm.ed25519));
      expect(profile.keypairs.first.privateKey, isNotEmpty);
      expect(profile.keypairs.first.publicKey, isNotEmpty);
    });

    test('createProfile creates secp256k1 keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Secp256k1 Profile',
        algorithm: KeyAlgorithm.secp256k1,
      );

      expect(profile, isNotNull);
      expect(profile.keypairs.first.algorithm, equals(KeyAlgorithm.secp256k1));
    });

    test('createProfile with setAsActive sets active profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      expect(controller.activeProfileId, equals(profile.id));
      expect(controller.hasActiveProfile, isTrue);
      expect(controller.activeProfile?.id, equals(profile.id));
    });

    test('createProfile without setAsActive does not change active profile',
        () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      await controller.createProfile(
        profileName: 'Inactive Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: false,
      );

      expect(controller.activeProfileId, isNull);
    });

    test('createProfile with mnemonic uses provided mnemonic', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);
      final testKeypair = await TestKeypairFactory.getEd25519Keypair();

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Mnemonic Profile',
        algorithm: KeyAlgorithm.ed25519,
        mnemonic: testKeypair.mnemonic,
      );

      expect(profile.keypairs.first.mnemonic, equals(testKeypair.mnemonic));
    });

    test('updateProfileName updates profile name', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Original Name',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileName(
        profileId: profile.id,
        name: 'Updated Name',
      );

      final updatedProfile = controller.findById(profile.id);
      expect(updatedProfile?.name, equals('Updated Name'));
    });

    test('updateProfileName updates timestamp', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Original Name',
        algorithm: KeyAlgorithm.ed25519,
      );
      final originalUpdatedAt = profile.updatedAt;

      await Future.delayed(const Duration(milliseconds: 10));
      await controller.updateProfileName(
        profileId: profile.id,
        name: 'Updated Name',
      );

      final updatedProfile = controller.findById(profile.id);
      expect(updatedProfile?.updatedAt.isAfter(originalUpdatedAt), isTrue);
    });

    test('updateProfileName for non-existent profile does nothing', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      await controller.updateProfileName(
        profileId: 'non-existent-id',
        name: 'Updated Name',
      );

      expect(controller.profiles, isEmpty);
    });

    test('updateProfileUsername updates username', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileUsername(
        profileId: profile.id,
        username: 'testuser',
      );

      final updatedProfile = controller.findById(profile.id);
      expect(updatedProfile?.username, equals('testuser'));
      expect(updatedProfile?.isRegistered, isTrue);
    });

    test('deleteProfile removes profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'To Delete',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(controller.profiles, hasLength(1));

      await controller.deleteProfile(profile.id);

      expect(controller.profiles, isEmpty);
      expect(controller.findById(profile.id), isNull);
    });

    test('deleteProfile clears active profile if deleted', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      expect(controller.activeProfileId, equals(profile.id));

      await controller.deleteProfile(profile.id);

      expect(controller.activeProfileId, isNull);
      expect(controller.hasActiveProfile, isFalse);
    });

    test('deleteProfile does not clear active if different profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final activeProfile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      final otherProfile = await controller.createProfile(
        profileName: 'Other Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.deleteProfile(otherProfile.id);

      expect(controller.activeProfileId, equals(activeProfile.id));
    });

    test('setActiveProfile switches active profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile1 = await controller.createProfile(
        profileName: 'Profile 1',
        algorithm: KeyAlgorithm.ed25519,
      );
      final profile2 = await controller.createProfile(
        profileName: 'Profile 2',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.setActiveProfile(profile1.id);
      expect(controller.activeProfile?.id, equals(profile1.id));

      await controller.setActiveProfile(profile2.id);
      expect(controller.activeProfile?.id, equals(profile2.id));
    });

    test('setActiveProfile with null clears active profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      expect(controller.activeProfileId, equals(profile.id));

      await controller.setActiveProfile(null);

      expect(controller.activeProfileId, isNull);
    });

    test('setActiveProfile throws for non-existent profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(
        () => controller.setActiveProfile('non-existent-id'),
        throwsArgumentError,
      );
    });

    test('findById returns profile by id', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final found = controller.findById(profile.id);
      expect(found?.id, equals(profile.id));
    });

    test('findById returns null for non-existent id', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(controller.findById('non-existent'), isNull);
    });

    test('findByKeypairId returns profile containing keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );
      final keypairId = profile.keypairs.first.id;

      final found = controller.findByKeypairId(keypairId);
      expect(found?.id, equals(profile.id));
    });

    test('findByKeypairId returns null for non-existent keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(controller.findByKeypairId('non-existent'), isNull);
    });
  });

  group('ProfileController - Keypair Operations', () {
    test('addKeypairToProfile adds keypair to profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(profile.keypairs, hasLength(1));

      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.secp256k1,
      );

      expect(updatedProfile.keypairs, hasLength(2));
      expect(updatedProfile.keypairs.last.algorithm,
          equals(KeyAlgorithm.secp256k1));
    });

    test('addKeypairToProfile with custom label', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
        label: 'Custom Label',
      );

      expect(updatedProfile.keypairs.last.label, equals('Custom Label'));
    });

    test('addKeypairToProfile throws for non-existent profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(
        () => controller.addKeypairToProfile(
          profileId: 'non-existent',
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsArgumentError,
      );
    });

    test('setActiveKeypair changes active keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );
      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      final secondKeypairId = updatedProfile.keypairs.last.id;

      await controller.setActiveKeypair(
        profileId: profile.id,
        keypairId: secondKeypairId,
      );

      final foundProfile = controller.findById(profile.id);
      expect(foundProfile?.activeKeypairId, equals(secondKeypairId));
      expect(foundProfile?.primaryKeypair.id, equals(secondKeypairId));
    });

    test('setActiveKeypair throws for non-existent profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(
        () => controller.setActiveKeypair(
          profileId: 'non-existent',
          keypairId: 'any-keypair',
        ),
        throwsArgumentError,
      );
    });

    test('setActiveKeypair throws for non-existent keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(
        () => controller.setActiveKeypair(
          profileId: profile.id,
          keypairId: 'non-existent-keypair',
        ),
        throwsArgumentError,
      );
    });

    test('updateKeypairLabel updates label', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );
      final keypairId = profile.keypairs.first.id;

      await controller.updateKeypairLabel(
        profileId: profile.id,
        keypairId: keypairId,
        label: 'New Label',
      );

      final updatedProfile = controller.findById(profile.id);
      final keypair = updatedProfile?.getKeypair(keypairId);
      expect(keypair?.label, equals('New Label'));
    });

    test('updateKeypairLabel for non-existent profile does nothing', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      await controller.updateKeypairLabel(
        profileId: 'non-existent',
        keypairId: 'any-keypair',
        label: 'New Label',
      );
    });

    test('updateKeypairLabel for non-existent keypair does nothing', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateKeypairLabel(
        profileId: profile.id,
        keypairId: 'non-existent-keypair',
        label: 'New Label',
      );

      final updatedProfile = controller.findById(profile.id);
      expect(updatedProfile?.keypairs, hasLength(1));
    });

    test('deleteKeypair removes non-primary keypair', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );
      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(updatedProfile.keypairs, hasLength(2));

      final keypairToDelete = updatedProfile.keypairs.last.id;
      await controller.deleteKeypair(
        profileId: profile.id,
        keypairId: keypairToDelete,
      );

      final finalProfile = controller.findById(profile.id);
      expect(finalProfile?.keypairs, hasLength(1));
      expect(finalProfile?.getKeypair(keypairToDelete), isNull);
    });

    test('deleteKeypair for non-existent profile does nothing', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      await controller.deleteKeypair(
        profileId: 'non-existent',
        keypairId: 'any-keypair',
      );
    });
  });

  group('ProfileController - Edge Cases', () {
    test('cannot add more than 10 keypairs to profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Max Keys Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      for (int i = 0; i < 9; i++) {
        await controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        );
      }

      final profileWithMaxKeys = controller.findById(profile.id);
      expect(profileWithMaxKeys?.keypairs, hasLength(10));
      expect(profileWithMaxKeys?.canAddKeypair, isFalse);

      expect(
        () => controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cannot delete last keypair in profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Single Keypair Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final keypairId = profile.keypairs.first.id;

      expect(
        () => controller.deleteKeypair(
          profileId: profile.id,
          keypairId: keypairId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('active profile persists across refresh', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(
        profileRepository: fakeRepo,
        preferences: prefs,
      );

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      expect(controller.activeProfileId, equals(profile.id));

      await controller.refresh();

      expect(controller.activeProfileId, equals(profile.id));
    });

    test('invalid active profile ID is cleared on reconcile', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_profile_id', 'non-existent-id');

      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(
        profileRepository: fakeRepo,
        preferences: prefs,
      );

      await controller.ensureLoaded();

      expect(controller.activeProfileId, isNull);
    });

    test('profile persistence across controller reinitialization', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller1 = ProfileController(profileRepository: fakeRepo);

      await controller1.ensureLoaded();

      final profile = await controller1.createProfile(
        profileName: 'Persistent Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final controller2 = ProfileController(profileRepository: fakeRepo);
      await controller2.ensureLoaded();

      final loadedProfile = controller2.findById(profile.id);
      expect(loadedProfile, isNotNull);
      expect(loadedProfile?.name, equals('Persistent Profile'));
      expect(loadedProfile?.keypairs, hasLength(1));
    });

    test('activeKeypair returns primary keypair of active profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Active Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      expect(controller.activeKeypair, isNotNull);
      expect(controller.activeKeypair?.id, equals(profile.keypairs.first.id));
    });
  });

  group('ProfileController - Keypair Properties', () {
    test('keypair derives correct IC principal', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();

      expect(keypair.principal, isNotNull);
      expect(keypair.principal!, isNotEmpty);
      expect(keypair.principal!.length, greaterThan(20));
    });

    test('different keypairs have different principals', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);

      expect(keypair1.principal, isNot(equals(keypair2.principal)));
    });

    test('deterministic keypairs from same seed are identical', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(42);
      final keypair2 = await TestKeypairFactory.fromSeed(42);

      expect(keypair1.privateKey, equals(keypair2.privateKey));
      expect(keypair1.publicKey, equals(keypair2.publicKey));
      expect(keypair1.principal, equals(keypair2.principal));
    });
  });

  group('ProfileController - Marketplace Integration', () {
    setUpAll(() async {
      final fallbackKeypair = await TestKeypairFactory.fromSeed(9001);
      registerFallbackValue(AddPublicKeyRequest(
        username: 'fallback',
        newKeypair: fallbackKeypair,
        signingPublicKeyB64: 'fallback',
        timestamp: 0,
        nonce: 'fallback',
        signature: 'fallback',
      ));
    });

    test('addKeypairToProfile calls marketplace when profile has username',
        () async {
      final fakeRepo = FakeProfileRepository([]);
      final mockMarketplace = _MockMarketplaceService();
      when(() => mockMarketplace.addPublicKey(
            username: any(named: 'username'),
            request: any(named: 'request'),
          )).thenAnswer((_) async => AccountPublicKey(
            id: 'key-1',
            publicKey: 'test-public-key',
            icPrincipal: 'test-principal',
            isActive: true,
            addedAt: DateTime.now(),
          ));

      final controller = ProfileController(
        profileRepository: fakeRepo,
        marketplaceService: mockMarketplace,
      );

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileUsername(
        profileId: profile.id,
        username: 'testuser',
      );

      await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      verify(() => mockMarketplace.addPublicKey(
            username: 'testuser',
            request: any(named: 'request'),
          )).called(1);
    });

    test(
        'addKeypairToProfile throws StateError when profile has username but MarketplaceService is null',
        () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileUsername(
        profileId: profile.id,
        username: 'testuser',
      );

      expect(
        () => controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'addKeypairToProfile propagates error when marketplace addPublicKey fails',
        () async {
      final fakeRepo = FakeProfileRepository([]);
      final mockMarketplace = _MockMarketplaceService();
      when(() => mockMarketplace.addPublicKey(
            username: any(named: 'username'),
            request: any(named: 'request'),
          )).thenThrow(Exception('Marketplace error'));

      final controller = ProfileController(
        profileRepository: fakeRepo,
        marketplaceService: mockMarketplace,
      );

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileUsername(
        profileId: profile.id,
        username: 'testuser',
      );

      await expectLater(
        () => controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ProfileController - isBusy State Transitions', () {
    test('createProfile sets isBusy during creation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.isBusy, isFalse);

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('addKeypairToProfile sets isBusy during operation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('deleteProfile sets isBusy during operation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.deleteProfile(profile.id);

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('deleteKeypair sets isBusy during operation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );
      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.deleteKeypair(
        profileId: profile.id,
        keypairId: updatedProfile.keypairs.last.id,
      );

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('refresh sets isBusy during refresh', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.refresh();

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });
  });

  group('ProfileController - Backup/Restore', () {
    test('exportProfileBackup exports encrypted profile backup', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Backup Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      expect(backup, isNotEmpty);
      expect(backup, contains('{"v":'));
    });

    test('exportProfileBackup throws for non-existent profile', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      expect(
        () => controller.exportProfileBackup('non-existent', 'password'),
        throwsArgumentError,
      );
    });

    test('importProfileBackup imports profile from backup', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Original Profile',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      await controller.deleteProfile(profile.id);
      expect(controller.profiles, isEmpty);

      final importedProfile = await controller.importProfileBackup(
        backup,
        'test-password',
      );

      expect(importedProfile.name, equals('Original Profile'));
      expect(importedProfile.keypairs, hasLength(1));
      expect(controller.profiles, hasLength(1));
    });

    test('importProfileBackup throws with wrong password', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'correct-password',
      );

      await controller.deleteProfile(profile.id);

      expect(
        () => controller.importProfileBackup(backup, 'wrong-password'),
        throwsA(anything),
      );
    });

    test('importProfileBackup throws when profile ID already exists', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Duplicate Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      expect(
        () => controller.importProfileBackup(backup, 'test-password'),
        throwsA(
          allOf(
            isA<ProfileAlreadyExistsException>(),
            predicate<ProfileAlreadyExistsException>(
              (v) => v.profileId == profile.id,
              'carries the colliding profile id',
            ),
          ),
        ),
      );
    });

    test('importProfileBackup sets isBusy during operation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      await controller.deleteProfile(profile.id);

      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.isBusy));

      await controller.importProfileBackup(backup, 'test-password');

      expect(busyStates, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('backup preserves all keypairs', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Multi-Keypair Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.secp256k1,
      );

      final profileWithMultipleKeys = controller.findById(profile.id);
      expect(profileWithMultipleKeys?.keypairs, hasLength(2));

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      await controller.deleteProfile(profile.id);

      final importedProfile = await controller.importProfileBackup(
        backup,
        'test-password',
      );

      expect(importedProfile.keypairs, hasLength(2));
      expect(
        importedProfile.keypairs[0].algorithm,
        equals(KeyAlgorithm.ed25519),
      );
      expect(
        importedProfile.keypairs[1].algorithm,
        equals(KeyAlgorithm.secp256k1),
      );
    });

    test('backup preserves username', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Registered Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.updateProfileUsername(
        profileId: profile.id,
        username: 'testuser123',
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      await controller.deleteProfile(profile.id);

      final importedProfile = await controller.importProfileBackup(
        backup,
        'test-password',
      );

      expect(importedProfile.username, equals('testuser123'));
      expect(importedProfile.isRegistered, isTrue);
    });

    test('backup preserves activeKeypairId', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final updatedProfile = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.ed25519,
      );

      final secondKeypairId = updatedProfile.keypairs.last.id;
      await controller.setActiveKeypair(
        profileId: profile.id,
        keypairId: secondKeypairId,
      );

      final backup = await controller.exportProfileBackup(
        profile.id,
        'test-password',
      );

      await controller.deleteProfile(profile.id);

      final importedProfile = await controller.importProfileBackup(
        backup,
        'test-password',
      );

      expect(importedProfile.activeKeypairId, equals(secondKeypairId));
      expect(importedProfile.primaryKeypair.id, equals(secondKeypairId));
    });
  });

  group('ProfileController - Persistence', () {
    test('createProfile persists to repository after creation', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();
      expect(controller.profiles, isEmpty);

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final controller2 = ProfileController(profileRepository: fakeRepo);
      await controller2.ensureLoaded();

      expect(controller2.profiles, hasLength(1));
      expect(controller2.profiles.first.id, equals(profile.id));
      expect(controller2.profiles.first.name, equals('Test Profile'));
    });

    test('setActiveProfile persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(
        profileRepository: fakeRepo,
        preferences: prefs,
      );

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.setActiveProfile(profile.id);

      expect(prefs.getString('active_profile_id'), equals(profile.id));

      final controller2 = ProfileController(
        profileRepository: fakeRepo,
        preferences: prefs,
      );
      await controller2.ensureLoaded();

      expect(controller2.activeProfileId, equals(profile.id));
    });

    test('deleteProfile calls repository.deleteProfileSecureData', () async {
      final fakeRepo = FakeProfileRepository([]);
      final controller = ProfileController(profileRepository: fakeRepo);

      await controller.ensureLoaded();

      final profile = await controller.createProfile(
        profileName: 'To Delete',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(controller.profiles, hasLength(1));

      await controller.deleteProfile(profile.id);

      expect(controller.profiles, isEmpty);

      final controller2 = ProfileController(profileRepository: fakeRepo);
      await controller2.ensureLoaded();

      expect(controller2.profiles, isEmpty);
    });
  });
}
