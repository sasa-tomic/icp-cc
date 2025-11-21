import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import '../models/profile_keypair.dart';
import '../services/profile_repository.dart';
import '../utils/keypair_generator.dart';

/// ProfileController manages user profiles
///
/// Architecture: Profile-Centric Model
/// - Each Profile is an isolated container (like browser profiles)
/// - Each Profile contains 1-10 keypairs
/// - Each Profile maps to exactly ONE backend account
/// - NO cross-profile operations
///
/// Key operations:
/// - createProfile: Generates initial keypair + creates Profile container
/// - addKeypair: Generates NEW keypair within current profile (no importing)
/// - deleteProfile: Removes profile and ALL its keypairs
/// - setActiveProfile: Switch between profiles
class ProfileController extends ChangeNotifier {
  ProfileController({
    ProfileRepository? profileRepository,
    SharedPreferences? preferences,
  })  : _profileRepository = profileRepository ?? ProfileRepository(),
        _preferencesOverride = preferences;

  static const String _activeProfilePrefsKey = 'active_profile_id';
  static const _uuid = Uuid();

  final ProfileRepository _profileRepository;
  final SharedPreferences? _preferencesOverride;
  SharedPreferences? _preferences;

  final List<Profile> _profiles = <Profile>[];

  bool _initialized = false;
  bool _isBusy = false;
  bool _restoredActiveProfile = false;
  String? _activeProfileId;

  List<Profile> get profiles => List<Profile>.unmodifiable(_profiles);
  bool get isBusy => _isBusy;
  String? get activeProfileId => _activeProfileId;
  bool get hasActiveProfile => _activeProfileId != null;
  Profile? get activeProfile => _profiles
      .firstWhereOrNull((Profile profile) => profile.id == _activeProfileId);

  /// Get primary keypair of active profile (for backward compatibility)
  ProfileKeypair? get activeKeypair => activeProfile?.primaryKeypair;

  Future<void> ensureLoaded() async {
    if (_initialized) {
      return;
    }
    await refresh();
    _initialized = true;
  }

