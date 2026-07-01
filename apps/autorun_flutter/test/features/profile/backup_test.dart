import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/encrypted_export.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  group('Profile Backup', () {
    test('full backup/restore round-trip preserves all data', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);
      final profile = Profile(
        id: 'test-profile-1',
        name: 'My Profile',
        keypairs: [keypair1, keypair2],
        username: 'testuser',
        activeKeypairId: keypair2.id,
        createdAt: DateTime.parse('2024-01-15T10:30:00Z'),
        updatedAt: DateTime.parse('2024-01-20T14:45:00Z'),
      );

      final repo = FakeSecureKeypairRepository([keypair1]);
      await repo.profileRepository.persistProfiles([profile]);

      const password = 'secure-backup-password';
      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        password,
      );

      final newRepo = FakeSecureKeypairRepository([]);
      final restored = await newRepo.profileRepository.importProfileBackup(
        backup,
        password,
      );

      expect(restored.id, equals(profile.id));
      expect(restored.name, equals(profile.name));
      expect(restored.username, equals(profile.username));
      expect(restored.activeKeypairId, equals(profile.activeKeypairId));
      expect(restored.keypairs.length, equals(2));

      expect(restored.keypairs[0].privateKey, equals(keypair1.privateKey));
      expect(restored.keypairs[0].mnemonic, equals(keypair1.mnemonic));
      expect(restored.keypairs[1].privateKey, equals(keypair2.privateKey));
      expect(restored.keypairs[1].mnemonic, equals(keypair2.mnemonic));
    });

    test('backup includes all keypairs', () async {
      final keypairs = <ProfileKeypair>[];
      for (int i = 0; i < 5; i++) {
        keypairs.add(await TestKeypairFactory.fromSeed(100 + i));
      }

      final profile = Profile(
        id: 'multi-keypair-profile',
        name: 'Multi-Keypair Profile',
        keypairs: keypairs,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final newRepo = FakeSecureKeypairRepository([]);
      final restored = await newRepo.profileRepository.importProfileBackup(
        backup,
        'password',
      );

      expect(restored.keypairs.length, equals(5));
      for (int i = 0; i < 5; i++) {
        expect(
          restored.keypairs[i].privateKey,
          equals(keypairs[i].privateKey),
        );
        expect(restored.keypairs[i].mnemonic, equals(keypairs[i].mnemonic));
      }
    });

    test('wrong password fails restore', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'correct-password',
      );

      await expectLater(
        repo.profileRepository.importProfileBackup(backup, 'wrong-password'),
        throwsA(isA<StateError>()),
      );
    });

    test('corrupted backup fails restore', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final backupMap = jsonDecode(backup) as Map<String, dynamic>;
      backupMap['cipher'] = base64Encode([1, 2, 3, 4, 5]);
      final corrupted = jsonEncode(backupMap);

      await expectLater(
        repo.profileRepository.importProfileBackup(corrupted, 'password'),
        throwsA(isA<StateError>()),
      );
    });

    test('can import to new repository (simulates new device)', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(10);
      final keypair2 = await TestKeypairFactory.fromSeed(11);
      final originalProfile = Profile(
        id: 'device1-profile',
        name: 'Device 1 Profile',
        keypairs: [keypair1, keypair2],
        username: 'devuser',
        createdAt: DateTime.parse('2024-02-01T00:00:00Z'),
        updatedAt: DateTime.parse('2024-02-15T12:00:00Z'),
      );

      final originalRepo = FakeSecureKeypairRepository([keypair1]);
      await originalRepo.profileRepository.persistProfiles([originalProfile]);

      final backup = await originalRepo.profileRepository.exportProfileBackup(
        originalProfile.id,
        'backup-password',
      );

      final newDeviceRepo = FakeSecureKeypairRepository([]);
      final restoredProfile = await newDeviceRepo.profileRepository
          .importProfileBackup(backup, 'backup-password');

      expect(restoredProfile.id, equals(originalProfile.id));
      expect(restoredProfile.name, equals(originalProfile.name));
      expect(restoredProfile.keypairs.length, equals(2));
      expect(
        restoredProfile.keypairs[0].privateKey,
        equals(keypair1.privateKey),
      );
      expect(
        restoredProfile.keypairs[1].privateKey,
        equals(keypair2.privateKey),
      );

      final loadedProfiles =
          await newDeviceRepo.profileRepository.loadProfiles();
      expect(loadedProfiles.length, equals(1));
      expect(loadedProfiles.first.id, equals(originalProfile.id));
    });

    test('backup format contains required fields', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'format-test-profile',
        name: 'Format Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final backupMap = jsonDecode(backup) as Map<String, dynamic>;

      expect(backupMap['v'], equals(1));
      expect(backupMap['alg'], equals('aes256-gcm'));
      expect(backupMap['kdf'], equals('pbkdf2-sha256'));
      expect(backupMap['salt'], isNotEmpty);
      expect(backupMap['nonce'], isNotEmpty);
      expect(backupMap['cipher'], isNotEmpty);
      expect(backupMap['mac'], isNotEmpty);
    });

    test('different passwords produce different backups', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup1 = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password1',
      );
      final backup2 = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password2',
      );

      expect(backup1, isNot(equals(backup2)));
    });

    test('same password produces different backups (random salt/nonce)',
        () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      const password = 'same-password';
      final backup1 = await repo.profileRepository.exportProfileBackup(
        profile.id,
        password,
      );
      final backup2 = await repo.profileRepository.exportProfileBackup(
        profile.id,
        password,
      );

      expect(backup1, isNot(equals(backup2)));

      final map1 = jsonDecode(backup1) as Map<String, dynamic>;
      final map2 = jsonDecode(backup2) as Map<String, dynamic>;

      expect(map1['salt'], isNot(equals(map2['salt'])));
      expect(map1['nonce'], isNot(equals(map2['nonce'])));
    });

    test('export throws for non-existent profile', () async {
      final repo = FakeSecureKeypairRepository([]);

      await expectLater(
        repo.profileRepository.exportProfileBackup('non-existent', 'password'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('import throws for duplicate profile id', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'duplicate-id-profile',
        name: 'Original',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      await expectLater(
        repo.profileRepository.importProfileBackup(backup, 'password'),
        throwsA(isA<StateError>()),
      );
    });

    test('backup with profile containing 10 keypairs (maximum)', () async {
      final keypairs = <ProfileKeypair>[];
      for (int i = 0; i < 10; i++) {
        keypairs.add(await TestKeypairFactory.fromSeed(200 + i));
      }

      final profile = Profile(
        id: 'max-keypair-profile',
        name: 'Max Keypairs',
        keypairs: keypairs,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final newRepo = FakeSecureKeypairRepository([]);
      final restored = await newRepo.profileRepository.importProfileBackup(
        backup,
        'password',
      );

      expect(restored.keypairs.length, equals(10));
    });

    test('invalid JSON format throws FormatException', () async {
      final repo = FakeSecureKeypairRepository([]);

      await expectLater(
        repo.profileRepository
            .importProfileBackup('not-valid-json', 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unsupported backup version throws FormatException', () async {
      final repo = FakeSecureKeypairRepository([]);

      final invalidBackup = jsonEncode({
        'v': 999,
        'type': 'profile_backup',
        'profile': {'id': 'test'},
      });

      await expectLater(
        repo.profileRepository.importProfileBackup(invalidBackup, 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid backup type throws FormatException', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final plainJson = await Future.value(
        _decryptForTest(backup, 'password'),
      );
      final backupMap = jsonDecode(plainJson) as Map<String, dynamic>;
      backupMap['type'] = 'invalid_type';
      final modifiedBackup = jsonEncode(backupMap);

      await expectLater(
        repo.profileRepository.importProfileBackup(modifiedBackup, 'password'),
        throwsA(isA<FormatException>()),
      );
    });

    test('corrupted MAC fails restore', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'test-profile',
        name: 'Test',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final repo = FakeSecureKeypairRepository([keypair]);
      await repo.profileRepository.persistProfiles([profile]);

      final backup = await repo.profileRepository.exportProfileBackup(
        profile.id,
        'password',
      );

      final backupMap = jsonDecode(backup) as Map<String, dynamic>;
      backupMap['mac'] = base64Encode(List.filled(16, 0));
      final corrupted = jsonEncode(backupMap);

      await expectLater(
        repo.profileRepository.importProfileBackup(corrupted, 'password'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

Future<String> _decryptForTest(String encryptedJson, String password) async {
  return EncryptedExport.decrypt(encryptedJson, password);
}
