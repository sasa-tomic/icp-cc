import 'package:flutter/foundation.dart';

import '../models/identity_record.dart';
import '../services/identity_repository.dart';
import '../services/secure_identity_repository.dart';
import '../utils/identity_generator.dart';

class IdentityController extends ChangeNotifier {
  IdentityController(this._repository, {SecureIdentityRepository? secureRepository})
      : _secureRepository = secureRepository ?? SecureIdentityRepository();

  final IdentityRepository _repository;
  final SecureIdentityRepository _secureRepository;
  final List<IdentityRecord> _identities = <IdentityRecord>[];

  bool _initialized = false;
  bool _isBusy = false;

  List<IdentityRecord> get identities =>
      List<IdentityRecord>.unmodifiable(_identities);
  bool get isBusy => _isBusy;

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
      // First, try to load from secure storage
      List<IdentityRecord> records = await _secureRepository.loadIdentities();

      // If no secure identities exist, try to migrate from insecure storage
      if (records.isEmpty) {
        final List<IdentityRecord> insecureRecords = await _repository.loadIdentities();
        if (insecureRecords.isNotEmpty) {
          // Migrate to secure storage
          await _secureRepository.migrateFromInsecureStorage(insecureRecords);
          records = await _secureRepository.loadIdentities();

          // Clear the old insecure storage after successful migration
          await _repository.persistIdentities(<IdentityRecord>[]);
        }
      }

      _identities
        ..clear()
        ..addAll(records);
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
      notifyListeners();
      return record;
    } finally {
      _setBusy(false);
    }
  }

  IdentityRecord? findById(String id) {
    try {
      return _identities.firstWhere((IdentityRecord record) => record.id == id);
    } on StateError {
      return null;
    }
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
    final IdentityRecord? toDelete = _identities.where((IdentityRecord record) => record.id == id).firstOrNull;
    if (toDelete != null) {
      await _secureRepository.deleteIdentitySecureData(toDelete.id);
    }
    _identities.removeWhere((IdentityRecord record) => record.id == id);
    await _secureRepository.persistIdentities(_identities);
    notifyListeners();
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }
}
