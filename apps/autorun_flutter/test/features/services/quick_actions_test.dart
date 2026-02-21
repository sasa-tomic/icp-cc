import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

class _FakeRustBridgeLoader extends RustBridgeLoader {
  @override
  Future<String?> fetchCandid(
          {required String canisterId, String? host}) async =>
      null;

  @override
  String? parseCandid({required String candidText}) => null;

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) =>
      null;

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int kind,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) =>
      null;
}

void main() {
  group('Quick Actions', () {
    testWidgets('shows Quick Actions section header', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('shows Check ICP Balance quick action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Check ICP Balance'), findsOneWidget);
    });

    testWidgets('shows View Neurons quick action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('View Neurons'), findsOneWidget);
    });

    testWidgets('shows Search Dapps quick action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Search Dapps'), findsOneWidget);
    });

    testWidgets('shows Advanced section header', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Advanced'), findsOneWidget);
    });

    testWidgets('tapping Check ICP Balance opens canister client with ledger',
        (tester) async {
      String? capturedCanisterId;
      String? capturedMethodName;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId, String? initialMethodName}) async {
              capturedCanisterId = initialCanisterId;
              capturedMethodName = initialMethodName;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check ICP Balance'));
      await tester.pumpAndSettle();

      expect(capturedCanisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(capturedMethodName, 'account_balance_dfx');
    });

    testWidgets('tapping View Neurons opens canister client with governance',
        (tester) async {
      String? capturedCanisterId;
      String? capturedMethodName;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId, String? initialMethodName}) async {
              capturedCanisterId = initialCanisterId;
              capturedMethodName = initialMethodName;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Neurons'));
      await tester.pumpAndSettle();

      expect(capturedCanisterId, 'rrkah-fqaaa-aaaaa-aaaaq-cai');
      expect(capturedMethodName, 'list_neurons');
    });

    testWidgets('Search Dapps card has external link icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Find the Search Dapps card by its key and check for external link icon
      final searchDappsCard = find.byKey(const Key('quickAction_searchDapps'));
      expect(searchDappsCard, findsOneWidget);

      // Check for open_in_new icon within the card
      final iconFinder = find.descendant(
        of: searchDappsCard,
        matching: find.byIcon(Icons.open_in_new),
      );
      expect(iconFinder, findsOneWidget);
    });

    testWidgets('Quick Actions appear before Popular Canisters section',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Quick Actions text should appear before Popular Canisters
      final quickActionsText = find.text('Quick Actions');
      final popularText = find.text('Popular Canisters');

      expect(quickActionsText, findsOneWidget);
      expect(popularText, findsOneWidget);

      // Get y positions
      final quickActionsY = tester.getTopLeft(quickActionsText).dy;
      final popularY = tester.getTopLeft(popularText).dy;

      expect(quickActionsY, lessThan(popularY));
    });

    testWidgets('Quick action cards have correct icons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Check for balance icon on Check ICP Balance
      final balanceCard = find.byKey(const Key('quickAction_checkBalance'));
      expect(balanceCard, findsOneWidget);
      final balanceIcon = find.descendant(
        of: balanceCard,
        matching: find.byIcon(Icons.account_balance_wallet_rounded),
      );
      expect(balanceIcon, findsOneWidget);

      // Check for neuron icon on View Neurons
      final neuronCard = find.byKey(const Key('quickAction_viewNeurons'));
      expect(neuronCard, findsOneWidget);
      final neuronIcon = find.descendant(
        of: neuronCard,
        matching: find.byIcon(Icons.how_to_vote_rounded),
      );
      expect(neuronIcon, findsOneWidget);

      // Check for search icon on Search Dapps
      final searchCard = find.byKey(const Key('quickAction_searchDapps'));
      expect(searchCard, findsOneWidget);
      final searchIcon = find.descendant(
        of: searchCard,
        matching: find.byIcon(Icons.search_rounded),
      );
      expect(searchIcon, findsOneWidget);
    });

    testWidgets('Quick action cards have gradient backgrounds', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final balanceCard = find.byKey(const Key('quickAction_checkBalance'));
      expect(balanceCard, findsOneWidget);

      final containers = find.descendant(
        of: balanceCard,
        matching: find.byType(Container),
      );
      expect(containers, findsWidgets);

      bool foundGradient = false;
      for (var i = 0; i < containers.evaluate().length; i++) {
        final container = tester.widget<Container>(containers.at(i));
        if (container.decoration is BoxDecoration) {
          final decoration = container.decoration as BoxDecoration;
          if (decoration.gradient is LinearGradient) {
            foundGradient = true;
            break;
          }
        }
      }
      expect(foundGradient, isTrue);
    });

    testWidgets('Quick action cards meet minimum height of 120px',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final balanceCard = find.byKey(const Key('quickAction_checkBalance'));
      expect(balanceCard, findsOneWidget);

      final cardSize = tester.getSize(balanceCard);
      expect(cardSize.height, greaterThanOrEqualTo(120));
    });

    testWidgets('See All button is present and tappable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final seeAllButton = find.byKey(const Key('quickActions_seeAll'));
      expect(seeAllButton, findsOneWidget);

      await tester.tap(seeAllButton);
      await tester.pumpAndSettle();
    });

    testWidgets('See All button shows snackbar when tapped', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quickActions_seeAll')));
      await tester.pumpAndSettle();

      expect(find.text('More actions coming soon'), findsOneWidget);
    });

    testWidgets('Quick action cards have divider between title and description',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookmarksScreen(
            bridge: _FakeRustBridgeLoader(),
            onOpenClient: (
                {String? initialCanisterId,
                String? initialMethodName}) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final balanceCard = find.byKey(const Key('quickAction_checkBalance'));
      expect(balanceCard, findsOneWidget);

      final divider = find.descendant(
        of: balanceCard,
        matching: find.byType(Divider),
      );
      expect(divider, findsOneWidget);
    });
  });
}
