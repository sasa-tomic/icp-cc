import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/services/secure_keypair_repository.dart';

import 'test_keypair_factory.dart';

/// Fake implementation of SecureKeypairRepository for testing
/// Stores identities in memory and provides full control for test scenarios
class FakeSecureKeypairRepository implements SecureKeypairRepository {
  FakeSecureKeypairRepository(List<ProfileKeypair> initialIdentities)
      : _identities = List.of(initialIdentities),
        _fakeProfileRepository = FakeProfileRepository(
          // Convert initial identities to profiles
          initialIdentities.map((identity) {
            return Profile(
              id: 'profile_${identity.id}',
              name: identity.label,
              keypairs: [identity],
              username: null,
              createdAt: identity.createdAt,
              updatedAt: identity.createdAt,
            );
          }).toList(),
        );

  List<ProfileKeypair> _identities;
  final FakeProfileRepository _fakeProfileRepository;

  /// Public getter for testing purposes to verify persistence
  List<ProfileKeypair> get identities => List<ProfileKeypair>.from(_identities);

  @override
  Future<List<ProfileKeypair>> loadIdentities() async {
    return List<ProfileKeypair>.from(_identities);
  }

  @override
  Future<void> persistIdentities(List<ProfileKeypair> identities) async {
    _identities = List<ProfileKeypair>.from(identities);

    // Also update profiles - each identity becomes a profile with one keypair
    final List<Profile> profiles = identities.map((identity) {
      return Profile(
        id: 'profile_${identity.id}', // Deterministic profile ID
        name: identity.label,
        keypairs: [identity],
        username: null,
        createdAt: identity.createdAt,
        updatedAt: identity.createdAt,
      );
    }).toList();

    await _fakeProfileRepository.persistProfiles(profiles);
  }

  @override
  Future<void> deleteKeypairSecureData(String identityId) async {
    _identities.removeWhere((identity) => identity.id == identityId);
  }

  @override
  Future<void> deleteAllSecureData() async {
    _identities = <ProfileKeypair>[];
  }

  @override
  Future<String?> getPrivateKey(String identityId) async {
    final identity = _identities.firstWhere(
      (identity) => identity.id == identityId,
      orElse: () => throw StateError('Keypair not found: $identityId'),
    );
    return identity.privateKey;
  }

  @override
  ProfileRepository get profileRepository => _fakeProfileRepository;
}

/// Fake ProfileRepository for testing
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(List<Profile> initialProfiles)
      : _profiles = List.of(initialProfiles);

  List<Profile> _profiles;

  /// Create a test profile with a single keypair
  static Future<Profile> createTestProfile({
    required String name,
    String? username,
  }) async {
    // Import needed for generating keypair
    final keypair = await _generateTestKeypair(label: '$name - Primary');

    final now = DateTime.now().toUtc();
    return Profile(
      id: 'profile_${name.hashCode}', // Deterministic ID based on name
      name: name,
      keypairs: [keypair],
      username: username,
      createdAt: now,
      updatedAt: now,
    );
  }

  static Future<ProfileKeypair> _generateTestKeypair(
      {required String label}) async {
    // Import test identity factory
    final TestKeypair = await TestKeypairFactory.getEd25519Keypair();
    // Create a copy with the desired label
    return TestKeypair.copyWith(label: label);
  }

  @override
  Future<List<Profile>> loadProfiles() async {
    return List<Profile>.from(_profiles);
  }

  @override
  Future<void> persistProfiles(List<Profile> profiles) async {
    _profiles = List<Profile>.from(profiles);
  }

  @override
  Future<void> deleteKeypairSecureData(String keypairId) async {
    // No-op in fake implementation
  }

  @override
  Future<void> deleteProfileSecureData(Profile profile) async {
    // No-op in fake implementation
  }

  @override
  Future<void> deleteAllSecureData() async {
    _profiles = <Profile>[];
  }

  @override
  Future<String?> getPrivateKey(String keypairId) async {
    for (final profile in _profiles) {
      final keypair = profile.getKeypair(keypairId);
      if (keypair != null) {
        return keypair.privateKey;
      }
    }
    return null;
  }

  @override
  Future<String?> getMnemonic(String keypairId) async {
    for (final profile in _profiles) {
      final keypair = profile.getKeypair(keypairId);
      if (keypair != null) {
        return keypair.mnemonic;
      }
    }
    return null;
  }
}
