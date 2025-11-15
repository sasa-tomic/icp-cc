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
        _marketplaceService = marketplaceService ?? MarketplaceOpenApiService(),
        _preferencesOverride = preferences;

  static const String _activeIdentityPrefsKey = 'active_identity_id';

  final SecureIdentityRepository _secureRepository;
  final MarketplaceOpenApiService _marketplaceService;
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

  bool isProfileComplete(IdentityRecord record) =>
      profileForRecord(record)?.isComplete ?? false;

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
    final IdentityProfile? remote =
        await _marketplaceService.fetchIdentityProfile(principal: principal);
    if (remote != null) {
      _profiles[principal] = remote;
      notifyListeners();
    }
    return remote;
  }

  Future<IdentityProfile> saveProfile({
    required IdentityRecord identity,
    required IdentityProfileDraft draft,
  }) async {
    final IdentityProfile profile = await _marketplaceService.upsertIdentityProfile(draft);
    _profiles[profile.principal] = profile;
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
}
