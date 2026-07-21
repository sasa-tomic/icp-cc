// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/well_known_canisters.dart';
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
    // One labelled bookmark button per shipped canister card. Count derives
    // from the canonical catalog (UX-H11: single source of truth) — no
    // per-surface magic numbers.
    expect(bookmarkButtons.length, WellKnownCanister.all.length,
        reason: 'expected one bookmark button per card');
  });

  testWidgets(
    'W7-19: the canister name is announced only once (no doubled name '
    'from the card label + title Text)', (tester) async {
    await pumpList(
      tester,
      onSelect: (_, __) {},
      onBookmark: (_) async {},
    );

    final handle = tester.ensureSemantics();
    final nodes = collectNodes(tester);
    handle.dispose();

    // The card's open-action node is the button whose label starts with
    // "Open NNS Registry". Before W7-19 the inner title Text merged its
    // label in too, producing "Open NNS Registry NNS Registry …" (the name
    // spoken twice). After ExcludeSemantics on the title, the name appears
    // exactly once within that label.
    const name = 'NNS Registry';
    final openNode = nodes.firstWhere(
      (n) =>
          n.hasFlag(SemanticsFlag.isButton) &&
          n.label.toLowerCase().startsWith('open $name'.toLowerCase()),
      orElse: () => throw TestFailure(
          'Open-action card node not found. Labels: '
          '${nodes.where((n) => n.label.isNotEmpty).map((n) => n.label).toList()}'),
    );

    final occurrences =
        name.toLowerCase().allMatches(openNode.label.toLowerCase()).length;
    expect(occurrences, 1,
        reason: 'Card name must appear exactly once in the open-action label. '
            'Got: "${openNode.label}"');
  });

  // E2E-D-RESUME-2: the card's outer Column used a Spacer to push the method
  // badge to the bottom. At narrow widths (crossAxisCount=1, aspectRatio=3.0)
  // AND medium widths (crossAxisCount=2, aspectRatio=2.6) the GridView gives
  // each card a tight height that's smaller than the natural Row + Spacer +
  // badge height, so the Column overflows. Pre-Flutter-3.44.6 this was a
  // silent warning; under IntegrationTestWidgetsFlutterBinding on 3.44.6 it's
  // a FATAL test error that blocks the canisters.open_inline_client e2e flow.
  testWidgets(
      'E2E-D-RESUME-2: cards do NOT overflow at any width '
      '(1-, 2-, and 3-column GridView layouts)', (tester) async {
    // Sweep widths that exercise every layout branch in WellKnownList.build
    // (line 88-89): 1-col (aspect 3.0), 2-col (aspect 2.6), 3-col (aspect 3.5).
    for (final width in const <double>[280, 420, 600, 880, 1200, 1440]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      // Reset between iterations so each width gets a clean viewport.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WellKnownList(onSelect: (_, __) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Without the fix: each card emits a `RenderFlex overflowed` FlutterError
      // (or `non-zero flex in unbounded` during transient re-layout).
      // With the fix: no overflow at any width.
      expect(tester.takeException(), isNull,
          reason: 'Well-known canister cards must not overflow at width '
              '$width. If this fires, the inner Column\'s natural height '
              'exceeds the GridView card height — wrap content in '
              'Flexible/Expanded or replace Spacer with a fixed SizedBox.');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
