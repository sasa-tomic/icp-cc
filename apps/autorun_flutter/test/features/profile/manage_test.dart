import 'package:flutter_test/flutter_test.dart';
import 'package:autorun_flutter/controllers/profile_controller.dart';
import 'package:autorun_flutter/services/profile_repository.dart';
import 'package:autorun_flutter/models/profile.dart';
import 'package:autorun_flutter/models/profile_keypair.dart';

import '../shared/test_helpers.dart';

/// E2E test: Profile and keypair management
/// 
/// This test covers the complete profile flow:
/// 1. Create profile with keypair
/// 2. Add additional keypairs
/// 3. Switch between profiles
/// 4. Register account on backend
void main() {
  late ProfileController controller;
  late FakeSecureKeypairRepository fakeRepo;

  setUp(() async {
    fakeRepo = FakeSecureKeypairRepository([]);
    controller = ProfileController(repository: fakeRepo);
    await controller.initialize();
  });

  group('create and manage profile', () {
    test('user can create profile with Ed25519 keypair', () async {
      final profile = await controller.createProfile(
        name: 'Test Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      expect(profile, isNotNull);
      expect(profile.name, equals('Test Profile'));
      expect(profile.keypairs, hasLength(1));
      expect(profile.keypairs.first.algorithm, equals(KeyAlgorithm.ed25519));
      expect(profile.keypairs.first.privateKeyBase64, isNotEmpty);
      expect(profile.keypairs.first.publicKeyBase64, isNotEmpty);
    });

    test('user can create profile with secp256k1 keypair', () async {
      final profile = await controller.createProfile(
        name: 'Secp256k1 Profile',
        algorithm: KeyAlgorithm.secp256k1,
      );

      expect(profile, isNotNull);
      expect(profile.keypairs.first.algorithm, equals(KeyAlgorithm.secp256k1));
    });

    test('user can add additional keypair to profile', () async {
      final profile = await controller.createProfile(
        name: 'Multi-Key Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      final newKeypair = await controller.addKeypairToProfile(
        profileId: profile.id,
        algorithm: KeyAlgorithm.secp256k1,
      );

      expect(newKeypair, isNotNull);
      
      final updatedProfile = controller.getProfile(profile.id);
      expect(updatedProfile!.keypairs, hasLength(2));
    });

    test('profile cannot have more than 10 keypairs', () async {
      final profile = await controller.createProfile(
        name: 'Max Keys Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      // Add 9 more keypairs (total 10)
      for (int i = 0; i < 9; i++) {
        await controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        );
      }

      // 11th keypair should fail
      expect(
        () => controller.addKeypairToProfile(
          profileId: profile.id,
          algorithm: KeyAlgorithm.ed25519,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('user can switch between profiles', () async {
      final profile1 = await controller.createProfile(
        name: 'Profile 1',
        algorithm: KeyAlgorithm.ed25519,
      );
      final profile2 = await controller.createProfile(
        name: 'Profile 2',
        algorithm: KeyAlgorithm.ed25519,
      );

      await controller.setActiveProfile(profile1.id);
      expect(controller.activeProfile?.id, equals(profile1.id));

      await controller.setActiveProfile(profile2.id);
      expect(controller.activeProfile?.id, equals(profile2.id));
    });
  });

  group('keypair properties', () {
    test('keypair derives correct IC principal', () async {
      final keypair = TestKeypairFactory.getEd25519Keypair();

      expect(keypair.icPrincipal, isNotEmpty);
      expect(keypair.icPrincipal.length, greaterThan(20));
    });

    test('different keypairs have different principals', () async {
      final keypair1 = TestKeypairFactory.fromSeed(1);
      final keypair2 = TestKeypairFactory.fromSeed(2);

      expect(keypair1.icPrincipal, isNot(equals(keypair2.icPrincipal)));
    });

    test('deterministic keypairs from same seed are identical', () async {
      final keypair1 = TestKeypairFactory.fromSeed(42);
      final keypair2 = TestKeypairFactory.fromSeed(42);

      expect(keypair1.privateKeyBase64, equals(keypair2.privateKeyBase64));
      expect(keypair1.publicKeyBase64, equals(keypair2.publicKeyBase64));
      expect(keypair1.icPrincipal, equals(keypair2.icPrincipal));
    });
  });

  group('profile persistence', () {
    test('profiles persist across controller reinitialization', () async {
      final profile = await controller.createProfile(
        name: 'Persistent Profile',
        algorithm: KeyAlgorithm.ed25519,
      );

      // Create new controller with same repo
      final newController = ProfileController(repository: fakeRepo);
      await newController.initialize();

      final loadedProfile = newController.getProfile(profile.id);
      expect(loadedProfile, isNotNull);
      expect(loadedProfile!.name, equals('Persistent Profile'));
      expect(loadedProfile.keypairs, hasLength(1));
    });
  });
}
