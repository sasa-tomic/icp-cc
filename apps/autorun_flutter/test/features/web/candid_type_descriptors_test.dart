// R-3b WU-3 — `methodTypeDescriptors` parity test (VM, pure Dart).
//
// Asserts the pure-Dart type-descriptor extraction (used by the Web
// `build_args_from_json` / `try_decode_with_types` parity path) produces the
// correct JSON descriptors for key candid type shapes: primitives, records,
// variants, opt, vec, func, and alias resolution (the TypeEnv / `check_prog`
// work native does). The descriptors are consumed by the JS bundle's
// `_toIdl()` converter to build agent-js IDL type objects for
// `IDL.encode` / `IDL.decode`.
//
// Run:  cd apps/autorun_flutter && flutter test test/features/web/candid_type_descriptors_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/candid_interface_parser.dart';

void main() {
  group('methodTypeDescriptors', () {
    test('primitives + empty args', () {
      const did = r'''
        service : {
          symbol : () -> (record { symbol : text }) query;
          decimals : () -> (record { decimals : nat32 }) query;
        }
      ''';
      final json = methodTypeDescriptors(did, 'symbol');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      expect(desc['args'], <dynamic>[]);
      expect(desc['rets'], [
        <String, dynamic>{
          't': 'record',
          'fields': [
            <String, dynamic>{'n': 'symbol', 't': <String, dynamic>{'t': 'text'}}
          ]
        }
      ]);
    });

    test('multiple arg types (text, nat64) → tuple record ret', () {
      const did = r'''
        service : {
          pair : (text, nat64) -> (record { 0 : text; 1 : nat64 });
        }
      ''';
      final json = methodTypeDescriptors(did, 'pair');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      expect(desc['args'], [
        <String, dynamic>{'t': 'text'},
        <String, dynamic>{'t': 'nat64'},
      ]);
      // Tuple record: fields with numeric ids 0, 1.
      final rets = desc['rets'] as List<dynamic>;
      expect(rets.length, 1);
      final rec = rets[0] as Map<String, dynamic>;
      expect(rec['t'], 'record');
      final fields = rec['fields'] as List<dynamic>;
      expect(fields.length, 2);
      expect((fields[0] as Map<String, dynamic>)['i'], 0);
      expect((fields[1] as Map<String, dynamic>)['i'], 1);
    });

    test('opt + vec + principal', () {
      const did = r'''
        service : {
          opts : (opt text) -> (opt principal);
          blobby : (vec nat8) -> (vec nat8);
        }
      ''';
      final json = methodTypeDescriptors(did, 'opts');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      expect(desc['args'], [
        <String, dynamic>{
          't': 'opt',
          'inner': <String, dynamic>{'t': 'text'}
        }
      ]);
      expect(desc['rets'], [
        <String, dynamic>{
          't': 'opt',
          'inner': <String, dynamic>{'t': 'principal'}
        }
      ]);
    });

    test('variant with null case', () {
      const did = r'''
        service : {
          v : () -> (variant { ok; err : text });
        }
      ''';
      final json = methodTypeDescriptors(did, 'v');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      final rets = desc['rets'] as List<dynamic>;
      expect(rets.length, 1);
      final variant = rets[0] as Map<String, dynamic>;
      expect(variant['t'], 'variant');
      final fields = variant['fields'] as List<dynamic>;
      // `ok` has null type; `err` has text type.
      expect(fields.length, 2);
      final okField = fields.firstWhere(
          (f) => (f as Map<String, dynamic>)['n'] == 'ok') as Map<String, dynamic>;
      expect((okField['t'] as Map<String, dynamic>)['t'], 'null');
    });

    test('alias resolution (type env)', () {
      const did = r'''
        type Tokens = record { e8s : nat64 };
        type Account = variant { id : nat64; principal : principal };
        service : {
          items : (vec Account, opt nat8) -> (Tokens);
        }
      ''';
      final json = methodTypeDescriptors(did, 'items');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      // arg 0: vec Account → resolved to vec variant { id: nat64; principal: principal }
      final args = desc['args'] as List<dynamic>;
      expect(args.length, 2);
      final vecAccount = args[0] as Map<String, dynamic>;
      expect(vecAccount['t'], 'vec');
      final account = vecAccount['inner'] as Map<String, dynamic>;
      expect(account['t'], 'variant');
      // ret: Tokens → resolved to record { e8s: nat64 }
      final rets = desc['rets'] as List<dynamic>;
      expect(rets.length, 1);
      final tokens = rets[0] as Map<String, dynamic>;
      expect(tokens['t'], 'record');
      final fields = tokens['fields'] as List<dynamic>;
      expect(fields.length, 1);
      expect((fields[0] as Map<String, dynamic>)['n'], 'e8s');
    });

    test('transitive alias resolution (A → B → nat)', () {
      const did = r'''
        type A = nat;
        type B = A;
        service : {
          f : (B) -> ();
        }
      ''';
      final json = methodTypeDescriptors(did, 'f');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      final args = desc['args'] as List<dynamic>;
      expect(args.length, 1);
      expect((args[0] as Map<String, dynamic>)['t'], 'nat');
    });

    test('method not found returns null', () {
      const did = r'''
        service : {
          symbol : () -> (text) query;
        }
      ''';
      expect(methodTypeDescriptors(did, 'nonexistent'), isNull);
    });

    test('invalid did returns null', () {
      expect(methodTypeDescriptors('not valid candid', 'f'), isNull);
      expect(methodTypeDescriptors('', 'f'), isNull);
    });

    test('func type in arg position', () {
      const did = r'''
        service : {
          f : (func (text) -> (nat) query) -> ();
        }
      ''';
      final json = methodTypeDescriptors(did, 'f');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      final args = desc['args'] as List<dynamic>;
      expect(args.length, 1);
      final func = args[0] as Map<String, dynamic>;
      expect(func['t'], 'func');
      expect(func['args'], [<String, dynamic>{'t': 'text'}]);
      expect(func['rets'], [<String, dynamic>{'t': 'nat'}]);
      expect(func['modes'], ['query']);
    });

    test('blob sugar (vec nat8)', () {
      const did = r'''
        service : {
          blobby : (blob) -> (blob);
        }
      ''';
      final json = methodTypeDescriptors(did, 'blobby');
      expect(json, isNotNull);
      final desc = jsonDecode(json!) as Map<String, dynamic>;
      final args = desc['args'] as List<dynamic>;
      // `blob` is sugar for `vec nat8` — the descriptor should show vec nat8.
      expect(args.length, 1);
      final vec = args[0] as Map<String, dynamic>;
      expect(vec['t'], 'vec');
      expect((vec['inner'] as Map<String, dynamic>)['t'], 'nat8');
    });
  });
}
