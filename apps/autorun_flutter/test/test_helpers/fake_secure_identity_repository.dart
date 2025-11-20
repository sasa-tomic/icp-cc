import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/services/secure_identity_repository.dart';

/// Fake implementation of SecureIdentityRepository for testing
/// Stores identities in memory and provides full control for test scenarios
class FakeSecureIdentityRepository implements SecureIdentityRepository {
  FakeSecureIdentityRepository(List<IdentityRecord> initialIdentities)
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

  List<IdentityRecord> _identities;
  final FakeProfileRepository _fakeProfileRepository;

  /// Public getter for testing purposes to verify persistence
  List<IdentityRecord> get identities => List<IdentityRecord>.from(_identities);

  @override
  Future<List<IdentityRecord>> loadIdentities() async {
    return List<IdentityRecord>.from(_identities);
  }

  @override
  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    _identities = List<IdentityRecord>.from(identities);

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
  Future<void> deleteIdentitySecureData(String identityId) async {
    _identities.removeWhere((identity) => identity.id == identityId);
  }

  @override
  Future<void> deleteAllSecureData() async {
    _identities = <IdentityRecord>[];
  }

  @override
  Future<String?> getPrivateKey(String identityId) async {
    final identity = _identities.firstWhere(
      (identity) => identity.id == identityId,
      orElse: () => throw StateError('Identity not found: $identityId'),
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
