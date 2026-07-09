// R-3b WU-2 — `parseCandid` parity test (VM, pure Dart).
//
// Asserts the pure-Dart `parseCandidInterface` port produces BYTE-IDENTICAL
// compact JSON to the native Rust `parse_candid_interface` for every vector in
// `candidParseGoldenVectors`. Each vector's `expectedJson` was captured from
// the native FFI (`serde_json::to_string` compact) — see the vectors file.
//
// Because `parseCandid` is pure Dart (no `dart:js_interop`, no network), this
// is the FULL parity bar (unlike the quickjs golden vectors, which split
// static/runtime stages between VM and the Chrome probe). The live end-to-end
// proof (fetch a real canister `.did` through the proxy + parse it) is the
// `just verify-ic-agent-web` Chrome harness.
//
// Run:  cd apps/autorun_flutter && flutter test test/features/web/candid_parse_golden_vectors_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/candid_interface_parser.dart';
import 'package:icp_autorun/rust/web/candid_parse_golden_vectors.dart';

void main() {
  group('parseCandid golden vectors (native parity, byte-identical JSON)', () {
    for (final v in candidParseGoldenVectors) {
      test('${v.name} produces byte-identical JSON to native', () {
        final actual = parseCandidInterface(v.did);
        expect(actual, isNotNull, reason: '${v.name}: parser returned null');
        expect(actual, v.expectedJson,
            reason: '${v.name}: JSON mismatch vs native\n'
                '  expected: ${v.expectedJson}\n'
                '  actual:   $actual');
      });
    }

    test('invalid candid returns null (parity: native null_c_string on Err)', () {
      expect(parseCandidInterface('not valid candid at all'), isNull);
      expect(parseCandidInterface(''), isNull);
      expect(parseCandidInterface('service : { broken :'), isNull);
      expect(parseCandidInterface('type T = ;'), isNull);
    });

    test('a did with no service returns null (no actor → native errors)', () {
      // `parse_candid_interface` errors when there is no service/actor
      // (`check_prog` returns `None` → `CanisterClientError::CandidParse`).
      expect(parseCandidInterface('type T = nat;'), isNull);
    });

    test('method name with quoted string is preserved raw (not ident-quoted)', () {
      // The JSON `name` field is the raw method name (native: `name.to_string()`),
      // NOT `ident_string`-quoted. A method named via a quoted string keeps its
      // raw value. (Type Var rendering, by contrast, DOES ident_string-quote.)
      final did = r'''
        service : {
          "weird name" : () -> () query;
        }
      ''';
      final json = parseCandidInterface(did);
      expect(json, isNotNull);
      expect(json, contains('"name":"weird name"'));
    });
  });
}
