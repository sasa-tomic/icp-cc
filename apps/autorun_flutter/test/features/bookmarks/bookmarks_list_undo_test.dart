// UX-H5 Path 2: deleting a bookmark must offer Undo (re-add) — no destructive
// one-click removal without recourse.
//
// We back BookmarksService with an in-memory JsonDocumentStore stub because
// dart:io file I/O does NOT resolve inside testWidgets()'s fake-async zone
// (a real FileJsonStore's read/write would hang the test on await).
//
// Pattern from diag test: BookmarksService.overrideStoreForTesting(_MemoryStore(seed)).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/bookmarks_service.dart';
import 'package:icp_autorun/services/json_store.dart';
import 'package:icp_autorun/widgets/bookmarks_list.dart';

class _MemoryStore implements JsonDocumentStore {
  String? _data;
  _MemoryStore(this._data);

  @override
  Future<String?> read(String key) async => _data;

  @override
  Future<void> write(String key, String json) async {
    _data = json;
  }

  @override
  Future<void> delete(String key) async {
    _data = null;
  }
}

class _NoOpRustBridge extends RustBridgeLoader {
  @override
  Future<String?> fetchCandid({required String canisterId, String? host}) async {
    return null;
  }
}

void main() {
  const seedJson =
      '[{"canister_id":"rdmx6-jaaaa-aaaaa-aaaga-cai","method":"get_balance","label":"NNS Ledger"}]';

  Future<void> pumpBookmarksList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarksList(
            bridge: _NoOpRustBridge(),
            onTapEntry: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('UX-H5 Path 2: bookmark trash Undo', () {
    setUp(() {
      BookmarksService.overrideStoreForTesting(_MemoryStore(seedJson));
    });

    tearDown(() {
      // Restore the platform-default store so subsequent tests are clean.
      BookmarksService.overrideStoreForTesting(null);
    });

    testWidgets('trash shows Undo SnackBar and removes the entry immediately',
        (tester) async {
      await pumpBookmarksList(tester);

      // Sanity: the seeded bookmark is rendered.
      expect(find.text('NNS Ledger'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pumpAndSettle();

      // Removed from the list right away.
      expect(find.text('NNS Ledger'), findsNothing);

      // SnackBar offers Undo.
      expect(find.text('Bookmark removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('Undo restores the entry including its label', (tester) async {
      await pumpBookmarksList(tester);

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Entry re-appears with its original label intact.
      expect(find.text('NNS Ledger'), findsOneWidget);

      final stored = await BookmarksService.list();
      expect(stored.single.label, 'NNS Ledger');
      expect(stored.single.canisterId, 'rdmx6-jaaaa-aaaaa-aaaga-cai');
      expect(stored.single.method, 'get_balance');
    });

    testWidgets('without Undo the removal persists to the store',
        (tester) async {
      await pumpBookmarksList(tester);

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pumpAndSettle();

      // Do NOT tap Undo. Advance the clock past the SnackBar's 4s duration and
      // settle the exit animation; then verify the store is still empty (the
      // entry was not silently restored).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final stored = await BookmarksService.list();
      expect(stored, isEmpty);
    });
  });
}
