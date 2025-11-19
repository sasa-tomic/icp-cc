import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/identity_profile.dart';
import '../models/identity_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/secure_identity_repository.dart';
import '../utils/identity_generator.dart';
import '../utils/principal.dart';

class IdentityController extends ChangeNotifier {
  IdentityController({
    SecureIdentityRepository? secureRepository,
    MarketplaceOpenApiService? marketplaceService,
    SharedPreferences? preferences,
  })  : _secureRepository = secureRepository ?? SecureIdentityRepository(),
        _preferencesOverride = preferences;

  static const String _activeIdentityPrefsKey = 'active_identity_id';

  final SecureIdentityRepository _secureRepository;
  final SharedPreferences? _preferencesOverride;
  SharedPreferences? _preferences;

  final List<IdentityRecord> _identities = <IdentityRecord>[];
  final Map<String, IdentityProfile> _profiles = <String, IdentityProfile>{};

  bool _initialized = false;
  bool _isBusy = false;
  bool _restoredActiveIdentity = false;
  String? _activeIdentityId;

  List<IdentityRecord> get identities => List<IdentityRecord>.unmodifiable(_identities);
  bool get isBusy => _isBusy;
  String? get activeIdentityId => _activeIdentityId;
  bool get hasActiveIdentity => _activeIdentityId != null;
  IdentityRecord? get activeIdentity =>
      _identities.firstWhereOrNull((IdentityRecord record) => record.id == _activeIdentityId);

  IdentityProfile? profileForPrincipal(String principal) => _profiles[principal];

  IdentityProfile? profileForRecord(IdentityRecord record) =>
      _profiles[PrincipalUtils.textFromRecord(record)];

  bool isProfileComplete(IdentityRecord record) {
    final IdentityProfile? profile = profileForRecord(record);
    return profile != null && profile.displayName.isNotEmpty;
  }

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
      final List<IdentityRecord> records = await _secureRepository.loadIdentities();
      _identities
        ..clear()
        ..addAll(records);
      await _loadProfilesFromPreferences();
      await _hydrateActiveIdentityFromPreferences();
      await _reconcileActiveIdentity();
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<IdentityRecord> createIdentity({
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
  }) async {
    _setBusy(true);
    try {
      final IdentityRecord record = await IdentityGenerator.generate(
        algorithm: algorithm,
        label: label,
        mnemonic: mnemonic,
        identityCount: _identities.length,
      );
      _identities.add(record);
      await _secureRepository.persistIdentities(_identities);
      await _updateActiveIdentity(record.id);
      notifyListeners();
      return record;
    } finally {
      _setBusy(false);
    }
  }

