import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:icp_autorun/utils/encrypted_export.dart';
import 'package:path_provider/path_provider.dart';

import '../models/profile.dart';
import '../models/profile_keypair.dart';

/// ProfileRepository manages secure storage of user profiles
///
/// Architecture: Profile-Centric Storage
/// - Stores Profile objects (not individual keypairs)
/// - Each Profile contains 1-10 keypairs
/// - Sensitive data (private keys, mnemonics) stored in platform secure storage
/// - Non-sensitive data (public keys, metadata) stored in regular file storage
///
/// Storage Strategy:
/// - profiles.json: Profile metadata + keypair public data
/// - Secure Storage: Private keys and mnemonics (per-keypair)
class ProfileRepository {
  ProfileRepository({Directory? overrideDirectory})
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

  // Key prefixes for secure storage
  static const String _privateKeyPrefix = 'keypair_private_key_';
  static const String _mnemonicPrefix = 'keypair_mnemonic_';

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      throw UnsupportedError('ProfileRepository does not support web yet.');
    }

    Directory directory;
    final Directory? override = _overrideDirectory;
    if (override != null) {
      directory = override;
    } else {
      try {
        directory = await getApplicationSupportDirectory();
      } catch (e, st) {
        debugPrint('ProfileRepository: path_provider unavailable, '
            'falling back to temp dir: $e\n$st');
        // In test or restricted environments, fall back to temporary directory
        directory = await Directory.systemTemp.createTemp('icp_autorun_test_');
      }
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final File file = File('${directory.path}/profiles.json');
    if (!await file.exists()) {
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'profiles': <Map<String, dynamic>>[],
        }),
      );
    }

    _storeFile = file;
    _initialized = true;
  }

  /// Load all profiles from storage
  Future<List<Profile>> loadProfiles() async {
    await _ensureInitialized();
    final File file = _storeFile!;

    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <Profile>[];
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid profile store format.');
      }

      final List<dynamic> profilesJson =
          decoded['profiles'] as List<dynamic>? ?? <dynamic>[];

      final List<Profile> result = [];
      for (final dynamic item in profilesJson) {
        if (item is Map<String, dynamic>) {
          final Map<String, dynamic> profileData =
              Map<String, dynamic>.from(item);

          // Load keypairs with sensitive data from secure storage
          final List<dynamic> keypairsJson =
              profileData['keypairs'] as List<dynamic>;
          final List<ProfileKeypair> keypairs = [];

          for (final dynamic keypairItem in keypairsJson) {
            if (keypairItem is Map<String, dynamic>) {
              final Map<String, dynamic> keypairData =
                  Map<String, dynamic>.from(keypairItem);

              // Retrieve sensitive data from secure storage
              final String? privateKey = await _secureStorage.read(
                key: '$_privateKeyPrefix${keypairData['id'] as String}',
              );
              final String? mnemonic = await _secureStorage.read(
                key: '$_mnemonicPrefix${keypairData['id'] as String}',
              );

              if (privateKey != null && mnemonic != null) {
                keypairData['privateKey'] = privateKey;
                keypairData['mnemonic'] = mnemonic;
                keypairs.add(ProfileKeypair.fromJson(keypairData));
              }
            }
          }

          if (keypairs.isNotEmpty) {
            profileData['keypairs'] = keypairs.map((k) => k.toJson()).toList();
            result.add(Profile.fromJson(profileData));
          }
        }
      }

      return result;
    } on FormatException {
      // If parsing fails, back up the corrupted file and start fresh
      final String backupPath = '${file.path}.bak';
      await file.copy(backupPath);
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'profiles': <Map<String, dynamic>>[],
        }),
      );
      return <Profile>[];
    }
  }

  /// Persist profiles to storage
  Future<void> persistProfiles(List<Profile> profiles) async {
    await _ensureInitialized();
    final File file = _storeFile!;

    // Store sensitive data in secure storage for all keypairs
    for (final Profile profile in profiles) {
      for (final ProfileKeypair keypair in profile.keypairs) {
        await _secureStorage.write(
          key: '$_privateKeyPrefix${keypair.id}',
          value: keypair.privateKey,
        );
        await _secureStorage.write(
          key: '$_mnemonicPrefix${keypair.id}',
          value: keypair.mnemonic,
        );
      }
    }

    // Store non-sensitive data in regular file
    final List<Map<String, dynamic>> publicProfiles = profiles
        .map((Profile profile) => <String, dynamic>{
              'id': profile.id,
              'name': profile.name,
              'username': profile.username,
              'activeKeypairId': profile.activeKeypairId,
              'keypairs': profile.keypairs
                  .map((ProfileKeypair keypair) => <String, dynamic>{
                        'id': keypair.id,
                        'label': keypair.label,
                        'algorithm': keyAlgorithmToString(keypair.algorithm),
                        'publicKey': keypair.publicKey,
                        'createdAt': keypair.createdAt.toIso8601String(),
                        if (keypair.principal != null)
                          'principal': keypair.principal,
                      })
                  .toList(),
              'createdAt': profile.createdAt.toIso8601String(),
              'updatedAt': profile.updatedAt.toIso8601String(),
            })
        .toList();

    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 1,
      'profiles': publicProfiles,
    };

    await file.writeAsString(jsonEncode(payload));
  }

  /// Delete secure data for a specific keypair
  Future<void> deleteKeypairSecureData(String keypairId) async {
    await _secureStorage.delete(key: '$_privateKeyPrefix$keypairId');
    await _secureStorage.delete(key: '$_mnemonicPrefix$keypairId');
  }

  /// Delete secure data for all keypairs in a profile
  Future<void> deleteProfileSecureData(Profile profile) async {
    for (final keypair in profile.keypairs) {
      await deleteKeypairSecureData(keypair.id);
    }
  }

  /// Delete all secure data
  Future<void> deleteAllSecureData() async {
    await _secureStorage.deleteAll();
  }

  /// Get private key for a specific keypair
  Future<String?> getPrivateKey(String keypairId) async {
    try {
      return await _secureStorage.read(key: '$_privateKeyPrefix$keypairId');
    } catch (e) {
      throw Exception(
          'Failed to retrieve private key for keypair $keypairId: $e');
    }
  }

  /// Get mnemonic for a specific keypair
  Future<String?> getMnemonic(String keypairId) async {
    try {
      return await _secureStorage.read(key: '$_mnemonicPrefix$keypairId');
    } catch (e) {
      throw Exception('Failed to retrieve mnemonic for keypair $keypairId: $e');
    }
  }

  /// Export a keypair as encrypted JSON string for disaster recovery
  /// The keypair must exist in the loaded profiles
  Future<String> exportKeypairEncrypted(
    String keypairId,
    String password,
  ) async {
    final profiles = await loadProfiles();
    ProfileKeypair? keypair;
    for (final profile in profiles) {
      final found = profile.getKeypair(keypairId);
      if (found != null) {
        keypair = found;
        break;
      }
    }

    if (keypair == null) {
      throw ArgumentError('Keypair not found: $keypairId');
    }

    return await keypair.toEncryptedExport(password);
  }

  /// Import an encrypted keypair and add it to a profile
  /// Returns the imported keypair
  Future<ProfileKeypair> importKeypairEncrypted(
    String encryptedJson,
    String password,
    String profileId,
  ) async {
    final keypair = await ProfileKeypair.fromEncryptedExport(
      encryptedJson,
      password,
    );

    final profiles = await loadProfiles();
    final profileIndex = profiles.indexWhere((p) => p.id == profileId);

    if (profileIndex == -1) {
      throw ArgumentError('Profile not found: $profileId');
    }

    final profile = profiles[profileIndex];
    if (profile.keypairs.length >= 10) {
      throw StateError('Profile already has maximum keypairs (10)');
    }

    final updatedKeypairs = [...profile.keypairs, keypair];
    profiles[profileIndex] = profile.copyWith(
      keypairs: updatedKeypairs,
      updatedAt: DateTime.now(),
    );

    await persistProfiles(profiles);
    return keypair;
  }

  Future<String> exportProfileBackup(String profileId, String password) async {
    final profiles = await loadProfiles();
    final profile = profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => throw ArgumentError('Profile not found: $profileId'),
    );

    final backupData = <String, dynamic>{
      'v': 1,
      'type': 'profile_backup',
      'profile': profile.toJson(),
    };

    return EncryptedExport.encrypt(jsonEncode(backupData), password);
  }

  Future<Profile> importProfileBackup(
      String encryptedJson, String password) async {
    final plainJson = await EncryptedExport.decrypt(encryptedJson, password);
    final backupData = jsonDecode(plainJson) as Map<String, dynamic>;

    if (backupData['v'] != 1) {
      throw FormatException('Unsupported backup version: ${backupData['v']}');
    }
    if (backupData['type'] != 'profile_backup') {
      throw FormatException('Invalid backup type: ${backupData['type']}');
    }

    final profileMap = backupData['profile'] as Map<String, dynamic>;
    final profile = Profile.fromJson(profileMap);

    final profiles = await loadProfiles();
    final existingIndex = profiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex != -1) {
      throw StateError('Profile with ID ${profile.id} already exists');
    }

    profiles.add(profile);
    await persistProfiles(profiles);

    return profile;
  }
}
