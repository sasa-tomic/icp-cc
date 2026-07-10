import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:icp_autorun/utils/encrypted_export.dart';

import '../models/profile.dart';
import '../models/profile_keypair.dart';
import '../utils/profile_errors.dart';
import 'json_store.dart';
import 'profile_invariants.dart';

/// ProfileRepository manages secure storage of user profiles
///
/// Architecture: Profile-Centric Storage
/// - Stores Profile objects (not individual keypairs)
/// - Each Profile contains 1-10 keypairs
/// - Sensitive data (private keys, mnemonics) stored in platform secure storage
/// - Non-sensitive data (public keys, metadata) stored in a JSON document store
///
/// Storage Strategy:
/// - JSON store key `'profiles'` (file on IO, localStorage on Web — see
///   [JsonDocumentStore]): Profile metadata + keypair public data.
/// - Secure Storage: Private keys and mnemonics (per-keypair). Unchanged by
///   WU-1 — `flutter_secure_storage` already works on Web (IndexedDB + AES).
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

  /// The IO test-injection directory (see [openJsonDocumentStore]). On Web this
  /// is always `null` — no caller can supply a `Directory` in the browser.
  final Directory? _overrideDirectory;
  final FlutterSecureStorage _secureStorage;

  JsonDocumentStore? _store;

  /// Lazily resolves the JSON document store for this repository. The store is
  /// built once from [_overrideDirectory] (test injection) or the
  /// platform-default location, then cached.
  JsonDocumentStore get _docStore =>
      _store ??= openJsonDocumentStore(overrideDirectory: _overrideDirectory);

  /// Single source for this repository's JSON-store key name.
  static const String _storeKey = 'profiles';

  // Key prefixes for secure storage
  static const String _privateKeyPrefix = 'keypair_private_key_';
  static const String _mnemonicPrefix = 'keypair_mnemonic_';

  /// The empty-store payload written on first run and after corruption reset.
  /// Kept schema-identical to the original `profiles.json` so existing data and
  /// tests are unaffected.
  static String _encodeEmptyStore() => jsonEncode(
        <String, dynamic>{
          'version': 1,
          'profiles': <Map<String, dynamic>>[],
        },
      );

  /// Load all profiles from storage
  Future<List<Profile>> loadProfiles() async {
    final String? content = await _docStore.read(_storeKey);
    // Absent or whitespace-only key → fresh store → no profiles (no error).
    if (content == null) {
      return <Profile>[];
    }

    try {
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

          // Load keypairs with sensitive data from secure storage. W6-5: use
          // the nullable form (mirroring the `profiles` read above) so an
          // old/malformed profile object omitting `keypairs` (or carrying it as
          // null) is treated as an empty list — never a TypeError that would
          // escape the FormatException corruption-recovery handler below.
          final List<dynamic> keypairsJson =
              profileData['keypairs'] as List<dynamic>? ?? <dynamic>[];
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

      // Fail loud if the decoded state already violates the keypair-ownership
      // invariant (a keypair claimed by >1 profile). Never silently dedupe —
      // that would mask permanent key loss. Mirrors the FormatException
      // corrupt-store recovery below, but throws so the app surfaces the error.
      assertUniqueKeypairOwnership(result);

      return result;
    } on FormatException {
      // Parsing failed: back up the corrupt payload (portably — into a sibling
      // store key, so this works on IO AND Web), reset to a safe empty state,
      // and surface the incident loudly. Never silently drop user data.
      debugPrint('ProfileRepository: corrupt `$_storeKey` store detected; '
          'backing up to `${_storeKey}_bak` and resetting.');
      await _docStore.write('${_storeKey}_bak', content);
      await _docStore.write(_storeKey, _encodeEmptyStore());
      return <Profile>[];
    } on KeypairOwnershipViolation {
      // Back the corrupt payload aside (as `<key>_corrupt`) for inspection /
      // recovery, reset the store to a safe empty state, then rethrow so the
      // violation is surfaced loudly — never silently dedupe or delete.
      debugPrint('ProfileRepository: keypair-ownership violation in '
          '`$_storeKey` store; backing up to `${_storeKey}_corrupt` and '
          'resetting.');
      await _docStore.write('${_storeKey}_corrupt', content);
      await _docStore.write(_storeKey, _encodeEmptyStore());
      rethrow;
    }
  }

  /// Persist profiles to storage
  Future<void> persistProfiles(List<Profile> profiles) async {
    // Fail loud BEFORE any write: refuse to persist state that violates the
    // keypair-ownership invariant (a keypair must belong to exactly ONE
    // profile). See profile_invariants.dart.
    assertUniqueKeypairOwnership(profiles);

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

    // Store non-sensitive data in the JSON document store
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

    await _docStore.write(_storeKey, jsonEncode(payload));
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
    // Translate the generic crypto-layer contract (EncryptedExport throws
    // FormatException for envelope problems, StateError exclusively for AES-GCM
    // authentication failure) into typed profile-backup exceptions at the
    // boundary — the origin of a backup import failure. The UI then branches
    // on type, never on an English substring (TD-4).
    final String plainJson;
    try {
      plainJson = await EncryptedExport.decrypt(encryptedJson, password);
    } on FormatException catch (e) {
      throw InvalidBackupFormatException(e.message);
    } on StateError {
      throw BackupDecryptionException();
    }

    final Map<String, dynamic> backupData;
    try {
      backupData = jsonDecode(plainJson) as Map<String, dynamic>;
    } catch (e) {
      throw InvalidBackupFormatException(
          'Backup payload is not valid JSON: $e');
    }

    if (backupData['v'] != 1) {
      throw InvalidBackupFormatException(
          'Unsupported backup version: ${backupData['v']}');
    }
    if (backupData['type'] != 'profile_backup') {
      throw InvalidBackupFormatException(
          'Invalid backup type: ${backupData['type']}');
    }

    final profileMap = backupData['profile'] as Map<String, dynamic>;
    final profile = Profile.fromJson(profileMap);

    final profiles = await loadProfiles();
    final existingIndex = profiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex != -1) {
      throw ProfileAlreadyExistsException(profile.id);
    }

    // Guard the cross-profile keypair-ownership invariant BEFORE mutating state.
    // A backup restored into a store that already owns one of its keypairs (by
    // id OR publicKey) would create two profiles claiming the same keypair —
    // permanent key-loss hazard (flat secure-storage keys are not profile-
    // scoped). Fail loud; never silently merge or drop the colliding key.
    assertUniqueKeypairOwnership([...profiles, profile]);

    profiles.add(profile);
    await persistProfiles(profiles);

    return profile;
  }
}
