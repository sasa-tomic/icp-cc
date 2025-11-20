import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/identity_record.dart';
import '../models/profile.dart';
import 'profile_repository.dart';

/// DEPRECATED: Use ProfileRepository instead
///
/// This class is kept for backward compatibility during migration.
/// It wraps ProfileRepository and converts between the old IdentityRecord
/// interface and the new Profile-centric interface.
///
/// Migration strategy:
/// - Old code: IdentityRecord = standalone keypair
/// - New code: Profile with 1 keypair
/// - Each IdentityRecord is converted to a Profile with a single keypair
class SecureIdentityRepository {
  SecureIdentityRepository({Directory? overrideDirectory})
      : _profileRepository = ProfileRepository(overrideDirectory: overrideDirectory);

  final ProfileRepository _profileRepository;

  static const _uuid = Uuid();

  /// Get the underlying ProfileRepository for direct access
  ProfileRepository get profileRepository => _profileRepository;

  /// Load identities (converted from profiles)
  ///
  /// MIGRATION: Each Profile is converted to a list of IdentityRecords (one per keypair)
  /// This maintains backward compatibility with old code expecting individual keypairs.
  Future<List<IdentityRecord>> loadIdentities() async {
    // Load profiles from new storage
    final List<Profile> profiles = await _profileRepository.loadProfiles();

    // Convert each profile's keypairs to IdentityRecords
    final List<IdentityRecord> result = [];
    for (final profile in profiles) {
      // Each keypair becomes an IdentityRecord
      for (final keypair in profile.keypairs) {
        result.add(keypair); // ProfileKeypair IS IdentityRecord (typedef)
      }
    }

    return result;
  }

  /// Persist identities (converted to profiles)
  ///
  /// MIGRATION: Each IdentityRecord is converted to a Profile with one keypair
  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    // Convert each IdentityRecord to a Profile with one keypair
    final List<Profile> profiles = identities.map((IdentityRecord identity) {
      return Profile(
        id: _uuid.v4(), // Generate new profile ID
        name: identity.label, // Use keypair label as profile name
        keypairs: <ProfileKeypair>[identity], // Single keypair in profile
        username: null, // Not registered yet
        createdAt: identity.createdAt,
        updatedAt: identity.createdAt,
      );
    }).toList();

    // Save to new profile storage
    await _profileRepository.persistProfiles(profiles);
  }

  Future<void> deleteIdentitySecureData(String identityId) async {
    // Delete sensitive data (delegates to ProfileRepository)
    await _profileRepository.deleteKeypairSecureData(identityId);
  }

  Future<void> deleteAllSecureData() async {
    // Delete all secure data (delegates to ProfileRepository)
    await _profileRepository.deleteAllSecureData();
  }

  /// Retrieves a private key from secure storage for cryptographic operations
  Future<String?> getPrivateKey(String identityId) async {
    try {
      return await _profileRepository.getPrivateKey(identityId);
    } catch (e) {
      // Fail fast - don't silently ignore errors
      throw Exception('Failed to retrieve private key for identity $identityId: $e');
    }
  }
}