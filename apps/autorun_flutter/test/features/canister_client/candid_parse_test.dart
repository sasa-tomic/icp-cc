// QS-2 (F-1 / F-2 / TD-9) — Candid parse-path coverage.
//
// Exercises `CandidService.fetchCanisterMethods` with REAL Candid interface
// text (no parser mocking) and asserts:
//   - ICRC read methods (`symbol`, `decimals`, `name`, `balance_of`,
//     `total_supply`, `fee`) are classified as **query** from the Candid
//     annotation — the F-1 bug was that the deleted name-prefix heuristic
//     (`_inferMethodMode`) defaulted them to **update** (none start with
//     `get_`/`list_`/…), sending update calls where a query would do.
//   - write methods (`transfer`, `approve`, no annotation) are **update**.
//   - `composite_query` → composite; explicit `query` vs no annotation.
//   - malformed/garbage Candid throws a typed [CandidParseException] — the F-2
//     bug was a `catch (e) { return []; }` that silently produced an empty
//     dropdown.
//
// The injected fetcher stands in for the certified read_state path (the
// optional `__get_candid_interface_tmp` probe misses in the test env and
// falls through, exactly as in `candid_fetch_test.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/canister_method.dart';
import 'package:icp_autorun/services/candid_service.dart';

const _canisterId = 'ryjl3-tyaaa-aaaaa-aaaba-cai'; // ICP Ledger id (fixture only)

/// Injected fetcher that returns [candid] verbatim.
CandidService _serviceFor(String candid) =>
    CandidService(fetchCandid: (_, __) async => candid);

/// Fetches methods, asserting the call succeeds, and returns them keyed by name
/// for per-method assertions.
Future<Map<String, CanisterMethod>> _methodsByName(String candid) async {
  final methods = await _serviceFor(candid).fetchCanisterMethods(_canisterId);
  return {for (final m in methods) m.name: m};
}

void main() {
  group('CandidService parse path (QS-2: F-1 mode-from-annotation, F-2, TD-9)',
      () {
    test('ICRC read methods are query from the annotation (was: update by name)',
        () async {
      // A realistic ICRC-1 ledger-shaped interface. Every read method is
      // annotated `query`; none start with a query name prefix, so the old
      // `_inferMethodMode` classified them all as update (mode 1) — F-1.
      const candid = r'''
        type Account = record { owner : principal; subaccount : opt blob };
        service : {
          name : () -> (text) query;
          symbol : () -> (text) query;
          decimals : () -> (nat8) query;
          fee : () -> (nat) query;
          total_supply : () -> (nat) query;
          balance_of : (Account) -> (nat) query;
          transfer : (Account, nat) -> (variant { Ok; Err : text });
          approve : (Account, nat) -> (variant { Ok; Err : text });
        }
      ''';

      final byName = await _methodsByName(candid);

      // F-1 fix: read methods annotated `query` → mode 0 (query).
      for (final queryMethod in const [
        'name',
        'symbol',
        'decimals',
        'fee',
        'total_supply',
        'balance_of',
      ]) {
        expect(byName, contains(queryMethod));
        expect(byName[queryMethod]!.mode, 0,
            reason: '$queryMethod is annotated `query` → must be mode 0, but '
                'the deleted name-prefix heuristic returned 1 (F-1)');
      }
    });

    test('write methods without annotation default to update (mode 1)',
        () async {
      const candid = r'''
        type Account = record { owner : principal };
        service : {
          transfer : (Account, nat) -> (variant { Ok; Err : text });
          approve : (Account, nat) -> (variant { Ok; Err : text });
        }
      ''';

      final byName = await _methodsByName(candid);

      for (final updateMethod in const ['transfer', 'approve']) {
        expect(byName, contains(updateMethod));
        expect(byName[updateMethod]!.mode, 1,
            reason: '$updateMethod has no annotation → update (mode 1) per '
                'the Candid spec');
      }
    });

    test('composite_query annotation maps to composite mode (2)', () async {
      const candid = r'''
        service : {
          deep_read : () -> (nat) composite_query;
        }
      ''';

      final byName = await _methodsByName(candid);

      expect(byName['deep_read']!.mode, 2);
    });

    test('explicit query vs no-annotation differ in mode (edge)', () async {
      const candid = r'''
        service : {
          annotated : () -> () query;
          plain : () -> ();
        }
      ''';

      final byName = await _methodsByName(candid);

      expect(byName['annotated']!.mode, 0, reason: 'annotated `query` → 0');
      expect(byName['plain']!.mode, 1, reason: 'no annotation → update (1)');
    });

    test('oneway annotation is update (mode 1)', () async {
      const candid = r'''
        service : {
          fire_and_forget : () -> () oneway;
        }
      ''';

      final byName = await _methodsByName(candid);

      expect(byName['fire_and_forget']!.mode, 1);
    });

    test('args + returnType are carried through with real types', () async {
      const candid = r'''
        type Account = record { owner : principal };
        service : {
          balance_of : (Account) -> (nat) query;
          pair : (text, nat64) -> (record { text; nat64 });
        }
      ''';

      final byName = await _methodsByName(candid);

      // balance_of: one arg typed by its declared alias name (`Account` — the
      // parser keeps arg types as-declared, parity with native), nat return.
      final balance = byName['balance_of']!;
      expect(balance.args, hasLength(1));
      expect(balance.args.first.type, 'Account');
      expect(balance.returnType, 'nat');
      expect(balance.mode, 0);

      // pair: two positional args with correct types (arg names are positional).
      final pair = byName['pair']!;
      expect(pair.args.map((a) => a.type), ['text', 'nat64']);
      expect(pair.args.map((a) => a.name), ['arg0', 'arg1']);
      expect(pair.mode, 1);
    });

    test('methods are returned alphabetically (parity with native sort)',
        () async {
      const candid = r'''
        service : {
          zeta : () -> () query;
          alpha : () -> () query;
          mid : () -> () query;
        }
      ''';

      final methods = await _serviceFor(candid).fetchCanisterMethods(_canisterId);

      expect(methods.map((m) => m.name), ['alpha', 'mid', 'zeta']);
    });

    group('malformed Candid throws a typed error (F-2: was silent [])', () {
      Future<void> expectParseError(String candid, {String? reason}) async {
        final service = _serviceFor(candid);
        late final CandidParseException captured;
        try {
          await service.fetchCanisterMethods(_canisterId);
          fail('expected CandidParseException but call succeeded$reason');
        } on CandidParseException catch (e) {
          captured = e;
        }
        expect(captured.kind, CandidParseErrorKind.malformed,
            reason: 'parse failure must surface a typed kind, not [] (F-2)$reason');
      }

      test('garbage text', () async {
        await expectParseError('not valid candid at all');
      });

      test('truncated / broken service block', () async {
        await expectParseError('service : { broken :');
      });

      test('a type decl with no service actor', () async {
        await expectParseError('type T = nat;', reason: ' (no service)');
      });
    });

    test('a valid interface with only alias-referenced methods is empty ([])',
        () async {
      // `aliased : T` has a Var type → skipped by parse_candid_interface's
      // `if let TypeInner::Func(f)`. A valid parse with zero inline-func
      // methods is legitimately empty — NOT a parse error.
      const candid = r'''
        type T = func () -> ();
        service : {
          aliased : T;
        }
      ''';

      final methods = await _serviceFor(candid).fetchCanisterMethods(_canisterId);

      expect(methods, isEmpty);
    });
  });
}
