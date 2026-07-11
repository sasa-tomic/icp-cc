// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/well_known_canisters.dart';

// Walking the semantics tree uses `pipelineOwner` + `SemanticsNode.hasFlag`,
// the stable test API for semantics introspection. The newer `flagsCollection`
// replacement isn't available in this SDK, so suppress the deprecation here.
// ignore_for_file: deprecated_member_use

/// W6-10 (a): each Popular Canister card is a tappable `InkWell` that opens
/// the call sheet, but the card appeared in the a11y tree only as a `group`
/// with a single `Bookmark` button — the primary tap target wasn't announced
/// as actionable. The fix exposes the card as a `Semantics(button: true)`
/// node labelled with the canister name so screen-reader users hear an
/// actionable button, while the Bookmark affordance stays separately
/// focusable.
void main() {
  /// Collects every semantics node in the tree (depth-first).
  List<SemanticsNode> collectNodes(WidgetTester tester) {
    final root =
        tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
    final nodes = <SemanticsNode>[];
    bool visit(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren(visit);
      return true;
    }

    visit(root);
    return nodes;
  }

  Future<void> pumpList(
    WidgetTester tester, {
    required void Function(String canisterId, String? method) onSelect,
    Future<void> Function(WellKnownCanister entry)? onBookmark,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WellKnownList(onSelect: onSelect, onBookmark: onBookmark),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'W6-10 (a): a Popular Canister card is exposed as a button whose label '
      'includes the canister name', (tester) async {
    String? tappedCanisterId;
    await pumpList(
      tester,
      onSelect: (canisterId, method) => tappedCanisterId = canisterId,
    );

    // NOTE: dispose the semantics handle BEFORE the assertions — testWidgets
    // verifies handles were disposed right after the body returns (before
    // addTearDown), so collect first, dispose, then assert.
    final handle = tester.ensureSemantics();
    final nodes = collectNodes(tester);
    handle.dispose();

    // Find button nodes whose label mentions the canister name.
    const canisterName = 'NNS Registry';
    final openButtons = nodes
        .where((n) =>
            n.hasFlag(SemanticsFlag.isButton) &&
            n.label.toLowerCase().contains(canisterName.toLowerCase()))
        .toList();

    expect(openButtons, isNotEmpty,
        reason: 'The NNS Registry card must be exposed as an actionable '
            'button so screen readers announce the tap target. Got labels: '
            '${nodes.where((n) => n.label.isNotEmpty).map((n) => n.label).toList()}');

    // Tapping the card still fires onSelect (behaviour unchanged).
    await tester.tap(find.text(canisterName));
    await tester.pump();
    expect(tappedCanisterId, 'rwlgt-iiaaa-aaaaa-aaaaa-cai');
  });

  testWidgets(
      'W6-10 (a): the Bookmark affordance remains a separately focusable '
      'button (one per card)', (tester) async {
    await pumpList(
      tester,
      onSelect: (_, __) {},
      // Providing onBookmark renders the per-card bookmark affordance.
      onBookmark: (_) async {},
    );

    final handle = tester.ensureSemantics();
    final nodes = collectNodes(tester);
    handle.dispose();

    final bookmarkButtons = nodes
        .where((n) =>
            n.hasFlag(SemanticsFlag.isButton) &&
            n.label.toLowerCase().contains('bookmark'))
        .toList();

    expect(bookmarkButtons, isNotEmpty,
        reason: 'Bookmark buttons must remain individually focusable');
    // One labelled bookmark button per shipped canister card (8 shipped).
    expect(bookmarkButtons.length, 8,
        reason: 'expected one bookmark button per card');
  });
}
