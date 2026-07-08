import 'dart:convert';

import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/profile_invariants.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/services/secure_keypair_repository.dart';
import 'package:icp_autorun/utils/encrypted_export.dart';
import 'package:icp_autorun/utils/profile_errors.dart';

import 'test_keypair_factory.dart';

/// Fake implementation of SecureKeypairRepository for testing
/// Stores keypairs in memory and provides full control for test scenarios
class FakeSecureKeypairRepository implements SecureKeypairRepository {
  FakeSecureKeypairRepository(List<ProfileKeypair> initialKeypairs)
      : _keypairs = List.of(initialKeypairs),
        _fakeProfileRepository = FakeProfileRepository(
          // Convert initial keypairs to profiles
          initialKeypairs.map((keypair) {
            return Profile(
              id: 'profile_${keypair.id}',
              name: keypair.label,
              keypairs: [keypair],
              username: null,
              createdAt: keypair.createdAt,
              updatedAt: keypair.createdAt,
            );
          }).toList(),
        );

  List<ProfileKeypair> _keypairs;
  final FakeProfileRepository _fakeProfileRepository;

  /// Public getter for testing purposes to verify persistence
  List<ProfileKeypair> get keypairs => List<ProfileKeypair>.from(_keypairs);

  @override
  Future<List<ProfileKeypair>> loadKeypairs() async {
    return List<ProfileKeypair>.from(_keypairs);
  }

  @override
  Future<void> deleteKeypairSecureData(String keypairId) async {
    _keypairs.removeWhere((keypair) => keypair.id == keypairId);
  }

  @override
  Future<void> deleteAllSecureData() async {
    _keypairs = <ProfileKeypair>[];
  }

  @override
  Future<String?> getPrivateKey(String keypairId) async {
    final keypair = _keypairs.firstWhere(
      (keypair) => keypair.id == keypairId,
      orElse: () => throw StateError('Keypair not found: $keypairId'),
    );
    return keypair.privateKey;
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
    // Import test keypair factory
    final testKeypair = await TestKeypairFactory.getEd25519Keypair();
    // Create a copy with the desired label
    return testKeypair.copyWith(label: label);
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

  @override
  Future<String> exportKeypairEncrypted(
    String keypairId,
    String password,
  ) async {
    for (final profile in _profiles) {
      final keypair = profile.getKeypair(keypairId);
      if (keypair != null) {
        return await keypair.toEncryptedExport(password);
      }
    }
    throw ArgumentError('Keypair not found: $keypairId');
  }

  @override
  Future<String> exportProfileBackup(String profileId, String password) async {
    final profile = _profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => throw ArgumentError('Profile not found: $profileId'),
    );

    final backupData = <String, dynamic>{
      'v': 1,
      'type': 'profile_backup',
      'profile': profile.toJson(),
    };

    return EncryptedExport.encrypt(jsonEncode(backupData), password);
  }

  @override
  Future<Profile> importProfileBackup(
    String encryptedJson,
    String password,
  ) async {
    // Mirror the real ProfileRepository: translate the generic crypto-layer
    // contract into typed profile-backup exceptions at this boundary so tests
    // exercising the import path observe the same typed errors as production.
    final String plainJson;
    try {
      plainJson = await EncryptedExport.decrypt(encryptedJson, password);
    } on FormatException catch (e) {
      throw InvalidBackupFormatException(e.message);
    } on StateError {
      throw BackupDecryptionException();
    }

    final Map<String, dynamic> backupData;
    try {
      backupData = jsonDecode(plainJson) as Map<String, dynamic>;
    } catch (e) {
      throw InvalidBackupFormatException(
          'Backup payload is not valid JSON: $e');
    }

    if (backupData['v'] != 1) {
      throw InvalidBackupFormatException(
          'Unsupported backup version: ${backupData['v']}');
    }
    if (backupData['type'] != 'profile_backup') {
      throw InvalidBackupFormatException(
          'Invalid backup type: ${backupData['type']}');
    }

    final profileMap = backupData['profile'] as Map<String, dynamic>;
    final profile = Profile.fromJson(profileMap);

    final existingIndex = _profiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex != -1) {
      throw ProfileAlreadyExistsException(profile.id);
    }

    // Mirror the real ProfileRepository: guard the cross-profile keypair-
    // ownership invariant before mutating state. Fail loud on collision.
    assertUniqueKeypairOwnership([..._profiles, profile]);

    _profiles.add(profile);

    return profile;
  }
}
