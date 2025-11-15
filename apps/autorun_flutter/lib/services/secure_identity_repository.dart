import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/identity_record.dart';

/// Secure repository that stores sensitive data (private keys, mnemonics) in platform secure storage
/// and non-sensitive data in regular file storage.
class SecureIdentityRepository {
  SecureIdentityRepository({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory,
        _secureStorage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  final Directory? _overrideDirectory;
  final FlutterSecureStorage _secureStorage;
  bool _initialized = false;
  File? _storeFile;

  // Constants for key prefixes
  static const String _privateKeyPrefix = 'identity_private_key_';
  static const String _mnemonicPrefix = 'identity_mnemonic_';

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      throw UnsupportedError('SecureIdentityRepository does not support web yet.');
    }

    Directory directory;
    final Directory? override = _overrideDirectory;
    if (override != null) {
      directory = override;
    } else {
      try {
        directory = await getApplicationSupportDirectory();
      } catch (_) {
        // In test or restricted environments where platform channels are unavailable,
        // fall back to a temporary directory to avoid hanging initialization.
        directory = await Directory.systemTemp.createTemp('icp_autorun_test_');
      }
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final File file = File('${directory.path}/identities_secure.json');
    if (!await file.exists()) {
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 2,
          'identities': <Map<String, dynamic>>[],
        }),
      );
    }

    _storeFile = file;
    _initialized = true;
  }

  Future<List<IdentityRecord>> loadIdentities() async {
    await _ensureInitialized();
    final File file = _storeFile!;
    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <IdentityRecord>[];
      }
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid identity store format.');
      }
      final List<dynamic> identities =
          decoded['identities'] as List<dynamic>? ?? <dynamic>[];

      final List<IdentityRecord> result = [];
      for (final dynamic item in identities) {
        if (item is Map<String, dynamic>) {
          final Map<String, dynamic> identityData =
              Map<String, dynamic>.from(item);

          // Retrieve sensitive data from secure storage
          final String? privateKey = await _secureStorage.read(
            key: '$_privateKeyPrefix${identityData['id'] as String}',
          );
          final String? mnemonic = await _secureStorage.read(
            key: '$_mnemonicPrefix${identityData['id'] as String}',
          );

          if (privateKey != null && mnemonic != null) {
            identityData['privateKey'] = privateKey;
            identityData['mnemonic'] = mnemonic;

            result.add(IdentityRecord.fromJson(identityData));
          }
        }
      }

      return result;
    } on FormatException {
      // If parsing fails we back up the corrupted file and start fresh.
      final String backupPath = '${file.path}.bak';
      await file.copy(backupPath);
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 2,
          'identities': <Map<String, dynamic>>[],
        }),
      );
      return <IdentityRecord>[];
    }
  }

  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    await _ensureInitialized();
    final File file = _storeFile!;

    // Store sensitive data in secure storage
    for (final IdentityRecord record in identities) {
      await _secureStorage.write(
        key: '$_privateKeyPrefix${record.id}',
        value: record.privateKey,
      );
      await _secureStorage.write(
        key: '$_mnemonicPrefix${record.id}',
        value: record.mnemonic,
      );
    }

    // Store non-sensitive data in regular file (without private keys and mnemonics)
    final List<Map<String, dynamic>> publicIdentities = identities
        .map((IdentityRecord record) => <String, dynamic>{
          'id': record.id,
          'label': record.label,
          'algorithm': keyAlgorithmToString(record.algorithm),
          'publicKey': record.publicKey,
          'createdAt': record.createdAt.toIso8601String(),
        })
        .toList();

    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 2,
      'identities': publicIdentities,
    };
    await file.writeAsString(jsonEncode(payload));
  }

  Future<void> deleteIdentitySecureData(String identityId) async {
    // Delete sensitive data from secure storage
    await _secureStorage.delete(key: '$_privateKeyPrefix$identityId');
    await _secureStorage.delete(key: '$_mnemonicPrefix$identityId');
  }

  Future<void> deleteAllSecureData() async {
    // Delete all identity-related data from secure storage
    await _secureStorage.deleteAll();
  }

  /// Migrates data from the old insecure storage to the new secure storage
  Future<void> migrateFromInsecureStorage(
    List<IdentityRecord> insecureIdentities,
  ) async {
    if (insecureIdentities.isNotEmpty) {
      await persistIdentities(insecureIdentities);
    }
  }
}