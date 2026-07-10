import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/profile_repository.dart';

import '../../shared/test_keypair_factory.dart';

/// W6-5 — type-safety of the per-profile `keypairs` field read in
/// `ProfileRepository.loadProfiles`.
///
/// The sibling `profiles` field read uses the nullable form
/// `as List<dynamic>? ?? <dynamic>[]` (missing/null → empty list, no throw).
/// The `keypairs` read historically used a non-nullable `as List<dynamic>`
/// cast, so an old/malformed profile object omitting `keypairs` (or carrying
/// it as `null`) threw a `TypeError` — NOT caught by the `on FormatException`
/// corruption-recovery handler, so it propagated as a confusing type error.
/// These tests pin the consistent (line-84) behaviour: missing/null keypairs is
/// treated as an empty keypairs list, never a throw.
void main() {
  FlutterSecureStorage.setMockInitialValues({});

  late Directory tempDir;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('w65_keypairs_field_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProfileRepository newRepo() => ProfileRepository(overrideDirectory: tempDir);

  /// Writes the given store payload verbatim to `profiles.json`.
  Future<void> seedStore(Map<String, dynamic> store) async {
    final file = File('${tempDir.path}/profiles.json');
    await file.writeAsString(jsonEncode(store));
  }

  group('W6-5: missing/null per-profile keypairs field', () {
    test('profile omitting `keypairs` loads without throwing (TypeError guard)',
        () async {
      await seedStore(<String, dynamic>{
        'version': 1,
        'profiles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p-orphan',
            'name': 'Orphan',
            // 'keypairs' intentionally OMITTED — old/malformed schema. Before
            // W6-5 this threw `TypeError` (uncaught by the FormatException
            // recovery handler) and propagated as a confusing type error.
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
          },
        ],
      });

      // Must NOT throw a TypeError (or anything). The orphan profile has no
      // materialisable keypairs, so it is dropped — consistent with the
      // line-84 pattern (missing `profiles` → empty list → nothing iterated).
      final List<Profile> loaded = await newRepo().loadProfiles();
      expect(loaded, isEmpty);
    });

    test('profile with `keypairs: null` loads without throwing', () async {
      await seedStore(<String, dynamic>{
        'version': 1,
        'profiles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p-null',
            'name': 'Null',
            'keypairs': null, // explicit null — same crash class as omitted
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
          },
        ],
      });

      final List<Profile> loaded = await newRepo().loadProfiles();
      expect(loaded, isEmpty);
    });

    // Regression guard: the fix must not break the happy path. A well-formed
    // profile carrying a REAL keypair still loads (uses real crypto material,
    // per the project's "no mocked cryptography" rule). The neighbouring orphan
    // (missing keypairs) must be silently skipped without aborting the load.
    test('an orphan profile does not abort loading a sibling with real keypairs',
        () async {
      final kp = await TestKeypairFactory.fromSeed(42);

      // Pre-populate secure storage so the real keypair materialises on load.
      const storage = FlutterSecureStorage();
      await storage.write(key: 'keypair_private_key_${kp.id}', value: kp.privateKey);
      await storage.write(key: 'keypair_mnemonic_${kp.id}', value: kp.mnemonic);

      await seedStore(<String, dynamic>{
        'version': 1,
        'profiles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p-orphan',
            'name': 'Orphan',
            // 'keypairs' OMITTED — must be skipped, not crash the whole load.
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
          },
          <String, dynamic>{
            'id': 'p-real',
            'name': 'Real',
            'keypairs': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': kp.id,
                'label': 'real',
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

      final List<Profile> loaded = await newRepo().loadProfiles();

      // The orphan was dropped; the real-keypair profile survived intact.
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'p-real');
      expect(loaded.single.keypairs, hasLength(1));
      expect(loaded.single.keypairs.single.id, kp.id);
      // Real private material round-tripped through secure storage.
      expect(loaded.single.keypairs.single.privateKey, kp.privateKey);
    });
  });
}
