import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/profile_invariants.dart';
import 'package:icp_autorun/services/profile_repository.dart';

import '../../shared/test_keypair_factory.dart';

/// Helper: build a [Profile] with stable ids/timestamps for deterministic tests.
Profile _profile(String id, String name, List<ProfileKeypair> keypairs) {
  final now = DateTime.utc(2024, 1, 1);
  return Profile(
    id: id,
    name: name,
    keypairs: keypairs,
    createdAt: now,
    updatedAt: now,
  );
}

/// Helper: build a [ProfileKeypair] with explicit id/publicKey, but REAL
/// cryptographic key material (never mocked crypto).
ProfileKeypair _keypair({
  required String id,
  required String label,
  required ProfileKeypair source,
  String? publicKey,
}) {
  return ProfileKeypair(
    id: id,
    label: label,
    algorithm: source.algorithm,
    publicKey: publicKey ?? source.publicKey,
    privateKey: source.privateKey,
    mnemonic: source.mnemonic,
    createdAt: source.createdAt,
  );
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  group('assertUniqueKeypairOwnership', () {
    test('passes when each profile owns distinct keypairs', () async {
      final kpA = await TestKeypairFactory.fromSeed(1);
      final kpB = await TestKeypairFactory.fromSeed(2);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      // Returns normally — no throw.
      assertUniqueKeypairOwnership(profiles);
    });

    test('passes for a single profile with multiple distinct keypairs',
        () async {
      final kp1 = await TestKeypairFactory.fromSeed(10);
      final kp2 = await TestKeypairFactory.fromSeed(11);
      final profiles = [_profile('p-a', 'A', [kp1, kp2])];

      assertUniqueKeypairOwnership(profiles);
    });

    test('passes with empty profile list', () {
      assertUniqueKeypairOwnership(<Profile>[]);
    });

    test('throws when two profiles share a keypair id (distinct publicKey)',
        () async {
      final real1 = await TestKeypairFactory.fromSeed(1);
      final real2 = await TestKeypairFactory.fromSeed(2);
      // Two keypairs with the SAME id but distinct publicKey/privateKey.
      final kpA = _keypair(id: 'shared-id', label: 'A', source: real1);
      final kpB = _keypair(id: 'shared-id', label: 'B', source: real2);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      expect(
        () => assertUniqueKeypairOwnership(profiles),
        throwsA(
          isA<KeypairOwnershipViolation>()
              .having((v) => v.field, 'field', 'id')
              .having((v) => v.value, 'value', 'shared-id')
              .having((v) => v.profileIds, 'profileIds', ['p-a', 'p-b']),
        ),
      );
    });

    test(
        'throws when two keypairs share a publicKey under different profiles',
        () async {
      final real = await TestKeypairFactory.fromSeed(3);
      final other = await TestKeypairFactory.fromSeed(4);
      // Different ids, SAME publicKey — defends the backend UNIQUE invariant.
      final kpA = _keypair(id: 'id-a', label: 'A', source: real);
      final kpB =
          _keypair(id: 'id-b', label: 'B', source: other, publicKey: real.publicKey);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      expect(
        () => assertUniqueKeypairOwnership(profiles),
        throwsA(
          isA<KeypairOwnershipViolation>()
              .having((v) => v.field, 'field', 'publicKey')
              .having((v) => v.value, 'value', real.publicKey)
              .having((v) => v.profileIds, 'profileIds', ['p-a', 'p-b']),
        ),
      );
    });

    test('throws on a duplicate keypair id within a single profile', () async {
      final real1 = await TestKeypairFactory.fromSeed(5);
      final real2 = await TestKeypairFactory.fromSeed(6);
      final kpA = _keypair(id: 'dup-id', label: 'A', source: real1);
      final kpB = _keypair(id: 'dup-id', label: 'B', source: real2);
      final profiles = [_profile('p-a', 'A', [kpA, kpB])];

      expect(
        () => assertUniqueKeypairOwnership(profiles),
        throwsA(
          isA<KeypairOwnershipViolation>()
              .having((v) => v.field, 'field', 'id')
              .having((v) => v.value, 'value', 'dup-id'),
        ),
      );
    });

    test('violation message is clear and actionable', () async {
      final real = await TestKeypairFactory.fromSeed(7);
      final kpA = _keypair(id: 'shared', label: 'A', source: real);
      final kpB = _keypair(id: 'shared', label: 'B', source: real);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      late final KeypairOwnershipViolation violation;
      try {
        assertUniqueKeypairOwnership(profiles);
        fail('Expected KeypairOwnershipViolation');
      } on KeypairOwnershipViolation catch (e) {
        violation = e;
      }

      expect(violation.toString(), contains('KeypairOwnershipViolation'));
      expect(violation.toString(), contains('exactly ONE profile'));
      expect(violation.toString(), contains('p-a'));
      expect(violation.toString(), contains('p-b'));
    });
  });

  group('ProfileRepository ownership guard', () {
    late Directory tempDir;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('a3a_invariant_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    ProfileRepository newRepo() =>
        ProfileRepository(overrideDirectory: tempDir);

    test('persistProfiles then loadProfiles round-trips distinct keypairs',
        () async {
      final kpA = await TestKeypairFactory.fromSeed(1);
      final kpB = await TestKeypairFactory.fromSeed(2);
      final profiles = [
        _profile('p-a', 'Profile A', [kpA]),
        _profile('p-b', 'Profile B', [kpB]),
      ];

      final repo = newRepo();
      await repo.persistProfiles(profiles);

      // Fresh repo instance simulates an app restart.
      final loaded = await newRepo().loadProfiles();
      expect(loaded, hasLength(2));
      expect(
        loaded.map((p) => p.id).toSet(),
        containsAll(<String>['p-a', 'p-b']),
      );

      // Private material round-tripped through secure storage.
      final loadedA = loaded.firstWhere((p) => p.id == 'p-a');
      expect(loadedA.keypairs.single.privateKey, kpA.privateKey);
      expect(loadedA.keypairs.single.mnemonic, kpA.mnemonic);
    });

    test('persistProfiles refuses to write a shared keypair id', () async {
      final real1 = await TestKeypairFactory.fromSeed(1);
      final real2 = await TestKeypairFactory.fromSeed(2);
      final kpA = _keypair(id: 'shared-id', label: 'A', source: real1);
      final kpB = _keypair(id: 'shared-id', label: 'B', source: real2);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      final repo = newRepo();
      await expectLater(
        () => repo.persistProfiles(profiles),
        throwsA(isA<KeypairOwnershipViolation>()),
      );

      // Nothing corrupt should have been written — a fresh load returns no
      // profiles. (WU-1: the JSON store is created lazily on first successful
      // write, so after a refused persist the `profiles` key is simply absent
      // rather than holding an empty placeholder file. Asserting via the public
      // contract keeps this resilient to the storage substrate.)
      final reloaded = await newRepo().loadProfiles();
      expect(reloaded, isEmpty);
    });

    test('persistProfiles refuses to write a shared publicKey', () async {
      final real = await TestKeypairFactory.fromSeed(3);
      final other = await TestKeypairFactory.fromSeed(4);
      final kpA = _keypair(id: 'id-a', label: 'A', source: real);
      final kpB = _keypair(
          id: 'id-b', label: 'B', source: other, publicKey: real.publicKey);
      final profiles = [
        _profile('p-a', 'A', [kpA]),
        _profile('p-b', 'B', [kpB]),
      ];

      await expectLater(
        () => newRepo().persistProfiles(profiles),
        throwsA(isA<KeypairOwnershipViolation>()),
      );
    });

    test(
        'loadProfiles fails loud on a corrupt store and backs it up '
        'under profiles_corrupt', () async {
      final kp = await TestKeypairFactory.fromSeed(7);

      // Pre-populate secure storage for the shared keypair id, so loadProfiles
      // actually materializes the keypair (otherwise it would be dropped
      // before the guard could inspect it).
      const storage = FlutterSecureStorage();
      await storage.write(
        key: 'keypair_private_key_${kp.id}',
        value: kp.privateKey,
      );
      await storage.write(
        key: 'keypair_mnemonic_${kp.id}',
        value: kp.mnemonic,
      );

      // Hand-craft profiles.json where BOTH profiles reference the SAME
      // keypair id — the exact corruption this guard exists to catch.
      final corruptJson = jsonEncode(<String, dynamic>{
        'version': 1,
        'profiles': [
          <String, dynamic>{
            'id': 'p-a',
            'name': 'A',
            'keypairs': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': kp.id,
                'label': 'shared',
                'algorithm': 'ed25519',
                'publicKey': kp.publicKey,
                'createdAt': '2024-01-01T00:00:00.000Z',
              },
            ],
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
          },
          <String, dynamic>{
            'id': 'p-b',
            'name': 'B',
            'keypairs': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': kp.id,
                'label': 'shared',
                'algorithm': 'ed25519',
                'publicKey': kp.publicKey,
                'createdAt': '2024-01-01T00:00:00.000Z',
              },
            ],
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
          },
        ],
      });

      final file = File('${tempDir.path}/profiles.json');
      await file.writeAsString(corruptJson);

      // Must throw — never silently dedupe.
      await expectLater(
        () => newRepo().loadProfiles(),
        throwsA(isA<KeypairOwnershipViolation>()),
      );

      // The corrupt content must be preserved aside (not deleted, not silently
      // rewritten) so the dev can inspect/recover. WU-1: the backup is written
      // to a portable sibling store key (`profiles_corrupt`) so recovery works
      // on IO (→ `profiles_corrupt.json` here) AND on Web (→ localStorage).
      final corruptBackup = File('${tempDir.path}/profiles_corrupt.json');
      expect(await corruptBackup.exists(), isTrue);
      final backedUp =
          jsonDecode(await corruptBackup.readAsString()) as Map<String, dynamic>;
      expect(backedUp['profiles'] as List, hasLength(2));

      // The live store must have been reset to a safe empty state.
      final liveContent =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(liveContent['profiles'] as List, isEmpty);
    });
  });
}
