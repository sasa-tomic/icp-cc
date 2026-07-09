import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/json_store.dart';

/// WU-1 — contract tests for [JsonDocumentStore], exercised via the IO impl
/// ([FileJsonStore]) against an override temp directory. These codify the
/// contract BOTH implementations must honour: write→read round-trip,
/// read-missing→null, delete idempotence, delete-missing is a no-op, overwrite
/// is idempotent, and unsafe keys are rejected loudly.
///
/// The Web impl ([WebJsonStore]) is covered separately via the integration test
/// `SharedPreferences` mock; the contract here is platform-agnostic.
void main() {
  late Directory tempDir;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_store_test_');
    store = FileJsonStore(overrideDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JsonDocumentStore contract (FileJsonStore)', () {
    test('write then read round-trips the JSON payload', () async {
      const String payload = '{"version":1,"items":[{"id":"a"}]}';

      await store.write('profiles', payload);

      expect(await store.read('profiles'), payload);
    });

    test('read on a missing key returns null', () async {
      expect(await store.read('absent_key'), isNull);
    });

    test('write of empty/whitespace content reads back as null', () async {
      // The store treats whitespace-only content as absent on read, so callers
      // can rely on `null` ⇔ "no data" regardless of platform.
      await store.write('profiles', '   ');

      expect(await store.read('profiles'), isNull);
    });

    test('write overwrites the previous value (idempotent overwrite)', () async {
      await store.write('profiles', '{"v":1}');
      await store.write('profiles', '{"v":2}');

      expect(await store.read('profiles'), '{"v":2}');
    });

    test('delete removes a written key', () async {
      await store.write('scripts', '{"v":1}');

      await store.delete('scripts');

      expect(await store.read('scripts'), isNull);
    });

    test('delete is idempotent: deleting an absent key is a no-op', () async {
      // Must NOT throw.
      await store.delete('never_written');

      expect(await store.read('never_written'), isNull);
    });

    test('deleting one key leaves sibling keys intact', () async {
      await store.write('profiles', '{"p":1}');
      await store.write('scripts', '{"s":1}');

      await store.delete('profiles');

      expect(await store.read('profiles'), isNull);
      expect(await store.read('scripts'), '{"s":1}');
    });

    test('multiple keys coexist independently', () async {
      await store.write('profiles', '{"p":1}');
      await store.write('scripts', '{"s":1}');
      await store.write('misc', '{"m":1}');

      expect(await store.read('profiles'), '{"p":1}');
      expect(await store.read('scripts'), '{"s":1}');
      expect(await store.read('misc'), '{"m":1}');
    });
  });

  group('JsonDocumentStore key validation', () {
    // Keys are programmer-controlled constants, so an invalid one is a bug —
    // rejected loudly (never turned into a path from untrusted input).
    test('rejects keys with path separators', () async {
      expect(
        () => store.read('../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects keys with dots', () async {
      expect(
        () => store.write('profiles.bak', '{}'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects keys with spaces', () async {
      expect(
        () => store.delete('bad key'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty keys', () async {
      expect(
        () => store.read(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts alphanumeric + underscore keys', () async {
      await store.write('profiles_2026', '{}');

      expect(await store.read('profiles_2026'), '{}');
    });
  });
}