  Future<void> refresh() async {
    _setBusy(true);
    try {
      final List<Profile> profiles = await _profileRepository.loadProfiles();
      _profiles
        ..clear()
        ..addAll(profiles);
      await _hydrateActiveProfileFromPreferences();
      await _reconcileActiveProfile();
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  /// Create a new profile with initial keypair
  ///
  /// This is the ONLY way to create profiles. It:
  /// 1. Generates a new keypair
  /// 2. Creates Profile container with the keypair
  /// 3. Saves to storage
  /// 4. Optionally sets as active
  ///
  /// Returns the created Profile.
  Future<Profile> createProfile({
    required String profileName,
    required KeyAlgorithm algorithm,
    String? mnemonic,
    bool setAsActive = false,
  }) async {
    _setBusy(true);
    try {
      // Generate initial keypair for this profile
      final ProfileKeypair keypair = await KeypairGenerator.generate(
        algorithm: algorithm,
        label: '$profileName - Primary',
        mnemonic: mnemonic,
        keypairCount: 0,
      );

      // Create Profile container
      final now = DateTime.now().toUtc();
      final profile = Profile(
        id: _uuid.v4(),
        name: profileName,
        keypairs: [keypair],
        username: null, // Not registered yet
        createdAt: now,
        updatedAt: now,
      );

      _profiles.add(profile);
      await _profileRepository.persistProfiles(_profiles);

      if (setAsActive) {
        await _updateActiveProfile(profile.id);
      }

      notifyListeners();
      return profile;
    } finally {
      _setBusy(false);
    }
  }

  /// Add a NEW keypair to an existing profile
  ///
  /// IMPORTANT: This GENERATES a new keypair for the profile.
  /// It does NOT import/share keypairs from other profiles.
  ///
  /// Returns the updated Profile.
  Future<Profile> addKeypairToProfile({
    required String profileId,
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
  }) async {
    _setBusy(true);
    try {
      final Profile? profile = findById(profileId);
      if (profile == null) {
        throw ArgumentError('Profile $profileId does not exist.');
      }

      if (!profile.canAddKeypair) {
        throw StateError(
            'Profile already has maximum number of keypairs (10).');
      }

      // Generate NEW keypair for this profile
      final ProfileKeypair keypair = await KeypairGenerator.generate(
        algorithm: algorithm,
        label: label ?? '${profile.name} - Key ${profile.keypairs.length + 1}',
        mnemonic: mnemonic,
        keypairCount: profile.keypairs.length,
      );

      // Update profile with new keypair
      final updatedKeypairs = [...profile.keypairs, keypair];
      final updatedProfile = profile.copyWith(
        keypairs: updatedKeypairs,
        updatedAt: DateTime.now().toUtc(),
      );

      final index = _profiles.indexOf(profile);
      _profiles[index] = updatedProfile;
      await _profileRepository.persistProfiles(_profiles);

      notifyListeners();
      return updatedProfile;
    } finally {
      _setBusy(false);
    }
  }

  /// Update profile metadata (name)
  Future<void> updateProfileName({
    required String profileId,
    required String name,
  }) async {
    final Profile? profile = findById(profileId);
    if (profile == null) {
      return;
    }

    final updatedProfile = profile.copyWith(
      name: name,
      updatedAt: DateTime.now().toUtc(),
    );

    final index = _profiles.indexOf(profile);
    _profiles[index] = updatedProfile;
    await _profileRepository.persistProfiles(_profiles);
    notifyListeners();
  }

  /// Update profile username (after registration)
  Future<void> updateProfileUsername({
    required String profileId,
    required String username,
  }) async {
    final Profile? profile = findById(profileId);
    if (profile == null) {
      return;
    }

    final updatedProfile = profile.copyWith(
      username: username,
      updatedAt: DateTime.now().toUtc(),
    );

    final index = _profiles.indexOf(profile);
    _profiles[index] = updatedProfile;
    await _profileRepository.persistProfiles(_profiles);
    notifyListeners();
  }

  /// Clear profile username (unlink from account)
  Future<void> clearProfileUsername({required String profileId}) async {
    final Profile? profile = findById(profileId);
    if (profile == null) {
      return;
    }

    final updatedProfile = Profile(
      id: profile.id,
      name: profile.name,
      keypairs: profile.keypairs,
      username: null, // Explicitly clear
      activeKeypairId: profile.activeKeypairId,
      createdAt: profile.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    final index = _profiles.indexOf(profile);
    _profiles[index] = updatedProfile;
    await _profileRepository.persistProfiles(_profiles);
    notifyListeners();
  }

  /// Set the active keypair for a profile (used for signing operations)
  Future<void> setActiveKeypair({
    required String profileId,
    required String keypairId,
  }) async {
    final Profile? profile = findById(profileId);
    if (profile == null) {
      throw ArgumentError('Profile $profileId does not exist.');
    }

    final keypair = profile.getKeypair(keypairId);
    if (keypair == null) {
      throw ArgumentError(
          'Keypair $keypairId does not exist in profile $profileId.');
    }

    final updatedProfile = profile.copyWith(
      activeKeypairId: keypairId,
      updatedAt: DateTime.now().toUtc(),
    );

    final index = _profiles.indexOf(profile);
    _profiles[index] = updatedProfile;
    await _profileRepository.persistProfiles(_profiles);
    notifyListeners();
  }

  /// Update keypair label within a profile
  Future<void> updateKeypairLabel({
    required String profileId,
    required String keypairId,
    required String label,
  }) async {
    final Profile? profile = findById(profileId);
    if (profile == null) {
      return;
    }

    final keypair = profile.getKeypair(keypairId);
    if (keypair == null) {
      return;
    }

    final updatedKeypairs = profile.keypairs.map((k) {
      if (k.id == keypairId) {
        return k.copyWith(label: label);
      }
      return k;
    }).toList();

    final updatedProfile = profile.copyWith(
      keypairs: updatedKeypairs,
      updatedAt: DateTime.now().toUtc(),
    );

    final index = _profiles.indexOf(profile);
    _profiles[index] = updatedProfile;
    await _profileRepository.persistProfiles(_profiles);
    notifyListeners();
  }

  /// Delete a keypair from a profile
  ///
  /// Cannot delete the last keypair (profile must have at least one)
  Future<void> deleteKeypair({
    required String profileId,
    required String keypairId,
  }) async {
    _setBusy(true);
    try {
      final Profile? profile = findById(profileId);
      if (profile == null) {
        return;
      }

      if (profile.keypairs.length == 1) {
        throw StateError(
            'Cannot delete the last keypair. Delete the profile instead.');
      }

      final updatedKeypairs =
          profile.keypairs.where((k) => k.id != keypairId).toList();

      final updatedProfile = profile.copyWith(
        keypairs: updatedKeypairs,
        updatedAt: DateTime.now().toUtc(),
      );

      final index = _profiles.indexOf(profile);
      _profiles[index] = updatedProfile;

      // Delete secure data for this keypair
      await _profileRepository.deleteKeypairSecureData(keypairId);
      await _profileRepository.persistProfiles(_profiles);

      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  /// Delete entire profile and ALL its keypairs
  Future<void> deleteProfile(String profileId) async {
    _setBusy(true);
    try {
      final Profile? profile = findById(profileId);
      if (profile == null) {
        return;
      }

      // Delete all secure data for this profile
      await _profileRepository.deleteProfileSecureData(profile);

      _profiles.remove(profile);

      if (_activeProfileId == profileId) {
        await _updateActiveProfile(null);
      }

      await _profileRepository.persistProfiles(_profiles);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Profile? findById(String id) {
    return _profiles.firstWhereOrNull((Profile profile) => profile.id == id);
  }

  /// Find profile that contains a specific keypair
  Profile? findByKeypairId(String keypairId) {
    return _profiles.firstWhereOrNull(
      (Profile profile) => profile.keypairs.any((k) => k.id == keypairId),
    );
  }

  Future<void> setActiveProfile(String? id) async {
    if (id == _activeProfileId) {
      return;
    }
    if (id != null && findById(id) == null) {
      throw ArgumentError('Profile $id does not exist in controller state.');
    }
    await _updateActiveProfile(id);
    notifyListeners();
  }

  Future<SharedPreferences> _prefs() async {
    final SharedPreferences? override = _preferencesOverride;
    if (override != null) {
      return override;
    }
    final SharedPreferences? cached = _preferences;
    if (cached != null) {
      return cached;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _preferences = prefs;
    return prefs;
  }

  Future<void> _hydrateActiveProfileFromPreferences() async {
    if (_restoredActiveProfile) {
      return;
    }
    final SharedPreferences prefs = await _prefs();
    final String? storedId = prefs.getString(_activeProfilePrefsKey);
    if (storedId != null &&
        _profiles.any((Profile profile) => profile.id == storedId)) {
      _activeProfileId = storedId;
    } else if (storedId != null) {
      await prefs.remove(_activeProfilePrefsKey);
      _activeProfileId = null;
    }
    _restoredActiveProfile = true;
  }

  Future<void> _reconcileActiveProfile() async {
    if (_activeProfileId == null) {
      return;
    }
    final bool exists =
        _profiles.any((Profile profile) => profile.id == _activeProfileId);
    if (!exists) {
      await _updateActiveProfile(null);
    }
  }

  Future<void> _updateActiveProfile(String? profileId) async {
    _activeProfileId = profileId;
    final SharedPreferences prefs = await _prefs();
    if (profileId == null) {
      await prefs.remove(_activeProfilePrefsKey);
    } else {
      await prefs.setString(_activeProfilePrefsKey, profileId);
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }
}
