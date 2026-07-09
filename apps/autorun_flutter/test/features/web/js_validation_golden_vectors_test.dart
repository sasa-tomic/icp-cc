// R-3 WU-5 — validate/lint golden-vector CONTRACT test (VM).
//
// Mirrors `js_exec_parity_test.dart` / `js_app_lifecycle_parity_test.dart`: the
// runtime stage is browser-only, so this VM test does NOT execute the engine.
// It pins the contract the browser harness verifies:
//   1. The [jsValidationGoldenVectors] catalogue covers every Rust
//      `validate_js_comprehensive` / `lint_js` test by name (the parity bar —
//      nothing silently dropped).
//   2. Every STATIC-only vector (needsRuntimeStage=false) PASSES its
//      [assertion] when run through the pure-Dart `runStaticStages` — proves
//      the rule port is correct for the cases that don't need QuickJS.
//
// The runtime-stage vectors (missing functions / syntax error / valid script)
// are exercised ONLY by the Chrome parity probe:  just verify-quickjs-web-parity

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/js_static_analysis.dart';
import 'package:icp_autorun/rust/web/js_validation_golden_vectors.dart';

void main() {
  group('validate/lint golden-vector catalogue (WU-5 contract)', () {
    // The Rust test names this catalogue must cover (js_engine.rs:1110-1441).
    const expectedNames = <String>{
      'validate_valid_production_script',
      'validate_blocks_eval',
      'validate_blocks_function_constructor_and_require',
      'validate_accepts_benign_function_substring_identifiers',
      'validate_rejects_new_function_constructor',
      'validate_rejects_globalthis_function_call',
      'validate_rejects_bare_function_call',
      'validate_accepts_benign_eval_substring_identifier',
      'validate_blocks_top_level_export',
      'validate_blocks_top_level_import',
      'validate_ui_node_extended_types_no_warning',
      'validate_ui_node_removed_input_type_warns',
      'validate_blocks_intl',
      'validate_example_warns_on_secret_not_error',
      'validate_missing_required_functions',
      'validate_syntax_error_reported',
      'validate_ui_nodes_unknown_type_warns',
      'validate_ui_nodes_empty_type_errors',
      'lint_js_returns_json_shape',
    };

    test('catalogue covers every Rust validate_js_comprehensive test by name',
        () {
      final names = jsValidationGoldenVectors.map((v) => v.name).toSet();
      for (final n in expectedNames) {
        expect(names, contains(n), reason: 'missing parity vector: $n');
      }
      expect(jsValidationGoldenVectors.length,
          greaterThanOrEqualTo(expectedNames.length));
    });

    test('every static-only vector passes its assertion via runStaticStages',
        () {
      // The pure-Dart bar: vectors whose outcome does NOT depend on the
      // browser runtime stage must pass through `runStaticStages` alone.
      for (final v in jsValidationGoldenVectors) {
        if (v.needsRuntimeStage) continue;
        final context = v.context ?? defaultContext(v.script);
        final result = runStaticStages(v.script, context);
        expect(result.isValid, v.expectValid,
            reason:
                '${v.name}: expected isValid=${v.expectValid}, got ${result.isValid}');
        final fail = v.assertion(result);
        expect(
          fail,
          isNull,
          reason: '${v.name}: assertion rejected the static result — $fail',
        );
      }
    });

    test('runtime-stage vectors are flagged for the Chrome probe', () {
      // These MUST be exercised by `just verify-quickjs-web-parity`; flagging
      // them here guards against accidentally asserting them VM-side (where the
      // engine cannot run).
      final runtimeNames = jsValidationGoldenVectors
          .where((v) => v.needsRuntimeStage)
          .map((v) => v.name)
          .toSet();
      expect(runtimeNames,
          contains('validate_missing_required_functions'));
      expect(runtimeNames, contains('validate_syntax_error_reported'));
      expect(runtimeNames, contains('validate_valid_production_script'));
      expect(runtimeNames, contains('lint_js_returns_json_shape'));
    });
  });
}
