// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/dapps_screen.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

// Walking the semantics tree uses `pipelineOwner` + `SemanticsNode.hasFlag`,
// the stable test API for semantics introspection. The newer `flagsCollection`
// replacement isn't available in this SDK, so suppress the deprecation here.
// ignore_for_file: deprecated_member_use

/// W6-10 (b): the ENTIRE dapp card (description + badges + sub-actions) was one
/// giant button with a huge concatenated label, so sub-actions weren't
/// individually focusable and screen readers read one enormous string. The fix
/// exposes the primary "Open" action as a clean button (concise label) while
/// keeping the description and path badges as separately focusable nodes.
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

  Future<void> pumpDapps(WidgetTester tester) async {
    final profileController = ProfileController(
      marketplaceService: MarketplaceOpenApiService(),
    );
    await tester.pumpWidget(
      ProfileScope(
        controller: profileController,
        child: const MaterialApp(home: DappsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'W6-10 (b): the dapp card exposes a primary "Open" button with a CONCISE '
      'label (title only), NOT the giant description+badges concatenation',
      (tester) async {
    await pumpDapps(tester);

    final handle = tester.ensureSemantics();
    final nodes = collectNodes(tester);
    handle.dispose();

    // Find the dapp whose title is unique.
    final dapp =
        exampleDapps.firstWhere((d) => d.title == 'ICP Ledger');
    final title = dapp.title;

    // There must be a button node whose label carries the title AND the word
    // "Open" (the primary action).
    final openButtons = nodes
        .where((n) =>
            n.hasFlag(SemanticsFlag.isButton) &&
            n.label.toLowerCase().contains(title.toLowerCase()) &&
            n.label.toLowerCase().contains('open'))
        .toList();
    expect(openButtons, isNotEmpty,
        reason: 'the dapp card must expose a primary "Open" button labelled '
            'with its title. Button labels were: '
            '${nodes.where((n) => n.hasFlag(SemanticsFlag.isButton)).map((n) => n.label).toList()}');

    // That button's label must NOT contain the full description (the OLD bug
    // merged the entire description + every badge into one huge label).
    final openLabel = openButtons.first.label;
    expect(openLabel.toLowerCase().contains(dapp.description.toLowerCase()),
        isFalse,
        reason: 'the open button label must stay concise (title only); it must '
            'not include the full description. Actual label: "$openLabel"');
  });

  testWidgets(
      'W6-10 (b): the path badges (sub-actions) are individually focusable — '
      'each appears as its own semantics node, not swallowed into the button',
      (tester) async {
    await pumpDapps(tester);

    final handle = tester.ensureSemantics();
    final nodes = collectNodes(tester);
    handle.dispose();

    // "Backend direct" is a sub-action badge; it must exist as its own node
    // (label exactly "Backend direct"), separate from the open button.
    final backendNodes =
        nodes.where((n) => n.label.trim() == 'Backend direct').toList();
    expect(backendNodes, isNotEmpty,
        reason: '"Backend direct" must be an individually focusable node');
    // That node must NOT be the primary open button (which carries "Open …").
    for (final node in backendNodes) {
      expect(node.label.toLowerCase().contains('open'), isFalse,
          reason: 'the badge must be its own node, not merged into the open '
              'button label: "${node.label}"');
    }
  });
}
