// R-3 WU-3 — jsApp lifecycle golden-vector CONTRACT test (VM).
//
// Mirrors `js_exec_parity_test.dart`: the engine is browser-only, so this VM
// test does NOT execute it. It pins the contract the browser harness verifies
// — the [jsAppGoldenVectors] catalogue covers every Rust `js_app_*` test by
// name (the parity bar) — so a dropped/silently-renamed vector is caught
// without launching a browser.
//
// The REAL end-to-end proof is:  just verify-quickjs-web-parity

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/js_app_golden_vectors.dart';

void main() {
  group('jsApp golden-vector catalogue (WU-3 contract)', () {
    // The Rust test names this catalogue must cover (js_engine.rs:947-1100),
    // plus the shipped hello-world bundle.
    const expectedNames = <String>{
      'app_init_view_update_roundtrip',
      'app_init_timeout',
      'app_view_invalid_state_json',
      'app_update_invalid_msg_json',
      'sample_app_default_works',
      'hello_world_bundle_init_view_update',
    };

    test('catalogue covers every Rust js_app_* test by name', () {
      final names = jsAppGoldenVectors.map((v) => v.name).toSet();
      for (final n in expectedNames) {
        expect(names, contains(n), reason: 'missing parity vector: $n');
      }
      expect(jsAppGoldenVectors.length, greaterThanOrEqualTo(expectedNames.length));
    });

    test('every vector defines a run + assertion', () {
      for (final v in jsAppGoldenVectors) {
        // The catalogue must be well-formed: a non-empty name + a run closure
        // (drives the lifecycle) + an assertion closure (the parity predicate).
        // The assertion's BEHAVIOUR (pass on the real checkpoints, clean fail
        // otherwise) is verified by the browser harness, not here.
        expect(v.name, isNotEmpty);
        expect(v.run, isNotNull);
        expect(v.assertion, isNotNull);
      }
    });
  });
}
