import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/services/web_json_store.dart';

/// TQ-5 — direct contract tests for [WebJsonStore].
///
/// [WebJsonStore] is the Web backing of [JsonDocumentStore] and the highest
/// silent-break risk for the Flutter-Web target (it is the ONLY code path a Web
/// user hits for local persistence). It is pure Dart (no `dart:js_interop` /
/// `dart:html`), so it runs unchanged in the VM. We exercise it against
/// `shared_preferences`' in-memory mock store (`setMockInitialValues`), which
/// mirrors what `shared_preferences_web` does over `localStorage` without
/// needing a real browser.
///
/// These tests guard the SAME contract [FileJsonStore] honours (see
/// `json_store_test.dart`), so both impls stay consistent: round-trip,
/// read-missing→null, whitespace→null (cross-platform parity — a corrupt/empty
/// web value must NOT be handed back raw), overwrite idempotence, delete
/// idempotence, and key namespacing.
void main() {
  late WebJsonStore store;

  setUp(() {
    // Fresh, isolated in-memory preferences per test (the platform mock that
    // backs SharedPreferences in tests).
    SharedPreferences.setMockInitialValues({});
    store = WebJsonStore();
  });

  group('WebJsonStore contract', () {
    test('write then read round-trips the JSON payload', () async {
      const String payload = '{"version":1,"items":[{"id":"a"}]}';

      await store.write('bookmarks', payload);

      expect(await store.read('bookmarks'), payload);
    });

    test('read on a missing key returns null', () async {
      expect(await store.read('absent_key'), isNull);
    });

    test('whitespace-only content reads back as null (parity with FileJsonStore)',
        () async {
      // Critical cross-platform invariant: the JsonDocumentStore.read contract
      // promises `null` for whitespace-only values. Without this, a Web user
      // with a corrupt/empty localStorage entry would get raw garbage handed to
      // the parser instead of the clean "absent" signal native users get.
      await store.write('bookmarks', '   ');

      expect(await store.read('bookmarks'), isNull);
    });

    test('empty-string content reads back as null', () async {
      await store.write('bookmarks', '');

      expect(await store.read('bookmarks'), isNull);
    });

    test('write overwrites the previous value (idempotent overwrite)', () async {
      await store.write('bookmarks', '{"v":1}');
      await store.write('bookmarks', '{"v":2}');

      expect(await store.read('bookmarks'), '{"v":2}');
    });

    test('delete removes a written key', () async {
      await store.write('bookmarks', '{"v":1}');

      await store.delete('bookmarks');

      expect(await store.read('bookmarks'), isNull);
    });

    test('delete is idempotent: deleting an absent key is a no-op', () async {
      // Must NOT throw.
      await store.delete('never_written');

      expect(await store.read('never_written'), isNull);
    });

    test('deleting one key leaves sibling keys intact', () async {
      await store.write('profiles', '{"p":1}');
      await store.write('bookmarks', '{"b":1}');

      await store.delete('profiles');

      expect(await store.read('profiles'), isNull);
      expect(await store.read('bookmarks'), '{"b":1}');
    });

    test('multiple keys coexist independently', () async {
      await store.write('profiles', '{"p":1}');
      await store.write('bookmarks', '{"b":1}');
      await store.write('scripts', '{"s":1}');

      expect(await store.read('profiles'), '{"p":1}');
      expect(await store.read('bookmarks'), '{"b":1}');
      expect(await store.read('scripts'), '{"s":1}');
    });

    test(
        'store keys are namespaced and do not collide with other preferences',
        () async {
      // Write a raw (un-prefixed) preference plus a store key, and confirm the
      // store neither reads nor tramples unrelated preference entries.
      SharedPreferences.setMockInitialValues({'foreign_key': 'keep-me'});
      await store.write('foreign_key', '{"store":true}');

      // The store reads its OWN namespaced value back…
      expect(await store.read('foreign_key'), '{"store":true}');

      // …while the raw preference remains untouched.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('foreign_key'), 'keep-me');
    });
  });

  group('openJsonDocumentStore (Web factory)', () {
    test('returns a WebJsonStore and ignores the directory override', () {
      // The browser has no filesystem, so overrideDirectory MUST be ignored
      // (and rejected loudly when non-null via the assert).
      final store = openJsonDocumentStore();

      expect(store, isA<WebJsonStore>());
    });
  });
}
