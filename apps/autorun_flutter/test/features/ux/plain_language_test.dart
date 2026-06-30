import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/utils/tech_terms.dart';

void main() {
  group('Plain Language UX', () {
    group('TechTerm plain language aliases', () {
      test('query term has plain language "Read" label', () {
        expect(TechTerm.query.plainLabel, equals('Read'));
      });

      test('update term has plain language "Write" label', () {
        expect(TechTerm.update.plainLabel, equals('Write'));
      });

      test('canister term has plain language "Service" label', () {
        expect(TechTerm.canister.plainLabel, equals('Service'));
      });

      test('all terms have non-empty plain labels', () {
        for (final term in TechTerm.values) {
          expect(term.plainLabel, isNotEmpty,
              reason: '${term.term} should have a plain label');
        }
      });

      test('plain labels are more user-friendly than technical terms', () {
        expect(TechTerm.query.plainLabel.length,
            lessThanOrEqualTo(TechTerm.query.term.length));
        expect(TechTerm.update.plainLabel.length,
            lessThanOrEqualTo(TechTerm.update.term.length));
      });
    });

    group('TechTerm readable descriptions', () {
      test('query plain explanation describes it as read-only', () {
        expect(
          TechTerm.query.plainExplanation.toLowerCase(),
          anyOf(contains('read'), contains('fast'), contains('free')),
        );
      });

      test('update plain explanation describes it as state-modifying', () {
        expect(
          TechTerm.update.plainExplanation.toLowerCase(),
          anyOf(contains('write'), contains('modify'), contains('change')),
        );
      });

      test('canister plain explanation is simpler than full', () {
        expect(TechTerm.canister.plainExplanation.length,
            lessThan(TechTerm.canister.fullExplanation.length));
      });
    });

    group('findByPlainLabel', () {
      test('finds query by plain label "Read"', () {
        expect(TechTerm.findByPlainLabel('Read'), equals(TechTerm.query));
        expect(TechTerm.findByPlainLabel('read'), equals(TechTerm.query));
      });

      test('finds update by plain label "Write"', () {
        expect(TechTerm.findByPlainLabel('Write'), equals(TechTerm.update));
        expect(TechTerm.findByPlainLabel('write'), equals(TechTerm.update));
      });

      test('finds canister by plain label "Service"', () {
        expect(TechTerm.findByPlainLabel('Service'), equals(TechTerm.canister));
        expect(TechTerm.findByPlainLabel('service'), equals(TechTerm.canister));
      });

      test('returns null for unknown plain labels', () {
        expect(TechTerm.findByPlainLabel('Unknown'), isNull);
      });
    });
  });
}