  Future<IdentityRecord> createIdentityWithProfile({
    required IdentityProfileDraft profileDraft,
    required IdentityRecord identity,
  }) async {
    _setBusy(true);
    try {
      // Persist identity
      _identities.add(identity);
      await _secureRepository.persistIdentities(_identities);
      await _updateActiveIdentity(identity.id);

      // Save profile locally only
      final IdentityProfile profile = IdentityProfile(
        id: identity.id,
        principal: profileDraft.principal,
        displayName: profileDraft.displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _profiles[profile.principal] = profile;
      await _saveProfilesToPreferences();

      notifyListeners();
      return identity;
    } finally {
      _setBusy(false);
    }
  }

  IdentityRecord? findById(String id) {
    return _identities.firstWhereOrNull((IdentityRecord record) => record.id == id);
  }

  Future<void> setActiveIdentity(String? id) async {
    if (id == _activeIdentityId) {
      return;
    }
    if (id != null && findById(id) == null) {
      throw ArgumentError('Identity $id does not exist in controller state.');
    }
    await _updateActiveIdentity(id);
    notifyListeners();
  }

  Future<void> updateLabel({required String id, required String label}) async {
    final IdentityRecord? existing = findById(id);
    if (existing == null) {
      return;
    }
    final int index = _identities.indexOf(existing);
    _identities[index] = existing.copyWith(label: label);
    await _secureRepository.persistIdentities(_identities);
    notifyListeners();
  }

  Future<void> deleteIdentity(String id) async {
    final IdentityRecord? record = findById(id);
    if (record == null) {
      return;
    }
    final String principal = PrincipalUtils.textFromRecord(record);
    await _secureRepository.deleteIdentitySecureData(record.id);
    _identities.remove(record);
    _profiles.remove(principal);
    if (_activeIdentityId == id) {
      await _updateActiveIdentity(null);
    }
    await _secureRepository.persistIdentities(_identities);
    notifyListeners();
  }

  Future<IdentityProfile?> ensureProfileLoaded(IdentityRecord identity) async {
    final String principal = PrincipalUtils.textFromRecord(identity);
    final IdentityProfile? cached = _profiles[principal];
    if (cached != null) {
      return cached;
    }
    // Profile is local-only, return null if not in cache
    return null;
  }

  Future<IdentityProfile> saveProfile({
    required IdentityRecord identity,
    required IdentityProfileDraft draft,
  }) async {
    // Save profile locally only
    final IdentityProfile profile = IdentityProfile(
      id: identity.id,
      principal: draft.principal,
      displayName: draft.displayName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _profiles[profile.principal] = profile;
    await _saveProfilesToPreferences();
    notifyListeners();
    return profile;
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

  Future<void> _hydrateActiveIdentityFromPreferences() async {
    if (_restoredActiveIdentity) {
      return;
    }
    final SharedPreferences prefs = await _prefs();
    final String? storedId = prefs.getString(_activeIdentityPrefsKey);
    if (storedId != null && _identities.any((IdentityRecord record) => record.id == storedId)) {
      _activeIdentityId = storedId;
    } else if (storedId != null) {
      await prefs.remove(_activeIdentityPrefsKey);
      _activeIdentityId = null;
    }
    _restoredActiveIdentity = true;
  }

  Future<void> _reconcileActiveIdentity() async {
    if (_activeIdentityId == null) {
      return;
    }
    final bool exists =
        _identities.any((IdentityRecord record) => record.id == _activeIdentityId);
    if (!exists) {
      await _updateActiveIdentity(null);
    }
  }

  Future<void> _updateActiveIdentity(String? identityId) async {
    _activeIdentityId = identityId;
    final SharedPreferences prefs = await _prefs();
    if (identityId == null) {
      await prefs.remove(_activeIdentityPrefsKey);
    } else {
      await prefs.setString(_activeIdentityPrefsKey, identityId);
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }

  /// Save profiles to SharedPreferences (local storage only)
  Future<void> _saveProfilesToPreferences() async {
    final SharedPreferences prefs = await _prefs();
    final Map<String, dynamic> profilesJson = <String, dynamic>{};

    for (final entry in _profiles.entries) {
      profilesJson[entry.key] = <String, dynamic>{
        'id': entry.value.id,
        'principal': entry.value.principal,
        'displayName': entry.value.displayName,
        'metadata': entry.value.metadata,
        'createdAt': entry.value.createdAt.toIso8601String(),
        'updatedAt': entry.value.updatedAt.toIso8601String(),
      };
    }

    final String encoded = jsonEncode(profilesJson);
    await prefs.setString('identity_profiles', encoded);
  }

  /// Load profiles from SharedPreferences (local storage only)
  Future<void> _loadProfilesFromPreferences() async {
    final SharedPreferences prefs = await _prefs();
    final String? encoded = prefs.getString('identity_profiles');

    if (encoded == null) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      _profiles.clear();
      for (final entry in decoded.entries) {
        final data = entry.value as Map<String, dynamic>;
        final profile = IdentityProfile(
          id: data['id'] as String,
          principal: data['principal'] as String,
          displayName: data['displayName'] as String,
          metadata: (data['metadata'] as Map<String, dynamic>?) ?? <String, dynamic>{},
          createdAt: DateTime.parse(data['createdAt'] as String),
          updatedAt: DateTime.parse(data['updatedAt'] as String),
        );
        _profiles[entry.key] = profile;
      }
    } catch (e) {
      debugPrint('Failed to load identity profiles from preferences: $e');
      _profiles.clear();
    }
  }
}
