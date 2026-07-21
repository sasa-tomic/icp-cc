// UX-H11 — Call Builder dropdown regression test.
//
// Before UX-H11, `CanisterCallBuilderDialog` had its own divergent
// hard-coded `_wellKnownCanisters` list with 5 entries that OMITTED the
// four entries the Canisters tab grid showed (ICLighthouse, Cyql, Kinic,
// Canistergeek). After UX-H11 the dropdown reads from the canonical
// `WellKnownCanister.all` via `buildWellKnownDropdownItems()`, so the
// dropdown and the Canisters tab grid show the SAME entries.
//
// This test verifies the items builder emits every canonical entry (by
// value + display text). If a future change re-forks the catalog (a new
// hard-coded list sneaks in), this fails loudly.
//
// Why a unit test on `buildWellKnownDropdownItems()` instead of pumping
// the dialog: the dialog ships with a fixed `SizedBox(width: 800,
// height: 600)` plus long canister-id strings that overflow the default
// test surface. The snippet generator was extracted to a
// `@visibleForTesting static` for the same reason; the items builder
// follows the same pattern (`canister_call_builder_snippet_test.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/config/well_known_canisters.dart';
import 'package:icp_autorun/widgets/canister_call_builder.dart';

void main() {
  group(
      'CanisterCallBuilderDialog.buildWellKnownDropdownItems '
      '(UX-H11 single-source)', () {
    final items = CanisterCallBuilderDialog.buildWellKnownDropdownItems();

    test(
        'the first item is the "Custom canister ID" placeholder (value: "")',
        () {
      expect(items.first.value, '');
      expect((items.first.child as Text).data, 'Custom canister ID');
    });

    test('every canonical WellKnownCanister is represented exactly once', () {
      // Skip the placeholder (value == '').
      final wellKnownItems = items.where((i) => i.value != '').toList();
      expect(wellKnownItems.length, WellKnownCanister.all.length,
          reason: 'Item count must match the canonical catalog exactly.');

      for (final entry in WellKnownCanister.all) {
        final matches = wellKnownItems
            .where((i) => i.value == entry.canisterId)
            .toList();
        expect(matches, hasLength(1),
            reason:
                'Expected exactly one dropdown item for ${entry.label}.');
        // The displayed text must be '${label} (${canisterId})' so the
        // user sees both pieces (matches what the widget shipped before
        // UX-H11, just for the FULL catalog now).
        expect((matches.single.child as Text).data,
            '${entry.label} (${entry.canisterId})');
      }
    });

    test(
        'UX-H11 regression: the four entries the divergent list previously '
        'omitted are now present (ICLighthouse, Cyql, Kinic, Canistergeek)',
        () {
      const requiredLabels = <String>{
        'ICLighthouse',
        'Cyql Projects',
        'Kinic Search',
        'Canistergeek',
      };
      final presentLabels = <String>{};
      for (final item in items) {
        final text = (item.child as Text).data ?? '';
        for (final label in requiredLabels) {
          if (text.startsWith('$label (')) presentLabels.add(label);
        }
      }
      expect(presentLabels.containsAll(requiredLabels), isTrue,
          reason: 'UX-H11 fix: the Call Builder dropdown must include the '
              'four entries the previous divergent list omitted. Missing: '
              '${requiredLabels.difference(presentLabels)}');
    });
  });
}
