import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/bookmarks_service.dart';

/// Regression tests for F-3 / QS-3: a corrupt bookmarks file must NEVER be
/// silently overwritten with empty (or single-entry) data.
///
/// Strategy: mock the `path_provider` method channel so
/// `getApplicationDocumentsDirectory()` points at a fresh per-test temp dir,
/// seed the bookmarks file directly, then assert on both the thrown error type
/// AND that the on-disk bytes are left untouched.
void main() {
  // The method channel path_provider listens on.
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempDir;
  late File bookmarksFile;

  // The file name is private in the service; it must stay in sync.
  // (Documented here so a rename is caught loudly by these tests.)
  const bookmarksFileName = 'icp_bookmarks.json';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('bookmarks_corrupt_test_');
    bookmarksFile = File('${tempDir.path}/$bookmarksFileName');

    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    // Force every test to reload from disk — the service holds a static cache.
    BookmarksService.invalidateCache();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('corrupt-load data-loss protection (F-3 / QS-3)', () {
    test(
        'corrupt (invalid JSON) file: list() throws BookmarksLoadException '
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
        'corrupt file: add() throws (save blocked) and the file is left '
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

    test('empty (0-byte) file throws: a valid empty store is "[]" not ""',
        () async {
      // Decision: an empty file is treated as corruption, not as "no
      // bookmarks". Rationale: the service always writes valid JSON (a valid
      // empty store is the 2 bytes "[]"), so a 0-byte file can only come from
      // a truncated write or external tampering — treating it as empty would
      // risk silent data loss. (A genuinely missing file is the first-run
      // signal; see the missing-file test below.)
      bookmarksFile.writeAsStringSync('');

      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );
      expect(bookmarksFile.readAsStringSync(), '');
    });

    test('whitespace-only file throws', () async {
      bookmarksFile.writeAsStringSync('   \n\t ');

      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );
      expect(bookmarksFile.readAsStringSync(), '   \n\t ');
    });

    test('JSON object (not an array) throws', () async {
      bookmarksFile.writeAsStringSync('{"canister_id":"aaa"}');

      await expectLater(
        BookmarksService.list(),
        throwsA(isA<BookmarksLoadException>()),
      );
      expect(bookmarksFile.readAsStringSync(), '{"canister_id":"aaa"}');
    });
  });

  group('non-corrupt loads', () {
    test('missing file yields [] (first run) — no error', () async {
      // No file seeded.
      expect(await BookmarksService.list(), isEmpty);
      // And nothing was written on a pure read.
      expect(bookmarksFile.existsSync(), isFalse);
    });

    test('valid file loads entries correctly', () async {
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

    test('explicitly-empty store "[]" yields [] — no error', () async {
      // The canonical empty store written by _saveToStorage is "[]", which is
      // valid and must round-trip as empty (distinct from a 0-byte file).
      bookmarksFile.writeAsStringSync('[]');

      expect(await BookmarksService.list(), isEmpty);
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
  });

  group('BookmarksLoadException', () {
    test('carries the underlying cause + path', () {
      final e = BookmarksLoadException(
        const FormatException('Unexpected character'),
        path: '/tmp/icp_bookmarks.json',
      );
      expect(e.cause, isA<FormatException>());
      expect(e.path, '/tmp/icp_bookmarks.json');
      expect(e.toString(), contains('BookmarksLoadException'));
      expect(e.toString(), contains('/tmp/icp_bookmarks.json'));
      expect(e.toString(), contains('Unexpected character'));
    });
  });
}
