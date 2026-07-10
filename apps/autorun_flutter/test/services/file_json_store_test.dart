import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/json_store.dart';
import 'package:icp_autorun/services/file_json_store.dart';

/// TQ-5 — direct tests for [FileJsonStore] + the [openJsonDocumentStore] factory.
///
/// The shared contract (round-trip, missing→null, whitespace→null, overwrite,
/// delete idempotence, key validation) is covered by `json_store_test.dart`.
/// This file covers the [FileJsonStore]-specific wiring NOT exercised there:
/// the on-disk physical layout (`<dir>/<key>.json`), multi-key isolation in a
/// real directory, the `openJsonDocumentStore` factory (with and without an
/// override directory), and loud (non-silent) failure on an unwritable path.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_json_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileJsonStore on-disk layout', () {
    test('writes one `<key>.json` file per key in the storage directory',
        () async {
      final store = FileJsonStore(overrideDirectory: tempDir);

      await store.write('bookmarks', '[]');
      await store.write('profiles', '{}');

      expect(File('${tempDir.path}/bookmarks.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/profiles.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/bookmarks.json').readAsStringSync(), '[]');
    });

    test('delete removes the on-disk `<key>.json` file', () async {
      final store = FileJsonStore(overrideDirectory: tempDir);
      await store.write('bookmarks', '[]');

      await store.delete('bookmarks');

      expect(File('${tempDir.path}/bookmarks.json').existsSync(), isFalse);
    });

    test('reads back exactly what was written to disk (no transformation)',
        () async {
      final store = FileJsonStore(overrideDirectory: tempDir);

      await store.write('bookmarks', '[{"canister_id":"a"}]');

      expect(await store.read('bookmarks'), '[{"canister_id":"a"}]');
    });
  });

  group('openJsonDocumentStore factory (IO)', () {
    test('with an override directory round-trips through a FileJsonStore',
        () async {
      final store = openJsonDocumentStore(overrideDirectory: tempDir);

      expect(store, isA<FileJsonStore>());

      await store.write('bookmarks', '[]');
      expect(await store.read('bookmarks'), '[]');
      // And it landed at the override directory.
      expect(File('${tempDir.path}/bookmarks.json').existsSync(), isTrue);
    });

    test('without an override directory returns a FileJsonStore (no I/O yet)',
        () async {
      // The factory must construct cheaply without touching path_provider or
      // the filesystem — I/O is deferred to the first read/write. On the VM
      // (no path_provider mock) the default store would later fall back to a
      // temp dir, but construction itself must not throw or do I/O.
      final store = openJsonDocumentStore();

      expect(store, isA<FileJsonStore>());
    });
  });

  group('loud failure (no silent swallowing)', () {
    test('writing to a path whose parent is a file throws (not silent)',
        () async {
      // Make the "directory" actually a file — so creating `<key>.json`
      // beneath it must fail loudly rather than silently lose the write.
      final blocker = File('${tempDir.path}/not_a_dir');
      blocker.writeAsStringSync('I am a file, not a directory');
      final store = FileJsonStore(overrideDirectory: Directory(blocker.path));

      await expectLater(
        store.write('bookmarks', '[]'),
        throwsA(anyOf(isA<FileSystemException>(), isA<Exception>())),
      );
    });

    test('reading a corrupt (malformed) document returns the raw bytes — the '
        'caller parses, the store never silently drops data', () async {
      // The store does not interpret JSON: it hands back whatever is on disk so
      // the caller (e.g. BookmarksService) can decide corruption policy. This
      // is what lets the corrupt-load safety net work uniformly.
      File('${tempDir.path}/bookmarks.json').writeAsStringSync('{ broken');
      final store = FileJsonStore(overrideDirectory: tempDir);

      expect(await store.read('bookmarks'), '{ broken');
    });
  });
}
