import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/profile_keypair.dart';
import '../models/profile.dart';
import 'profile_repository.dart';

/// DEPRECATED: Use ProfileRepository instead
///
/// This class is kept for backward compatibility during migration.
/// It wraps ProfileRepository and converts between the old ProfileKeypair
/// interface and the new Profile-centric interface.
///
/// Migration strategy:
/// - Old code: ProfileKeypair = standalone keypair
/// - New code: Profile with 1 keypair
/// - Each ProfileKeypair is converted to a Profile with a single keypair
class SecureKeypairRepository {
  SecureKeypairRepository({Directory? overrideDirectory})
      : _profileRepository =
            ProfileRepository(overrideDirectory: overrideDirectory);

  final ProfileRepository _profileRepository;

  static const _uuid = Uuid();

  /// Get the underlying ProfileRepository for direct access
  ProfileRepository get profileRepository => _profileRepository;

  /// Load keypairs (converted from profiles)
  ///
  /// MIGRATION: Each Profile is converted to a list of ProfileKeypairs (one per keypair)
  /// This maintains backward compatibility with old code expecting individual keypairs.
  Future<List<ProfileKeypair>> loadKeypairs() async {
    // Load profiles from new storage
    final List<Profile> profiles = await _profileRepository.loadProfiles();

    // Convert each profile's keypairs to ProfileKeypairs
    final List<ProfileKeypair> result = [];
    for (final profile in profiles) {
      // Each keypair becomes an ProfileKeypair
      for (final keypair in profile.keypairs) {
        result.add(keypair); // ProfileKeypair IS ProfileKeypair (typedef)
      }
    }

    return result;
  }

  /// Persist keypairs (converted to profiles)
  ///
  /// MIGRATION: Each ProfileKeypair is converted to a Profile with one keypair
  Future<void> persistKeypairs(List<ProfileKeypair> keypairs) async {
    // Convert each ProfileKeypair to a Profile with one keypair
    final List<Profile> profiles = keypairs.map((ProfileKeypair keypair) {
      return Profile(
        id: _uuid.v4(), // Generate new profile ID
        name: keypair.label, // Use keypair label as profile name
        keypairs: <ProfileKeypair>[keypair], // Single keypair in profile
        username: null, // Not registered yet
        createdAt: keypair.createdAt,
        updatedAt: keypair.createdAt,
      );
    }).toList();

    // Save to new profile storage
    await _profileRepository.persistProfiles(profiles);
  }

  Future<void> deleteKeypairSecureData(String keypairId) async {
    // Delete sensitive data (delegates to ProfileRepository)
    await _profileRepository.deleteKeypairSecureData(keypairId);
  }

  Future<void> deleteAllSecureData() async {
    // Delete all secure data (delegates to ProfileRepository)
    await _profileRepository.deleteAllSecureData();
  }

  /// Retrieves a private key from secure storage for cryptographic operations
  Future<String?> getPrivateKey(String keypairId) async {
    try {
      return await _profileRepository.getPrivateKey(keypairId);
    } catch (e) {
      // Fail fast - don't silently ignore errors
      throw Exception(
          'Failed to retrieve private key for keypair $keypairId: $e');
    }
  }
}
