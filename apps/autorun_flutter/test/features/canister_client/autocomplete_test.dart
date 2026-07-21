// UX-H11 — autocomplete now reads from the canonical `WellKnownCanister`
// catalog (lib/config/well_known_canisters.dart) instead of the deleted,
// divergent `CanisterRegistryEntry` service list. These tests verify the
// search/autocomplete contract still holds against the unified catalog.
//
// Coverage:
//  * `WellKnownCanister.all` exposes the well-known canisters.
//  * `WellKnownCanister.search` matches by partial canister-id prefix or
//    label substring, case-insensitively, capped by `limit`.
//  * The four entries the issue (UX-H11) specifically called out as missing
//    from the Call Builder (ICLighthouse, Cyql, Kinic, Canistergeek) appear
//    in the catalog — proving the divergent surfaces now agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/well_known_canisters.dart';

void main() {
  group('WellKnownCanister.all', () {
    test('should provide all well-known canisters', () {
      final all = WellKnownCanister.all;

      expect(all.length, greaterThanOrEqualTo(5));
      expect(all.any((c) => c.label == 'NNS Ledger'), isTrue);
      expect(all.any((c) => c.label == 'NNS Governance'), isTrue);
      expect(all.any((c) => c.label == 'Internet Identity'), isTrue);
    });

    test(
        'UX-H11: contains the four entries the Call Builder previously '
        'omitted (ICLighthouse, Cyql, Kinic, Canistergeek)', () {
      const requiredLabels = <String>[
        'ICLighthouse',
        'Cyql Projects',
        'Kinic Search',
        'Canistergeek',
      ];
      for (final label in requiredLabels) {
        expect(
          WellKnownCanister.all.any((c) => c.label == label),
          isTrue,
          reason: '$label must be in the canonical catalog so every '
              'surface (Call Builder dropdown, Canisters tab grid, '
              'autocomplete) shows it.',
        );
      }
    });
  });

  group('WellKnownCanister.search', () {
    test('search by partial ID prefix returns matching canisters', () {
      final results = WellKnownCanister.search('ryjl');

      expect(results, isNotEmpty);
      expect(results.first.canisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(results.first.label, 'NNS Ledger');
    });

    test('search by full canister ID returns exact match', () {
      final results =
          WellKnownCanister.search('rrkah-fqaaa-aaaaa-aaaaq-cai');

      expect(results, hasLength(1));
      expect(results.first.label, 'NNS Governance');
    });

    test('search by label returns matching canisters', () {
      final results = WellKnownCanister.search('Governance');

      expect(results, isNotEmpty);
      expect(results.any((c) => c.label == 'NNS Governance'), isTrue);
    });

    test('search by label is case-insensitive', () {
      final lowerResults = WellKnownCanister.search('governance');
      final upperResults = WellKnownCanister.search('GOVERNANCE');
      final mixedResults = WellKnownCanister.search('GoVeRnAnCe');

      expect(lowerResults, isNotEmpty);
      expect(upperResults, isNotEmpty);
      expect(mixedResults, isNotEmpty);
      expect(lowerResults.first.canisterId, upperResults.first.canisterId);
      expect(lowerResults.first.canisterId, mixedResults.first.canisterId);
    });

    test('search by partial label returns matching canisters', () {
      final results = WellKnownCanister.search('Ledger');

      expect(results, isNotEmpty);
      expect(results.any((c) => c.label.contains('Ledger')), isTrue);
    });

    test('empty query returns all canisters limited by limit parameter', () {
      final results = WellKnownCanister.search('', limit: 3);

      expect(results.length, equals(3));
    });

    test('empty query with no limit returns all canisters', () {
      final all = WellKnownCanister.all;
      final results = WellKnownCanister.search('', limit: 100);

      expect(results.length, equals(all.length));
    });

    test('no match returns empty list', () {
      final results = WellKnownCanister.search('zzzzz-nonexistent');

      expect(results, isEmpty);
    });

    test('results are limited to specified limit', () {
      final results = WellKnownCanister.search('', limit: 2);

      expect(results.length, lessThanOrEqualTo(2));
    });

    test('search by ID prefix is case-insensitive', () {
      final upperResults = WellKnownCanister.search('RYJL');
      final lowerResults = WellKnownCanister.search('ryjl');

      expect(upperResults.length, equals(lowerResults.length));
      expect(
          upperResults.first.canisterId, equals(lowerResults.first.canisterId));
    });

    test('results include canisterId, label, description, and category', () {
      final results = WellKnownCanister.search('NNS Ledger');

      expect(results, hasLength(1));
      final entry = results.first;
      expect(entry.canisterId, isNotEmpty);
      expect(entry.label, isNotEmpty);
      expect(entry.description, isNotEmpty);
      expect(entry.category, isNotEmpty);
    });
  });
}
