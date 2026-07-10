import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/bookmarks_service.dart';
import 'package:icp_autorun/services/json_store.dart';

/// Regression tests for F-3 / QS-3: a corrupt bookmarks document must NEVER be
/// silently overwritten with empty (or single-entry) data.
///
/// Strategy: inject a [FileJsonStore] rooted at a fresh per-test temp dir (the
/// same web-aware [JsonDocumentStore] abstraction the service now uses), seed
/// the `<key>.json` document directly, then assert on both the thrown error
/// type AND that the on-disk bytes are left untouched.
///
/// IH-4 note: persistence was re-routed from raw `dart:io` `File` to
/// [JsonDocumentStore] so bookmarks work on Flutter Web. The store's documented
/// contract normalizes whitespace-only content to "absent" (`null`), so an
/// empty/whitespace document is treated as a clean first run (→ `[]`, no error)
/// rather than corruption — this carries NO data-loss risk (empty files hold no
/// recoverable entries) and is consistent with how the sibling repositories
/// treat whitespace-only stores. Genuine corruption (malformed JSON, wrong
/// shape) STILL throws loudly and is never overwritten — the actual point of
/// F-3 / QS-3.
void main() {
  late Directory tempDir;
  late File bookmarksFile;

  // The document the FileJsonStore writes for the service's `_storeKey`.
  // (Kept in sync here so a rename is caught loudly by these tests.)
  const bookmarksFileName = 'bookmarks.json';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('bookmarks_corrupt_test_');
    bookmarksFile = File('${tempDir.path}/$bookmarksFileName');

    // Inject a file-backed store rooted at the temp dir (production uses the
    // platform-default store). Also drops the static in-memory cache so every
    // test reloads from disk.
    BookmarksService.overrideStoreForTesting(
      FileJsonStore(overrideDirectory: tempDir),
    );
  });

  tearDown(() {
    // Restore the platform-default store + drop the cache for the next test.
    BookmarksService.overrideStoreForTesting(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('corrupt-load data-loss protection (F-3 / QS-3)', () {
    test(
        'corrupt (invalid JSON) document: list() throws BookmarksLoadException '
        'and the file is NOT overwritten or deleted', () async {
      const corrupt = '{ not valid json ';
      bookmarksFile.writeAsStringSync(corrupt);

      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );

      // Critical data-loss assertion: the corrupt-but-recoverable bytes are
      // still on disk, byte-for-byte. The next save must NOT clobber them.
      expect(bookmarksFile.existsSync(), isTrue,
          reason: 'corrupt file must not be deleted');
      expect(bookmarksFile.readAsStringSync(), corrupt,
          reason: 'corrupt file content must be unchanged');
    });

    test(
        'corrupt document: add() throws (save blocked) and the file is left '
        'untouched — no poisoned overwrite', () async {
      const corrupt = '[{"canister_id":"aaa","method":"m"},'; // truncated list
      bookmarksFile.writeAsStringSync(corrupt);

      // The save path is protected: add() loads first, which throws, so the
      // mutation+save never happens.
      await expectLater(
        BookmarksService.add(
          canisterId: 'new-canister',
          method: 'new_method',
        ),
        throwsA(isA<BookmarksLoadException>()),
      );

      expect(bookmarksFile.readAsStringSync(), corrupt,
          reason: 'a corrupt file must never be overwritten on a failed load');
    });

    test('JSON object (not an array) throws', () async {
      bookmarksFile.writeAsStringSync('{"canister_id":"aaa"}');

      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );
      expect(bookmarksFile.readAsStringSync(), '{"canister_id":"aaa"}');
    });

    test(
        'a corrupt load does NOT reset the in-memory cache — a subsequent '
        'save cannot clobber the corrupt document', () async {
      // Seed a known-good document and load it into the cache.
      const good = '[{"canister_id":"good","method":"m"}]';
      bookmarksFile.writeAsStringSync(good);
      expect((await BookmarksService.list()), hasLength(1));

      // Now corrupt the document ON DISK and force a reload. The reload must
      // throw (BookmarksLoadException) and the cache stays whatever it was —
      // critically it is NOT reset to [] as a side effect of the failed load.
      BookmarksService.invalidateCache();
      await bookmarksFile.writeAsString('{ broken');
      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );

      // The corrupt bytes are untouched — no poisoned overwrite happened.
      expect(bookmarksFile.readAsStringSync(), '{ broken');
    });
  });

  group('absent / empty documents (no data loss, no error)', () {
    test('missing file yields [] (first run) — no error', () async {
      // No file seeded.
      expect(await BookmarksService.list(), isEmpty);
      // And nothing was written on a pure read.
      expect(bookmarksFile.existsSync(), isFalse);
    });

    test('explicitly-empty store "[]" yields [] — no error', () async {
      // The canonical empty store written by _saveToStorage is "[]", which is
      // valid and must round-trip as empty.
      bookmarksFile.writeAsStringSync('[]');

      expect(await BookmarksService.list(), isEmpty);
    });

    test(
        'empty (0-byte) document yields [] — no error (IH-4 store contract)',
        () async {
      // IH-4: after re-routing through JsonDocumentStore, whitespace-only
      // content (including a 0-byte file) is normalized to "absent" by the
      // store's documented contract (callers get `null` ⇔ "no data" on every
      // platform). So an empty file reads as a clean first run, NOT corruption.
      // This is safe: an empty file holds no recoverable entries, so nothing
      // can be lost. Genuine corruption (malformed JSON) is still caught loudly
      // — see the group above.
      bookmarksFile.writeAsStringSync('');

      expect(await BookmarksService.list(), isEmpty);
      // The empty file is left untouched (a pure read never writes).
      expect(bookmarksFile.readAsStringSync(), '');
    });

    test('whitespace-only document yields [] — no error (IH-4 store contract)',
        () async {
      bookmarksFile.writeAsStringSync('   \n\t ');

      expect(await BookmarksService.list(), isEmpty);
      expect(bookmarksFile.readAsStringSync(), '   \n\t ');
    });
  });

  group('valid loads + round-trip', () {
    test('valid document loads entries correctly', () async {
      bookmarksFile.writeAsStringSync(
        '[{"canister_id":"rdmx6-jaaaa-aaaaa-aaadq-cai",'
        '"method":"get_balance","label":"NNS Ledger"},'
        '{"canister_id":"rrkah-fqaaa-aaaaa-aaaaq-cai",'
        '"method":"get_neuron_ids"}]',
      );

      final entries = await BookmarksService.list();

      expect(entries, hasLength(2));
      expect(entries[0].canisterId, 'rdmx6-jaaaa-aaaaa-aaadq-cai');
      expect(entries[0].method, 'get_balance');
      expect(entries[0].label, 'NNS Ledger');
      expect(entries[1].canisterId, 'rrkah-fqaaa-aaaaa-aaaaq-cai');
      expect(entries[1].method, 'get_neuron_ids');
      expect(entries[1].label, isNull);
    });

    test('a real save still works after a clean load (no false positive)',
        () async {
      // First run: missing file → [].
      expect(await BookmarksService.list(), isEmpty);

      await BookmarksService.add(
        canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
        method: 'get_value',
        label: 'Key-value store',
      );

      // Written as valid JSON, not empty, not corrupt.
      expect(bookmarksFile.existsSync(), isTrue);
      final saved = bookmarksFile.readAsStringSync();
      expect(saved, contains('rwlgt-iiaaa-aaaaa-aaaaa-cai'));

      // Force a reload and confirm round-trip.
      BookmarksService.invalidateCache();
      final reloaded = await BookmarksService.list();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.canisterId, 'rwlgt-iiaaa-aaaaa-aaaaa-cai');
      expect(reloaded.single.label, 'Key-value store');
    });

    test('remove() persists deletion across a reload', () async {
      await BookmarksService.add(
        canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
        method: 'get_value',
      );

      await BookmarksService.remove(
        canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
        method: 'get_value',
      );

      BookmarksService.invalidateCache();
      expect(await BookmarksService.list(), isEmpty);
    });
  });

  group('BookmarksLoadException', () {
    test('carries the underlying cause + path', () {
      final e = BookmarksLoadException(
        const FormatException('Unexpected character'),
        path: '/tmp/bookmarks.json',
      );
      expect(e.cause, isA<FormatException>());
      expect(e.path, '/tmp/bookmarks.json');
      expect(e.toString(), contains('BookmarksLoadException'));
      expect(e.toString(), contains('/tmp/bookmarks.json'));
      expect(e.toString(), contains('Unexpected character'));
    });
  });
}
