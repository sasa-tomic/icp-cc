import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

/// Fake bridge that exposes a canister with a large (>8) method set so the
/// UX-3 searchable, grouped method picker switches on. Mixes Candid call kinds
/// (query / update / composite) to exercise grouping.
class _LargeFakeBridge extends RustBridgeLoader {
  static const String _canister = 'large-canister';

  /// Method names, in the order [_parse] preserves. `get_*` are queries so we
  /// can assert precise substring filtering.
  static const List<String> queryMethods = <String>[
    'get_balance',
    'get_stats',
    'get_info',
    'get_name',
    'get_owner',
    'list_tokens',
    'total_supply',
    'decimals',
  ];
  static const List<String> updateMethods = <String>[
    'transfer',
    'mint',
    'burn',
  ];

  @override
  Future<String?> fetchCandid({required String canisterId, String? host}) async {
    if (canisterId == _canister) return 'service: { /* large */ }';
    return null;
  }

  @override
  String? parseCandid({required String candidText}) {
    if (!candidText.contains('large')) return null;
    final methodEntries = <String>[
      for (final n in queryMethods)
        '{"name":"$n","kind":"query","args":[],"rets":[]}',
      for (final n in updateMethods)
        '{"name":"$n","kind":"update","args":[],"rets":[]}',
      '{"name":"composite_call","kind":"composite_query","args":[],"rets":[]}',
    ];
    final joined = methodEntries.join(',');
    return '{"methods":[$joined]}';
  }

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) {
    return '{"ok":true}';
  }

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
    return '{"ok":true}';
  }
}

void main() {
  Future<void> pumpConnected(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanisterClientSheet(
            bridge: _LargeFakeBridge(),
            initialCanisterId: _LargeFakeBridge._canister,
            initialMethodName: '',
          ),
        ),
      ),
    );
    // initialCanisterId set + initialMethodName empty -> disconnected; we drive
    // the fetch like the real user does so the connected state is genuine.
    await tester.enterText(
      find.byKey(const Key('canisterField')),
      _LargeFakeBridge._canister,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  group('UX-3 searchable method picker', () {
    testWidgets('large canister shows search field, count, and kind groups',
        (tester) async {
      await pumpConnected(tester);

      expect(find.byKey(const Key('methodSearchField')), findsOneWidget);
      // 8 query + 3 update + 1 composite = 12 methods.
      expect(find.text('12 functions'), findsOneWidget);
      // Grouping is on (>8): all three call-kind headers render.
      expect(find.text('Read (fast) · 8'), findsOneWidget);
      expect(find.text('Write (slower) · 3'), findsOneWidget);
      expect(find.text('Composite · 1'), findsOneWidget);
      // A representative chip from each kind is present.
      expect(find.byKey(const Key('methodChip_get_balance')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_transfer')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_composite_call')), findsOneWidget);
    });

    testWidgets('typing filters methods by name and updates the count',
        (tester) async {
      await pumpConnected(tester);

      await tester.enterText(
        find.byKey(const Key('methodSearchField')),
        'get',
      );
      await tester.pumpAndSettle();

      // 5 of the 12 methods contain "get".
      expect(find.text('5 of 12'), findsOneWidget);
      // Matching chips remain…
      expect(find.byKey(const Key('methodChip_get_balance')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_get_owner')), findsOneWidget);
      // …non-matching ones are hidden (query, update, and composite alike).
      expect(find.byKey(const Key('methodChip_list_tokens')), findsNothing);
      expect(find.byKey(const Key('methodChip_transfer')), findsNothing);
      expect(find.byKey(const Key('methodChip_composite_call')), findsNothing);
      // The empty groups are no longer rendered.
      expect(find.text('Write (slower) · 3'), findsNothing);
      expect(find.text('Composite · 1'), findsNothing);
      // The surviving query group header reflects the filtered count.
      expect(find.text('Read (fast) · 5'), findsOneWidget);
    });

    testWidgets('filtering is case-insensitive', (tester) async {
      await pumpConnected(tester);

      await tester.enterText(
        find.byKey(const Key('methodSearchField')),
        'TRANSFER',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 12'), findsOneWidget);
      expect(find.byKey(const Key('methodChip_transfer')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_get_balance')), findsNothing);
    });

    testWidgets('clear button restores the full list', (tester) async {
      await pumpConnected(tester);

      await tester.enterText(
        find.byKey(const Key('methodSearchField')),
        'get',
      );
      await tester.pumpAndSettle();
      expect(find.text('5 of 12'), findsOneWidget);

      await tester.tap(find.byKey(const Key('methodSearchClear')));
      await tester.pumpAndSettle();

      // Full list + unfiltered count restored; non-matching chip is back.
      expect(find.text('12 functions'), findsOneWidget);
      expect(find.byKey(const Key('methodChip_transfer')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_composite_call')), findsOneWidget);
      // Clear button hides again once the query is empty.
      expect(find.byKey(const Key('methodSearchClear')), findsNothing);
    });

    testWidgets('no matches shows an empty state and hides all chips',
        (tester) async {
      await pumpConnected(tester);

      await tester.enterText(
        find.byKey(const Key('methodSearchField')),
        'zzz-nothing',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('methodSearchEmpty')), findsOneWidget);
      expect(find.text("No methods match 'zzz-nothing'."), findsOneWidget);
      expect(find.byKey(const Key('methodChip_get_balance')), findsNothing);
      expect(find.byKey(const Key('methodChip_transfer')), findsNothing);
      expect(find.text('0 of 12'), findsOneWidget);
    });

    testWidgets('Enter selects the first match and shows its Call button',
        (tester) async {
      await pumpConnected(tester);

      await tester.enterText(
        find.byKey(const Key('methodSearchField')),
        'get',
      );
      await tester.pumpAndSettle();
      // Submitting the search field selects the first matching method
      // (get_balance is the first method overall).
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('callButton')), findsOneWidget);
      expect(find.text('Call get_balance'), findsOneWidget);
    });

    testWidgets('small canister stays flat (no grouping) but still searchable',
        (tester) async {
      // A 2-method canister must NOT render kind headers (YAGNI) yet still
      // expose the search field and filter correctly.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanisterClientSheet(
              bridge: _SmallFakeBridge(),
              initialCanisterId: 'small',
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'small',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('methodSearchField')), findsOneWidget);
      expect(find.text('2 functions'), findsOneWidget);
      // No kind headers for a small set.
      expect(find.textContaining('Read (fast)'), findsNothing);
      expect(find.textContaining('Write (slower)'), findsNothing);
      expect(find.byKey(const Key('methodChip_alpha')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_beta')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('methodSearchField')), 'alp');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.byKey(const Key('methodChip_alpha')), findsOneWidget);
      expect(find.byKey(const Key('methodChip_beta')), findsNothing);
    });
  });
}

/// 2-method canister for the flat-layout assertion.
class _SmallFakeBridge extends RustBridgeLoader {
  @override
  Future<String?> fetchCandid({required String canisterId, String? host}) async {
    if (canisterId == 'small') return 'service: { /* small */ }';
    return null;
  }

  @override
  String? parseCandid({required String candidText}) {
    if (!candidText.contains('small')) return null;
    return '{"methods":['
        '{"name":"alpha","kind":"query","args":[],"rets":[]},'
        '{"name":"beta","kind":"update","args":[],"rets":[]}'
        ']}';
  }

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) =>
      '{"ok":true}';

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) =>
      '{"ok":true}';
}
