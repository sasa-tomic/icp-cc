import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/identity_record.dart';
import '../services/secure_identity_repository.dart';
import 'profile_controller.dart';

/// DEPRECATED: Use ProfileController instead
///
/// This class wraps ProfileController to maintain backward compatibility.
/// Old code works with individual IdentityRecords (keypairs), while new code
/// works with Profiles (containers with 1-10 keypairs).
///
/// Migration strategy:
/// - identities: Flatten all profiles' keypairs into a list
/// - createIdentity: Create profile with one keypair, return keypair
/// - activeIdentity: Return primary keypair of active profile
/// - findById: Search across all profiles' keypairs
///
/// This allows existing code to continue working unchanged while
/// using the profile-centric architecture underneath.
class IdentityController extends ChangeNotifier {
  IdentityController({
    SecureIdentityRepository? secureRepository,
    SharedPreferences? preferences,
  })  : _profileController = ProfileController(
          profileRepository: secureRepository?.profileRepository,
          preferences: preferences,
        );

  final ProfileController _profileController;

  /// Get all keypairs from all profiles (flattened view)
  ///
  /// MIGRATION: Each profile's keypairs are exposed as individual IdentityRecords
  /// This maintains backward compatibility with code expecting a flat list.
  List<IdentityRecord> get identities {
    final List<IdentityRecord> result = [];
    for (final profile in _profileController.profiles) {
      result.addAll(profile.keypairs);
    }
    return List<IdentityRecord>.unmodifiable(result);
  }

  bool get isBusy => _profileController.isBusy;

  /// Get active keypair ID (primary keypair of active profile)
  String? get activeIdentityId => _profileController.activeKeypair?.id;

  bool get hasActiveIdentity => _profileController.hasActiveProfile;

  /// Get active keypair (primary keypair of active profile)
  IdentityRecord? get activeIdentity => _profileController.activeKeypair;

  Future<void> ensureLoaded() async {
    await _profileController.ensureLoaded();
  }

  Future<void> refresh() async {
    await _profileController.refresh();
  }

  /// Create identity (backward compatible)
  ///
  /// MIGRATION: Creates a profile with one keypair, returns the keypair
  /// Old code expects to get an IdentityRecord back.
  Future<IdentityRecord> createIdentity({
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
    bool setAsActive = false,
  }) async {
    final profile = await _profileController.createProfile(
      profileName: label ?? 'Profile ${_profileController.profiles.length + 1}',
      algorithm: algorithm,
      mnemonic: mnemonic,
      setAsActive: setAsActive,
    );

    return profile.primaryKeypair;
  }

  /// Find keypair by ID (searches across all profiles)
  IdentityRecord? findById(String id) {
    for (final profile in _profileController.profiles) {
      final keypair = profile.getKeypair(id);
      if (keypair != null) {
        return keypair;
      }
    }
    return null;
  }

  /// Set active identity (sets profile containing this keypair as active)
  ///
  /// MIGRATION: Finds the profile containing this keypair and activates it
  Future<void> setActiveIdentity(String? id) async {
    if (id == null) {
      await _profileController.setActiveProfile(null);
      return;
    }

    // Find profile containing this keypair
    final profile = _profileController.findByKeypairId(id);
    if (profile == null) {
      throw ArgumentError('Identity $id does not exist in any profile.');
    }

    await _profileController.setActiveProfile(profile.id);
  }

  /// Update keypair label
  Future<void> updateLabel({required String id, required String label}) async {
    // Find profile containing this keypair
    final profile = _profileController.findByKeypairId(id);
    if (profile == null) {
      return;
    }

    await _profileController.updateKeypairLabel(
      profileId: profile.id,
      keypairId: id,
      label: label,
    );
  }

  /// Delete identity (backward compatible)
  ///
  /// MIGRATION: If it's the only keypair in the profile, delete the entire profile.
  /// Otherwise, just delete the keypair.
  Future<void> deleteIdentity(String id) async {
    // Find profile containing this keypair
    final profile = _profileController.findByKeypairId(id);
    if (profile == null) {
      return;
    }

    if (profile.keypairs.length == 1) {
      // Last keypair - delete entire profile
      await _profileController.deleteProfile(profile.id);
    } else {
      // Multiple keypairs - just delete this one
      await _profileController.deleteKeypair(
        profileId: profile.id,
        keypairId: id,
      );
    }
  }

  /// Forward notifications from ProfileController
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _profileController.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _profileController.removeListener(listener);
  }

  @override
  void dispose() {
    _profileController.dispose();
    super.dispose();
  }
}
