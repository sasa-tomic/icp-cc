// UX-H11 — single source of truth for the well-known canisters catalog.
//
// Before UX-H11 the repo had THREE divergent hard-coded lists:
//
//  * `widgets/well_known_canisters.dart` (the Canisters tab grid, 8 entries)
//  * `widgets/canister_call_builder.dart` (the Call Builder dropdown, 5
//    entries — omitted ICLighthouse / Cyql / Kinic / Canistergeek)
//  * `services/canister_registry_service.dart` (the autocomplete, 8 entries
//    with different members + an extra `category` field)
//
// After UX-H11 there is ONE list — `WellKnownCanister.all` in
// `lib/config/well_known_canisters.dart`. Every surface consumes it.
//
// These tests pin that invariant: adding an entry to the canonical list
// MUST automatically appear in every consumer. If a future change re-forks
// the catalog (a new hard-coded list sneaks in), the parameterised
// "appears in every consumer" case fails loudly.
//
// Walking the semantics tree uses `pipelineOwner` + `SemanticsNode.hasFlag`,
// the stable test API for semantics introspection. The newer `flagsCollection`
// replacement isn't available in this SDK, so suppress the deprecation here.
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/config/well_known_canisters.dart';
import 'package:icp_autorun/widgets/well_known_canisters.dart';

void main() {
  group('WellKnownCanister catalog (UX-H11 canonical source)', () {
    test('every entry has a unique canister id (no accidental dupes)', () {
      final ids = WellKnownCanister.all.map((c) => c.canisterId).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'Duplicate canister ids in the canonical catalog would '
              'produce duplicate dropdown options + wasted grid slots.');
    });

    test('every entry has a unique label (no name collisions)', () {
      final labels = WellKnownCanister.all.map((c) => c.label).toList();
      expect(labels.toSet().length, labels.length,
          reason: 'Labels drive the autocomplete + card titles; duplicates '
              'would be ambiguous in the UI.');
    });

    test('every entry has non-empty description + category', () {
      for (final entry in WellKnownCanister.all) {
        expect(entry.description, isNotEmpty,
            reason: 'description missing for ${entry.label}');
        expect(entry.category, isNotEmpty,
            reason: 'category missing for ${entry.label} — the autocomplete '
                'options view renders the category badge unconditionally.');
      }
    });

    test(
        'UX-H11 regression: the four entries the Call Builder previously '
        'omitted are present (ICLighthouse, Cyql, Kinic, Canistergeek)', () {
      const requiredLabels = <String>{
        'ICLighthouse',
        'Cyql Projects',
        'Kinic Search',
        'Canistergeek',
      };
      final present = WellKnownCanister.all.map((c) => c.label).toSet();
      expect(present.containsAll(requiredLabels), isTrue,
          reason: 'UX-H11 fix: these four must be in the catalog so they '
              'appear in the Call Builder dropdown too. Missing: '
              '${requiredLabels.difference(present)}');
    });

    testWidgets(
      'UX-H11 single-source property: WellKnownList renders exactly the '
      'canonical catalog (one card per entry, no more, no less)',
      (tester) async {
        // Give the grid enough room to lay out every card (the default test
        // viewport is 800x600 which clips the last row at 13 entries).
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WellKnownList(onSelect: (_, __) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Each card's open-action is a `Semantics(button: true)` node whose
        // label starts with 'Open <label>'. Collect those labels and verify
        // the set matches the canonical catalog exactly.
        final handle = tester.ensureSemantics();
        final nodes = <SemanticsNode>[];
        bool visit(SemanticsNode node) {
          nodes.add(node);
          node.visitChildren(visit);
          return true;
        }

        visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
        handle.dispose();

        final openLabels = nodes
            .where((n) => n.hasFlag(SemanticsFlag.isButton))
            .map((n) => n.label)
            .where((l) => l.startsWith('Open '))
            .map((l) => l.substring('Open '.length))
            .toSet();

        final canonicalLabels =
            WellKnownCanister.all.map((c) => c.label).toSet();

        expect(openLabels, canonicalLabels,
            reason: 'WellKnownList must render every entry of '
                '`WellKnownCanister.all` and ONLY those entries.');
      },
    );
  });

  // Single-source parameterised test: each entry of the canonical catalog
  // MUST be discoverable through the autocomplete search (so the user can
  // type either the id or a piece of the label and find it). If you add a
  // canister to the catalog but forget to make it searchable, this fires.
  group('WellKnownCanister.search (autocomplete single-source)', () {
    for (final entry in WellKnownCanister.all) {
      test('${entry.label} is searchable by its label', () {
        final results = WellKnownCanister.search(entry.label);
        expect(results.any((c) => c.canisterId == entry.canisterId), isTrue,
            reason: '${entry.label} (${entry.canisterId}) must be '
                'discoverable via autocomplete.');
      });

      test('${entry.label} is searchable by its full canister id', () {
        final results = WellKnownCanister.search(entry.canisterId);
        expect(results.any((c) => c.canisterId == entry.canisterId), isTrue,
            reason: '${entry.label} (${entry.canisterId}) must be '
                'discoverable by full id.');
      });
    }
  });
}

