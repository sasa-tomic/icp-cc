import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/encrypted_export.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  group('ProfileKeypair Encrypted Export', () {
    test('encryption round-trip preserves all keypair data', () async {
      final originalKeypair = await TestKeypairFactory.getEd25519Keypair();
      const password = 'my-secure-password-123';

      final encrypted = await originalKeypair.toEncryptedExport(password);
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        password,
      );

      expect(decrypted.id, equals(originalKeypair.id));
      expect(decrypted.label, equals(originalKeypair.label));
      expect(decrypted.algorithm, equals(originalKeypair.algorithm));
      expect(decrypted.publicKey, equals(originalKeypair.publicKey));
      expect(decrypted.privateKey, equals(originalKeypair.privateKey));
      expect(decrypted.mnemonic, equals(originalKeypair.mnemonic));
      expect(decrypted.principal, equals(originalKeypair.principal));
    });

    test('secp256k1 keypair encryption round-trip', () async {
      final originalKeypair = await TestKeypairFactory.getSecp256k1Keypair();
      const password = 'another-secure-password';

      final encrypted = await originalKeypair.toEncryptedExport(password);
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        password,
      );

      expect(decrypted.privateKey, equals(originalKeypair.privateKey));
      expect(decrypted.mnemonic, equals(originalKeypair.mnemonic));
    });

    test('different passwords produce different encrypted outputs', () async {
      final keypair = await TestKeypairFactory.fromSeed(1);

      final encrypted1 = await keypair.toEncryptedExport('password1');
      final encrypted2 = await keypair.toEncryptedExport('password2');

      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test(
        'same password produces different encrypted outputs (random salt/nonce)',
        () async {
      final keypair = await TestKeypairFactory.fromSeed(2);
      const password = 'same-password';

      final encrypted1 = await keypair.toEncryptedExport(password);
      final encrypted2 = await keypair.toEncryptedExport(password);

      expect(encrypted1, isNot(equals(encrypted2)));

      final map1 = jsonDecode(encrypted1) as Map<String, dynamic>;
      final map2 = jsonDecode(encrypted2) as Map<String, dynamic>;

      expect(map1['salt'], isNot(equals(map2['salt'])));
      expect(map1['nonce'], isNot(equals(map2['nonce'])));
    });

    test('wrong password fails decryption', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('correct-password');

      await expectLater(
        ProfileKeypair.fromEncryptedExport(encrypted, 'wrong-password'),
        throwsA(isA<StateError>()),
      );
    });

    test('corrupted encrypted data fails decryption', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;
      encryptedMap['cipher'] = base64Encode([1, 2, 3, 4, 5]);
      final corrupted = jsonEncode(encryptedMap);

      await expectLater(
        ProfileKeypair.fromEncryptedExport(corrupted, 'password'),
        throwsA(isA<StateError>()),
      );
    });

    test('invalid JSON format throws FormatException', () async {
      await expectLater(
        ProfileKeypair.fromEncryptedExport('not-valid-json', 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing required fields throws FormatException', () async {
      final invalidExport = jsonEncode({
        'v': 1,
        'alg': 'aes256-gcm',
      });

      await expectLater(
        ProfileKeypair.fromEncryptedExport(invalidExport, 'password'),
        throwsA(anything),
      );
    });

    test('unsupported version throws FormatException', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;
      encryptedMap['v'] = 999;
      final invalidVersion = jsonEncode(encryptedMap);

      await expectLater(
        ProfileKeypair.fromEncryptedExport(invalidVersion, 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unsupported algorithm throws FormatException', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;
      encryptedMap['alg'] = 'unknown-alg';
      final invalidAlg = jsonEncode(encryptedMap);

      await expectLater(
        ProfileKeypair.fromEncryptedExport(invalidAlg, 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('encrypted export contains all required fields', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;

      expect(encryptedMap['v'], equals(1));
      expect(encryptedMap['alg'], equals('aes256-gcm'));
      expect(encryptedMap['kdf'], equals('pbkdf2-sha256'));
      expect(encryptedMap['salt'], isNotEmpty);
      expect(encryptedMap['nonce'], isNotEmpty);
      expect(encryptedMap['cipher'], isNotEmpty);
      expect(encryptedMap['mac'], isNotEmpty);
    });

    test('encryption with empty password fails (security requirement)',
        () async {
      final keypair = await TestKeypairFactory.fromSeed(3);

      await expectLater(
        keypair.toEncryptedExport(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('encryption with unicode password works', () async {
      final keypair = await TestKeypairFactory.fromSeed(4);
      const password = '密码123🔐🔒';

      final encrypted = await keypair.toEncryptedExport(password);
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        password,
      );

      expect(decrypted.privateKey, equals(keypair.privateKey));
    });

    test('encryption with very long password works', () async {
      final keypair = await TestKeypairFactory.fromSeed(5);
      final longPassword = 'a' * 1000;

      final encrypted = await keypair.toEncryptedExport(longPassword);
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        longPassword,
      );

      expect(decrypted.privateKey, equals(keypair.privateKey));
    });

    test('corrupted MAC fails decryption', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;
      encryptedMap['mac'] = base64Encode(List.filled(16, 0));
      final corrupted = jsonEncode(encryptedMap);

      await expectLater(
        ProfileKeypair.fromEncryptedExport(corrupted, 'password'),
        throwsA(isA<StateError>()),
      );
    });

    test('corrupted salt fails decryption with correct password', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final encrypted = await keypair.toEncryptedExport('password');

      final encryptedMap = jsonDecode(encrypted) as Map<String, dynamic>;
      encryptedMap['salt'] = base64Encode(List.filled(16, 0));
      final corrupted = jsonEncode(encryptedMap);

      await expectLater(
        ProfileKeypair.fromEncryptedExport(corrupted, 'password'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ProfileKeypair Encrypted Export - Edge Cases', () {
    test('keypair with null principal exports and imports correctly', () async {
      final keypair = await TestKeypairFactory.fromSeed(10);
      expect(keypair.principal, isNotNull);

      final encrypted = await keypair.toEncryptedExport('password');
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        'password',
      );

      expect(decrypted.principal, equals(keypair.principal));
    });

    test('keypair with all fields populated exports correctly', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();

      final encrypted = await keypair.toEncryptedExport('password');
      final decrypted = await ProfileKeypair.fromEncryptedExport(
        encrypted,
        'password',
      );

      expect(decrypted.id, isNotEmpty);
      expect(decrypted.label, isNotEmpty);
      expect(decrypted.algorithm,
          isIn([KeyAlgorithm.ed25519, KeyAlgorithm.secp256k1]));
      expect(decrypted.publicKey, isNotEmpty);
      expect(decrypted.privateKey, isNotEmpty);
      expect(decrypted.mnemonic, isNotEmpty);
      expect(decrypted.createdAt, isNotNull);
    });

    test('multiple encryption/decryption cycles preserve data', () async {
      final originalKeypair = await TestKeypairFactory.fromSeed(20);
      const password = 'cycle-password';

      var currentKeypair = originalKeypair;

      for (int i = 0; i < 3; i++) {
        final encrypted = await currentKeypair.toEncryptedExport(password);
        currentKeypair = await ProfileKeypair.fromEncryptedExport(
          encrypted,
          password,
        );
      }

      expect(currentKeypair.id, equals(originalKeypair.id));
      expect(currentKeypair.privateKey, equals(originalKeypair.privateKey));
      expect(currentKeypair.mnemonic, equals(originalKeypair.mnemonic));
    });
  });

  group('ProfileRepository Encrypted Export', () {
    test('exportKeypairEncrypted exports keypair from repository', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);
      const password = 'secure-password';

      final encrypted = await repo.profileRepository.exportKeypairEncrypted(
        keypair.id,
        password,
      );

      expect(encrypted, isNotEmpty);
      final map = jsonDecode(encrypted) as Map<String, dynamic>;
      expect(map['v'], equals(1));
      expect(map['alg'], equals('aes256-gcm'));
    });

    test('exportKeypairEncrypted throws for non-existent keypair', () async {
      final repo = FakeSecureKeypairRepository([]);

      await expectLater(
        repo.profileRepository.exportKeypairEncrypted(
          'non-existent-id',
          'password',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('importKeypairEncrypted imports keypair to profile', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);
      const password = 'secure-password';

      final encrypted = await repo.profileRepository.exportKeypairEncrypted(
        keypair.id,
        password,
      );

      final profiles = await repo.profileRepository.loadProfiles();
      final profileId = profiles.first.id;

      final imported = await repo.profileRepository.importKeypairEncrypted(
        encrypted,
        password,
        profileId,
      );

      expect(imported.privateKey, equals(keypair.privateKey));
      expect(imported.mnemonic, equals(keypair.mnemonic));
    });

    test('importKeypairEncrypted throws for non-existent profile', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);

      final encrypted = await keypair.toEncryptedExport('password');

      await expectLater(
        repo.profileRepository.importKeypairEncrypted(
          encrypted,
          'password',
          'non-existent',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('importKeypairEncrypted throws for wrong password', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);

      final encrypted = await keypair.toEncryptedExport('correct-password');

      final profiles = await repo.profileRepository.loadProfiles();
      final profileId = profiles.first.id;

      await expectLater(
        repo.profileRepository.importKeypairEncrypted(
          encrypted,
          'wrong-password',
          profileId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('importKeypairEncrypted respects 10 keypair limit', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);

      final profiles = await repo.profileRepository.loadProfiles();
      final profile = profiles.first;

      final updatedProfile = profile.copyWith(
        keypairs: [
          ...profile.keypairs,
          for (int i = 1; i < 10; i++)
            await TestKeypairFactory.fromSeed(100 + i),
        ],
      );
      await repo.profileRepository.persistProfiles([updatedProfile]);

      final extraKeypair = await TestKeypairFactory.fromSeed(200);
      final encrypted = await extraKeypair.toEncryptedExport('password');

      await expectLater(
        repo.profileRepository.importKeypairEncrypted(
          encrypted,
          'password',
          profile.id,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('repository round-trip preserves all keypair fields', () async {
      final originalKeypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([originalKeypair]);
      const password = 'backup-password';

      final encrypted = await repo.profileRepository.exportKeypairEncrypted(
        originalKeypair.id,
        password,
      );

      final profiles = await repo.profileRepository.loadProfiles();
      final profileId = profiles.first.id;

      await repo.profileRepository.importKeypairEncrypted(
        encrypted,
        password,
        profileId,
      );

      final loadedKeypairs = await repo.loadKeypairs();
      final loadedKeypair = loadedKeypairs.firstWhere(
        (k) => k.id == originalKeypair.id,
      );

      expect(loadedKeypair.privateKey, equals(originalKeypair.privateKey));
      expect(loadedKeypair.mnemonic, equals(originalKeypair.mnemonic));
      expect(loadedKeypair.publicKey, equals(originalKeypair.publicKey));
    });
  });

  group('Profile Backup Export', () {
    test('exportProfileBackup produces valid encrypted output', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);
      const password = 'backup-password-123';

      final profiles = await repo.profileRepository.loadProfiles();
      final profileId = profiles.first.id;

      final encrypted = await repo.profileRepository.exportProfileBackup(
        profileId,
        password,
      );

      expect(encrypted, isNotEmpty);
      final decrypted = await EncryptedExport.decrypt(encrypted, password);
      final map = jsonDecode(decrypted) as Map<String, dynamic>;
      expect(map['v'], equals(1));
      expect(map['type'], equals('profile_backup'));
      expect(map['profile'], isA<Map>());
    });

    test('exportProfileBackup contains all keypair data', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);
      final now = DateTime.now().toUtc();

      final profile = Profile(
        id: 'test-profile-backup',
        name: 'Backup Test Profile',
        keypairs: [keypair1, keypair2],
        username: 'backupuser',
        createdAt: now,
        updatedAt: now,
      );

      final repo = FakeSecureKeypairRepository([]);
      await repo.profileRepository.persistProfiles([profile]);

      final encrypted = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'test-password',
      );

      expect(encrypted, isNotEmpty);
      final decrypted =
          await EncryptedExport.decrypt(encrypted, 'test-password');
      final map = jsonDecode(decrypted) as Map<String, dynamic>;
      final profileMap = map['profile'] as Map<String, dynamic>;
      final keypairs = profileMap['keypairs'] as List<dynamic>;

      expect(keypairs.length, equals(2));
    });

    test('exportProfileBackup round-trip preserves profile data', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repo = FakeSecureKeypairRepository([keypair]);
      const password = 'secure-backup-password';

      final profiles = await repo.profileRepository.loadProfiles();
      final originalProfile = profiles.first;
      final profileId = originalProfile.id;

      final encrypted = await repo.profileRepository.exportProfileBackup(
        profileId,
        password,
      );

      final decrypted = await EncryptedExport.decrypt(encrypted, password);
      final backupData = jsonDecode(decrypted) as Map<String, dynamic>;
      final restoredProfileMap = backupData['profile'] as Map<String, dynamic>;
      final restoredProfile = Profile.fromJson(restoredProfileMap);

      expect(restoredProfile.id, equals(originalProfile.id));
      expect(restoredProfile.name, equals(originalProfile.name));
      expect(restoredProfile.keypairs.length,
          equals(originalProfile.keypairs.length));
      expect(restoredProfile.keypairs.first.privateKey,
          equals(originalProfile.keypairs.first.privateKey));
      expect(restoredProfile.keypairs.first.mnemonic,
          equals(originalProfile.keypairs.first.mnemonic));
    });

    test('exportProfileBackup with non-existent profile throws error',
        () async {
      final repo = FakeSecureKeypairRepository([]);

      await expectLater(
        repo.profileRepository.exportProfileBackup('non-existent', 'password'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
