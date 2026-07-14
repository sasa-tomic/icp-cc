import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_type_classifier.dart';

void main() {
  group('classifyCandidType', () {
    group('scalar kinds', () {
      test('bool', () {
        expect(classifyCandidType('bool'), CandidTypeKind.boolean);
      });

      test('text', () {
        expect(classifyCandidType('text'), CandidTypeKind.text);
      });

      test('principal', () {
        expect(classifyCandidType('principal'), CandidTypeKind.principal);
      });
    });

    group('integer kinds (unbounded vs fixed-width)', () {
      test('nat is unbounded', () {
        expect(classifyCandidType('nat'), CandidTypeKind.nat);
      });

      test('int is unbounded', () {
        expect(classifyCandidType('int'), CandidTypeKind.int);
      });

      test('nat8/16/32/64 are distinct from nat', () {
        expect(classifyCandidType('nat8'), CandidTypeKind.nat8);
        expect(classifyCandidType('nat16'), CandidTypeKind.nat16);
        expect(classifyCandidType('nat32'), CandidTypeKind.nat32);
        expect(classifyCandidType('nat64'), CandidTypeKind.nat64);
      });

      test('int8/16/32/64 are distinct from int', () {
        expect(classifyCandidType('int8'), CandidTypeKind.int8);
        expect(classifyCandidType('int16'), CandidTypeKind.int16);
        expect(classifyCandidType('int32'), CandidTypeKind.int32);
        expect(classifyCandidType('int64'), CandidTypeKind.int64);
      });
    });

    group('float kinds', () {
      test('float32 / float64', () {
        expect(classifyCandidType('float32'), CandidTypeKind.float32);
        expect(classifyCandidType('float64'), CandidTypeKind.float64);
      });
    });

    group('aggregate kinds', () {
      test('vec (with parameterised inner)', () {
        expect(classifyCandidType('vec text'), CandidTypeKind.vec);
        expect(classifyCandidType('vec<nat64>'), CandidTypeKind.vec);
        expect(classifyCandidType('vec record { a : nat }'), CandidTypeKind.vec);
      });

      test('record (with body)', () {
        expect(classifyCandidType('record { a : nat; b : text }'),
            CandidTypeKind.record);
        expect(classifyCandidType('record{}'), CandidTypeKind.record);
        expect(classifyCandidType('record { 0 : nat; 1 : text }'),
            CandidTypeKind.record);
      });

      test('variant (with body)', () {
        expect(classifyCandidType('variant { ok; err : text }'),
            CandidTypeKind.variant);
        expect(classifyCandidType('variant{}'), CandidTypeKind.variant);
      });

      test('opt (with inner)', () {
        expect(classifyCandidType('opt text'), CandidTypeKind.opt);
        expect(classifyCandidType('opt<nat64>'), CandidTypeKind.opt);
        expect(classifyCandidType('opt opt text'), CandidTypeKind.opt);
      });
    });

    group('full-token matching (not prefix)', () {
      test('nat is not nat8 (eliminates historic ==/startsWith inconsistency)',
          () {
        expect(classifyCandidType('nat'), isNot(CandidTypeKind.nat8));
        expect(classifyCandidType('nat'), isNot(CandidTypeKind.nat64));
        expect(classifyCandidType('nat8'), isNot(CandidTypeKind.nat));
      });

      test('nat8foo is unknown (NOT nat8 — no prefix matching)', () {
        expect(classifyCandidType('nat8foo'), CandidTypeKind.unknown);
      });

      test('natural is unknown (NOT nat)', () {
        expect(classifyCandidType('natural'), CandidTypeKind.unknown);
      });

      test('vector is unknown (NOT vec)', () {
        expect(classifyCandidType('vector'), CandidTypeKind.unknown);
      });

      test('recorder is unknown (NOT record)', () {
        expect(classifyCandidType('recorder'), CandidTypeKind.unknown);
      });
    });

    group('case + whitespace robustness', () {
      test('leading/trailing whitespace is trimmed', () {
        expect(classifyCandidType('  nat  '), CandidTypeKind.nat);
        expect(classifyCandidType('\tvec text\n'), CandidTypeKind.vec);
      });

      test('mixed case is lowercased', () {
        expect(classifyCandidType('NAT'), CandidTypeKind.nat);
        expect(classifyCandidType('Text'), CandidTypeKind.text);
        expect(classifyCandidType('RECORD { ... }'), CandidTypeKind.record);
      });
    });

    group('non-canonical UI aliases (historic)', () {
      test('string -> text', () {
        expect(classifyCandidType('string'), CandidTypeKind.text);
      });

      test('boolean -> bool', () {
        expect(classifyCandidType('boolean'), CandidTypeKind.boolean);
      });

      test('float (no width) -> float64', () {
        expect(classifyCandidType('float'), CandidTypeKind.float64);
      });
    });

    group('unknown / edge cases', () {
      test('empty string', () {
        expect(classifyCandidType(''), CandidTypeKind.unknown);
      });

      test('whitespace only', () {
        expect(classifyCandidType('   '), CandidTypeKind.unknown);
      });

      test('unrecognised candid keyword (func)', () {
        expect(classifyCandidType('func (text) -> (text)'),
            CandidTypeKind.unknown);
      });

      test('unrecognised candid keyword (blob)', () {
        // No UI site special-cases blob today; classify as unknown so the
        // existing fall-through behaviour is preserved verbatim.
        expect(classifyCandidType('blob'), CandidTypeKind.unknown);
      });

      test('unrecognised candid keyword (service)', () {
        expect(classifyCandidType('service { foo : func () -> () }'),
            CandidTypeKind.unknown);
      });

      test('unrecognised type name', () {
        expect(classifyCandidType('MyTypeAlias'), CandidTypeKind.unknown);
      });

      test('non-identifier leading char', () {
        expect(classifyCandidType('{...}'), CandidTypeKind.unknown);
        expect(classifyCandidType('<nat>'), CandidTypeKind.unknown);
      });
    });
  });

  group('CandidTypeKind derived getters', () {
    group('isNumeric', () {
      test('true for every integer + float kind', () {
        for (final k in [
          CandidTypeKind.nat,
          CandidTypeKind.int,
          CandidTypeKind.nat8,
          CandidTypeKind.nat16,
          CandidTypeKind.nat32,
          CandidTypeKind.nat64,
          CandidTypeKind.int8,
          CandidTypeKind.int16,
          CandidTypeKind.int32,
          CandidTypeKind.int64,
          CandidTypeKind.float32,
          CandidTypeKind.float64,
        ]) {
          expect(k.isNumeric, isTrue, reason: '$k should be numeric');
        }
      });

      test('false for non-numeric kinds', () {
        for (final k in [
          CandidTypeKind.boolean,
          CandidTypeKind.text,
          CandidTypeKind.principal,
          CandidTypeKind.vec,
          CandidTypeKind.record,
          CandidTypeKind.variant,
          CandidTypeKind.opt,
          CandidTypeKind.unknown,
        ]) {
          expect(k.isNumeric, isFalse, reason: '$k should not be numeric');
        }
      });
    });

    group('isUnboundedInteger', () {
      test('true only for nat / int', () {
        expect(CandidTypeKind.nat.isUnboundedInteger, isTrue);
        expect(CandidTypeKind.int.isUnboundedInteger, isTrue);
      });

      test('false for fixed-width integers', () {
        expect(CandidTypeKind.nat8.isUnboundedInteger, isFalse);
        expect(CandidTypeKind.nat64.isUnboundedInteger, isFalse);
        expect(CandidTypeKind.int64.isUnboundedInteger, isFalse);
      });
    });

    group('isFixedWidthInteger', () {
      test('true for nat8/16/32/64 + int8/16/32/64', () {
        for (final k in [
          CandidTypeKind.nat8,
          CandidTypeKind.nat16,
          CandidTypeKind.nat32,
          CandidTypeKind.nat64,
          CandidTypeKind.int8,
          CandidTypeKind.int16,
          CandidTypeKind.int32,
          CandidTypeKind.int64,
        ]) {
          expect(k.isFixedWidthInteger, isTrue, reason: '$k');
        }
      });

      test('false for unbounded integers', () {
        expect(CandidTypeKind.nat.isFixedWidthInteger, isFalse);
        expect(CandidTypeKind.int.isFixedWidthInteger, isFalse);
      });
    });

    group('isFloat', () {
      test('true only for float32 / float64', () {
        expect(CandidTypeKind.float32.isFloat, isTrue);
        expect(CandidTypeKind.float64.isFloat, isTrue);
        expect(CandidTypeKind.nat.isFloat, isFalse);
      });
    });

    group('isAggregate', () {
      test('true only for vec / record / variant', () {
        expect(CandidTypeKind.vec.isAggregate, isTrue);
        expect(CandidTypeKind.record.isAggregate, isTrue);
        expect(CandidTypeKind.variant.isAggregate, isTrue);
        expect(CandidTypeKind.opt.isAggregate, isFalse);
        expect(CandidTypeKind.unknown.isAggregate, isFalse);
      });
    });
  });
}
