import 'dart:io';

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
