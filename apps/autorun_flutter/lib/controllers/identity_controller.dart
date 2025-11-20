import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/identity_record.dart';
import '../services/secure_identity_repository.dart';
import '../utils/identity_generator.dart';

/// FIXME - NEEDS COMPLETE REFACTORING:
/// This controller manages "identities" which are actually just individual keypairs.
/// It should be renamed/refactored to ProfileController with these changes:
///
/// Current state (WRONG):
/// - IdentityController manages list of IdentityRecords (individual keypairs)
/// - Each IdentityRecord is treated as independent entity
/// - Implies: Identity = Keypair (1:1)
///
/// Target state (CORRECT - Profile-Centric):
/// - ProfileController manages list of Profiles
/// - Each Profile contains:
///   - Profile metadata (name, settings)
///   - List of ProfileKeypairs (1-10 keypairs)
///   - Account reference (@username)
/// - Structure: Profile → [Keypair, Keypair, ...] + Account
///
/// Required changes:
/// 1. Rename to ProfileController
/// 2. Create Profile model
/// 3. Update storage to support Profile → Keypairs structure
/// 4. Active selection should be activeProfile, not activeIdentity
/// 5. createIdentity() becomes createProfile() which:
///    - Generates initial keypair
///    - Creates Profile container
///    - Optionally registers backend account
///
/// TEMPORARY: Until refactored, each IdentityRecord acts as a profile with one keypair.
class IdentityController extends ChangeNotifier {
  IdentityController({
    SecureIdentityRepository? secureRepository,
    SharedPreferences? preferences,
  })  : _secureRepository = secureRepository ?? SecureIdentityRepository(),
        _preferencesOverride = preferences;

  static const String _activeIdentityPrefsKey = 'active_identity_id';

  final SecureIdentityRepository _secureRepository;
  final SharedPreferences? _preferencesOverride;
  SharedPreferences? _preferences;

  // FIXME: Should be List<Profile> _profiles
  final List<IdentityRecord> _identities = <IdentityRecord>[];

  bool _initialized = false;
  bool _isBusy = false;
  bool _restoredActiveIdentity = false;
  String? _activeIdentityId; // FIXME: Should be _activeProfileId

  // FIXME: Should return List<Profile>
  List<IdentityRecord> get identities => List<IdentityRecord>.unmodifiable(_identities);
  bool get isBusy => _isBusy;
  String? get activeIdentityId => _activeIdentityId; // FIXME: Should be activeProfileId
  bool get hasActiveIdentity => _activeIdentityId != null; // FIXME: Should be hasActiveProfile
  // FIXME: Should be Profile? get activeProfile
  IdentityRecord? get activeIdentity =>
      _identities.firstWhereOrNull((IdentityRecord record) => record.id == _activeIdentityId);

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
      await _hydrateActiveIdentityFromPreferences();
      await _reconcileActiveIdentity();
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  /// FIXME - ARCHITECTURE VIOLATION:
  /// This method creates a standalone keypair, not a complete profile.
  /// Should be renamed to createProfile() with these changes:
  /// 1. Generate initial keypair
  /// 2. Create Profile container with metadata
  /// 3. Prompt for username and register backend account
  /// 4. Store Profile with 1 keypair + account reference
  /// 5. Return Profile (not IdentityRecord)
  Future<IdentityRecord> createIdentity({
    required KeyAlgorithm algorithm,
    String? label, // FIXME: Should be profileName
    String? mnemonic,
    bool setAsActive = false,
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
      if (setAsActive) {
        await _updateActiveIdentity(record.id);
      }
      notifyListeners();
      return record;
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
    await _secureRepository.deleteIdentitySecureData(record.id);
    _identities.remove(record);
    if (_activeIdentityId == id) {
      await _updateActiveIdentity(null);
    }
    await _secureRepository.persistIdentities(_identities);
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
}
