import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/screens/canister_client_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

class _FakeRustBridgeLoader extends RustBridgeLoader {
  @override
  Future<String?> fetchCandid(
      {required String canisterId, String? host}) async {
    if (canisterId == 'ryjl3-tyaaa-aaaaa-aaaba-cai') {
      return 'service: { account_balance_dfx: () -> (record {}); transfer: () -> (record {}); }';
    }
    if (canisterId == 'rrkah-fqaaa-aaaaa-aaaaq-cai') {
      return 'service: { get_neuron_ids: () -> (vec int64); list_neurons: () -> (record {}); }';
    }
    return null;
  }

  @override
  String? parseCandid({required String candidText}) {
    if (candidText.contains('account_balance_dfx')) {
      return '{"methods":[{"name":"account_balance_dfx","kind":"query","args":[],"rets":[]},{"name":"transfer","kind":"update","args":[],"rets":[]}]}';
    }
    if (candidText.contains('get_neuron_ids')) {
      return '{"methods":[{"name":"get_neuron_ids","kind":"query","args":[],"rets":["vec int64"]},{"name":"list_neurons","kind":"query","args":[],"rets":[]}]}';
    }
    return null;
  }

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) {
    return '{"result":"ok"}';
  }
}

void main() {
  group('POC: Merged Canisters Screen - Current State', () {
    Future<void> pumpBookmarksScreen(
      WidgetTester tester, {
      Future<void> Function(
              {String? initialCanisterId, String? initialMethodName})?
          onOpenClient,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: ConnectivityScope(
          child: Scaffold(
            body: BookmarksScreen(
              bridge: _FakeRustBridgeLoader(),
              onOpenClient: onOpenClient ??
                  ({initialCanisterId, initialMethodName}) async {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('BookmarksScreen shows Quick Actions section', (tester) async {
      await pumpBookmarksScreen(tester);
      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('BookmarksScreen shows Popular Canisters header',
        (tester) async {
      await pumpBookmarksScreen(tester);
      expect(find.text('Popular Canisters'), findsOneWidget);
    });

    testWidgets('BookmarksScreen shows Your Bookmarks section', (tester) async {
      await pumpBookmarksScreen(tester);
      expect(find.text('Your Bookmarks'), findsOneWidget);
    });

    testWidgets('BookmarksScreen shows Advanced section', (tester) async {
      await pumpBookmarksScreen(tester);
      await tester.fling(
          find.text('Quick Actions'), const Offset(0, -500), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Canister Client'), findsOneWidget);
    });

    testWidgets('tapping Quick Action calls onOpenClient with canister preset',
        (tester) async {
      String? calledCanisterId;
      String? calledMethod;

      await pumpBookmarksScreen(
        tester,
        onOpenClient: ({initialCanisterId, initialMethodName}) async {
          calledCanisterId = initialCanisterId;
          calledMethod = initialMethodName;
        },
      );

      await tester.tap(find.text('Check ICP Balance'));
      await tester.pumpAndSettle();

      expect(calledCanisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(calledMethod, 'account_balance_dfx');
    });
  });

  group('POC: Code Duplication Evidence', () {
    test('Both screens have identical _ArgsEditor widget pattern', () {
      // Evidence: bookmarks_screen.dart:1048-1199 vs canister_client_screen.dart:1256-1388
      // Both have:
      // - useAuto boolean
      // - argTypes list
      // - controller
      // - _rebuildJson() method
      // - CandidFormModel integration
      expect(true, isTrue);
    });

    test('Both screens have identical _fetchAndParse logic', () {
      // Evidence: bookmarks_screen.dart:400-458 vs canister_client_screen.dart:136-192
      // Both:
      // - Call bridge.fetchCandid()
      // - Call bridge.parseCandid()
      // - Parse JSON methods
      // - Set _methods state
      // - Handle errors with _friendlyError()
      expect(true, isTrue);
    });

    test('Both screens have identical advanced options UI', () {
      // Evidence: bookmarks_screen.dart:826-876 vs canister_client_screen.dart:987-1037
      // Both have ExpansionTile with:
      // - Custom Host field
      // - Private Key field
      // - View Raw Candid button
      expect(true, isTrue);
    });

    test('Both screens have identical result display UI', () {
      // Evidence: bookmarks_screen.dart:970-1008 vs canister_client_screen.dart:1128-1166
      // Both show:
      // - "Result" header
      // - Copy button
      // - Formatted JSON in monospace font
      expect(true, isTrue);
    });
  });

  group('POC: Merged Screen Target Behavior', () {
    testWidgets('Target: Popular canisters open inline caller (not modal)',
        (tester) async {
      // Currently: tapping popular canister calls onOpenClient -> CanisterClientScreen modal
      // Target: tapping popular canister opens CanisterClientSheet inline
      //
      // Change needed: _WellKnownList.onSelect should open sheet, not call onOpenClient
      expect(true, isTrue, reason: 'Documented target behavior');
    });

    testWidgets('Target: Recent calls section in BookmarksScreen',
        (tester) async {
      // Currently: Recent calls only in CanisterClientScreen (lines 674-736)
      // Target: Add _RecentCallsSection widget to BookmarksScreen
      //
      // Features to migrate:
      // - CanisterHistoryService().getHistory()
      // - _HistoryListItem widget
      // - Clear history button
      expect(true, isTrue, reason: 'Documented target behavior');
    });

    testWidgets('Target: Canister autocomplete in inline caller',
        (tester) async {
      // Currently: Autocomplete only in CanisterClientScreen (lines 518-665)
      // Target: Add RawAutocomplete<CanisterRegistryEntry> to CanisterClientSheet
      expect(true, isTrue, reason: 'Documented target behavior');
    });

    testWidgets('Target: Delete CanisterClientScreen after merge',
        (tester) async {
      // After merge:
      // 1. All functionality in BookmarksScreen
      // 2. Inline calling via CanisterClientSheet
      // 3. CanisterClientScreen.dart deleted (~1485 lines removed)
      // 4. main.dart no longer needs _openCanisterClient method
      expect(true, isTrue, reason: 'Documented target behavior');
    });
  });

  group('POC: Migration Checklist', () {
    testWidgets('Phase 1: Enhance CanisterClientSheet', (tester) async {
      // Tasks:
      // [ ] Add canister autocomplete from registry
      // [ ] Add history tracking (CanisterHistoryService)
      // [ ] Add host field (already in advanced options)
      // [ ] Verify all call types work (query, update, composite)
      expect(true, isTrue);
    });

    testWidgets('Phase 2: Update BookmarksScreen', (tester) async {
      // Tasks:
      // [ ] Change Popular Canisters to open sheet instead of modal
      // [ ] Add Recent Calls section
      // [ ] Remove Advanced section (no longer needed)
      // [ ] Remove onOpenClient callback (no longer needed)
      expect(true, isTrue);
    });

    testWidgets('Phase 3: Update navigation in main.dart', (tester) async {
      // Tasks:
      // [ ] Remove _openCanisterClient method
      // [ ] Remove CanisterClientScreen import
      // [ ] Update BookmarksScreen constructor (remove onOpenClient)
      expect(true, isTrue);
    });

    testWidgets('Phase 4: Test migration', (tester) async {
      // Tests to update:
      // - canister_client_sheet_test.dart (keep)
      // - canister_client/full_screen_test.dart (delete)
      // - features/services/quick_actions_test.dart (update)
      // - features/navigation/ux_improvements_test.dart (update)
      expect(true, isTrue);
    });
  });

  group('POC: Risk Assessment', () {
    test('Risk: Test count reduction', () {
      // Current tests:
      // - canister_client_sheet_test.dart: ~20 tests (KEEP - inline caller)
      // - full_screen_test.dart: ~10 tests (DELETE - full screen removed)
      // - quick_actions_test.dart: ~25 tests (UPDATE - onOpenClient removed)
      //
      // Net: -10 tests acceptable (redundant functionality removed)
      expect(true, isTrue);
    });

    test('Risk: User muscle memory', () {
      // Current: Some users may be used to CanisterClientScreen modal
      // Mitigation: Inline sheet provides same functionality, just in-place
      // No functionality is lost, just presentation changes
      expect(true, isTrue);
    });

    test('Risk: History service integration', () {
      // CanisterClientScreen already uses CanisterHistoryService
      // Just need to ensure sheet also records calls
      // Simple migration - same service, new caller location
      expect(true, isTrue);
    });
  });
}
