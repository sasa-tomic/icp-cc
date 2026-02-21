import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/tech_terms.dart';

void main() {
  group('TechTerm', () {
    test('all terms have non-empty properties', () {
      for (final term in TechTerm.values) {
        expect(term.term, isNotEmpty);
        expect(term.shortExplanation, isNotEmpty);
        expect(term.fullExplanation, isNotEmpty);
      }
    });

    test('short explanation is shorter than full explanation', () {
      for (final term in TechTerm.values) {
        expect(
          term.shortExplanation.length,
          lessThan(term.fullExplanation.length),
          reason: '${term.term}: short should be shorter than full',
        );
      }
    });

    test('canister term has correct properties', () {
      expect(TechTerm.canister.term, 'Canister');
      expect(
        TechTerm.canister.fullExplanation,
        contains('smart contract'),
      );
    });

    test('principal term has correct properties', () {
      expect(TechTerm.principal.term, 'Principal');
      expect(
        TechTerm.principal.fullExplanation,
        contains('unique account identifier'),
      );
    });

    test('keypair term has correct properties', () {
      expect(TechTerm.keypair.term, 'Keypair');
      expect(
        TechTerm.keypair.fullExplanation,
        contains('public/private key'),
      );
    });

    test('query term explains it is read-only', () {
      expect(TechTerm.query.term, 'Query');
      expect(
        TechTerm.query.fullExplanation,
        contains('read-only'),
      );
    });

    test('update term explains it modifies state', () {
      expect(TechTerm.update.term, 'Update');
      expect(
        TechTerm.update.fullExplanation,
        anyOf(contains('modifies'), contains('state')),
      );
    });

    test('cycles term references gas/computational resources', () {
      expect(TechTerm.cycles.term, 'Cycles');
      expect(
        TechTerm.cycles.fullExplanation,
        anyOf(contains('gas'), contains('computational')),
      );
    });

    test('candid term explains type system', () {
      expect(TechTerm.candid.term, 'Candid');
      expect(
        TechTerm.candid.fullExplanation,
        contains('type system'),
      );
    });

    test('replica term explains it is a node', () {
      expect(TechTerm.replica.term, 'Replica');
      expect(
        TechTerm.replica.fullExplanation,
        anyOf(contains('node'), contains('network')),
      );
    });

    test('findByTerm finds terms case-insensitively', () {
      expect(TechTerm.findByTerm('Canister'), TechTerm.canister);
      expect(TechTerm.findByTerm('canister'), TechTerm.canister);
      expect(TechTerm.findByTerm('CANISTER'), TechTerm.canister);
      expect(TechTerm.findByTerm('Principal'), TechTerm.principal);
      expect(TechTerm.findByTerm('Keypair'), TechTerm.keypair);
    });

    test('findByTerm returns null for unknown terms', () {
      expect(TechTerm.findByTerm('UnknownTerm'), isNull);
      expect(TechTerm.findByTerm(''), isNull);
      expect(TechTerm.findByTerm('random'), isNull);
    });

    test('all expected terms are defined', () {
      final expectedTerms = [
        'Canister',
        'Principal',
        'Candid',
        'Keypair',
        'Query',
        'Update',
        'Cycles',
        'Replica',
        'Signing Key',
        'IC Principal',
        'Passkey',
      ];

      for (final expected in expectedTerms) {
        expect(
          TechTerm.values.any((t) => t.term == expected),
          isTrue,
          reason: 'Missing term: $expected',
        );
      }
    });

    test('passkey term has correct properties', () {
      expect(TechTerm.passkey.term, 'Passkey');
      expect(TechTerm.passkey.plainLabel, isNotEmpty);
      expect(TechTerm.passkey.shortExplanation, isNotEmpty);
      expect(TechTerm.passkey.fullExplanation, contains('biometric'));
    });
  });
}
