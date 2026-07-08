import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/canister_registry_service.dart';

void main() {
  group('CanisterRegistryEntry', () {
    test('should provide all well-known canisters', () {
      final all = CanisterRegistryEntry.all;

      expect(all.length, greaterThanOrEqualTo(5));
      expect(all.any((c) => c.name == 'NNS Ledger'), isTrue);
      expect(all.any((c) => c.name == 'NNS Governance'), isTrue);
      expect(all.any((c) => c.name == 'Internet Identity'), isTrue);
    });
  });

  group('CanisterRegistryEntry.search', () {
    test('search by partial ID prefix returns matching canisters', () {
      final results = CanisterRegistryEntry.search('ryjl');

      expect(results, isNotEmpty);
      expect(results.first.canisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(results.first.name, 'NNS Ledger');
    });

    test('search by full canister ID returns exact match', () {
      final results =
          CanisterRegistryEntry.search('rrkah-fqaaa-aaaaa-aaaaq-cai');

      expect(results, hasLength(1));
      expect(results.first.name, 'NNS Governance');
    });

    test('search by name returns matching canisters', () {
      final results = CanisterRegistryEntry.search('Governance');

      expect(results, isNotEmpty);
      expect(results.any((c) => c.name == 'NNS Governance'), isTrue);
    });

    test('search by name is case-insensitive', () {
      final lowerResults = CanisterRegistryEntry.search('governance');
      final upperResults = CanisterRegistryEntry.search('GOVERNANCE');
      final mixedResults = CanisterRegistryEntry.search('GoVeRnAnCe');

      expect(lowerResults, isNotEmpty);
      expect(upperResults, isNotEmpty);
      expect(mixedResults, isNotEmpty);
      expect(lowerResults.first.canisterId, upperResults.first.canisterId);
      expect(lowerResults.first.canisterId, mixedResults.first.canisterId);
    });

    test('search by partial name returns matching canisters', () {
      final results = CanisterRegistryEntry.search('Ledger');

      expect(results, isNotEmpty);
      expect(results.any((c) => c.name.contains('Ledger')), isTrue);
    });

    test('empty query returns all canisters limited by limit parameter', () {
      final results = CanisterRegistryEntry.search('', limit: 3);

      expect(results.length, equals(3));
    });

    test('empty query with no limit returns all canisters', () {
      final all = CanisterRegistryEntry.all;
      final results = CanisterRegistryEntry.search('', limit: 100);

      expect(results.length, equals(all.length));
    });

    test('no match returns empty list', () {
      final results = CanisterRegistryEntry.search('zzzzz-nonexistent');

      expect(results, isEmpty);
    });

    test('results are limited to specified limit', () {
      final results = CanisterRegistryEntry.search('', limit: 2);

      expect(results.length, lessThanOrEqualTo(2));
    });

    test('search by ID prefix is case-insensitive', () {
      final upperResults = CanisterRegistryEntry.search('RYJL');
      final lowerResults = CanisterRegistryEntry.search('ryjl');

      expect(upperResults.length, equals(lowerResults.length));
      expect(
          upperResults.first.canisterId, equals(lowerResults.first.canisterId));
    });

    test('results include id, name, description, and category', () {
      final results = CanisterRegistryEntry.search('NNS Ledger');

      expect(results, hasLength(1));
      final entry = results.first;
      expect(entry.canisterId, isNotEmpty);
      expect(entry.name, isNotEmpty);
      expect(entry.description, isNotEmpty);
      expect(entry.category, isNotEmpty);
    });
  });
}
