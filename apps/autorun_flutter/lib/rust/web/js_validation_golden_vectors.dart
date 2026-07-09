// R-3 WU-5 — `validateJsComprehensive` / `jsLint` golden vectors (parity bar).
//
// Mirrors the `validate_js_comprehensive` + `lint_js` test suite in
// `crates/icp_core/src/js_engine.rs:1110-1441` (`validate_valid_production_script`,
// `validate_blocks_eval`, the `*function*` / `*eval*` identifier cases,
// `validate_blocks_top_level_import/export`, `validate_blocks_intl`, the
// `validate_ui_node_*` cases, `validate_missing_required_functions`,
// `validate_syntax_error_reported`, `validate_example_warns_on_secret_not_error`,
// `lint_js_returns_json_shape`). Each vector is the SAME (script, context) pair
// the native engine is asserted against; the Web bridge MUST produce a result
// whose validity + error/warning substrings match.
//
// Two consumers:
//  - `web_probe_parity_main.dart` (browser) runs each vector through the FULL
//    Web pipeline (pure-Dart static stages + the engine runtime stage) and
//    applies [assertion] to the resulting [JsValidationResult]. This is the
//    end-to-end parity proof (the runtime stage is browser-only).
//  - `js_validation_golden_vectors_test.dart` (VM) pins the catalogue by name
//    (covers every Rust validate test) and self-checks the STATIC-only vectors
//    through `runStaticStages` (the pure-Dart bar).
//
// [assertion] returns `null` on pass or a human failure message. It encodes the
// SAME predicate the Rust test asserts (substring matches on errors/warnings),
// not a full-string equality — matching the Rust tests' granularity.
//
// [context] is `null` for the auto-detect (`lint_js`) vectors; otherwise it is
// the explicit context the FFI `icp_js_validate_comprehensive` would build.
// [needsRuntimeStage] marks vectors whose outcome depends on the browser-only
// runtime stage (syntax check / required exports) and so are exercised ONLY by
// the Chrome parity probe, not the VM contract test.

import 'js_static_analysis.dart';

/// One validate/lint golden vector (port of a Rust `validate_js_comprehensive`
/// or `lint_js` test).
class JsValidationGoldenVector {
  const JsValidationGoldenVector({
    required this.name,
    required this.script,
    required this.expectValid,
    required this.assertion,
    this.context,
    this.needsRuntimeStage = false,
  });

  /// Stable identifier (matches the Rust test name).
  final String name;

  /// The script validated verbatim.
  final String script;

  /// Explicit context (`null` → [defaultContext], the `lint_js` path).
  final JsValidationContext? context;

  /// Expected `isValid` of the result.
  final bool expectValid;

  /// Predicate over the result: `null` = pass, else a failure message.
  final String? Function(JsValidationResult result) assertion;

  /// True when the outcome depends on the browser-only runtime stage (syntax
  /// check / required-exports). The VM contract test skips these; the Chrome
  /// parity probe runs them.
  final bool needsRuntimeStage;
}

/// Production context (`js_engine.rs:1102-1108`).
final JsValidationContext _prod = JsValidationContext(
  isExample: false,
  isTest: false,
  isProduction: true,
);

/// Example context (for `validate_example_warns_on_secret_not_error`).
final JsValidationContext _example = JsValidationContext(
  isExample: true,
  isTest: false,
  isProduction: false,
);

/// The minimal init/view/update trio (kept identical across vectors so only the
/// rule under test varies).
const String _iVu = 'function init(arg){ return {state:{},effects:[]}; }\n'
    'function view(state){ return {}; }\n'
    'function update(msg,state){ return {state:state,effects:[]}; }';

/// The catalogue. Consumed by the parity probe + VM contract test.
final List<JsValidationGoldenVector> jsValidationGoldenVectors =
    <JsValidationGoldenVector>[
  // js_engine.rs:1110-1131
  JsValidationGoldenVector(
    name: 'validate_valid_production_script',
    script: '''
            function init(arg) {
                return { state: { count: 0 }, effects: [] };
            }
            function view(state) {
                return { type: "text", props: { text: "Count: " + String(state.count) } };
            }
            function update(msg, state) {
                if (msg.type === "inc") {
                    state.count = state.count + 1;
                    return { state: state, effects: [] };
                }
                return { state: state, effects: [] };
            }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) => r.isValid && r.syntaxErrors.isEmpty
        ? null
        : 'expected valid, got errors: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1133-1143
  JsValidationGoldenVector(
    name: 'validate_blocks_eval',
    script: '''
            function init(arg) { eval("1"); return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('eval'))
        ? null
        : 'expected an eval error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1145-1157
  JsValidationGoldenVector(
    name: 'validate_blocks_function_constructor_and_require',
    script: '''
            var x = Function("return 1");
            var y = require("fs");
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) {
      if (!r.syntaxErrors.any((e) => e.contains('Function'))) {
        return 'expected a Function error, got: ${r.syntaxErrors}';
      }
      if (!r.syntaxErrors.any((e) => e.contains('require'))) {
        return 'expected a require error, got: ${r.syntaxErrors}';
      }
      return null;
    },
  ),
  // js_engine.rs:1159-1180
  JsValidationGoldenVector(
    name: 'validate_accepts_benign_function_substring_identifiers',
    // NOTE: `\$Function` is an escaped dollar (literal JS identifier
    // `$Function`) — mirrors the Rust test verbatim.
    script: '''
            function assertFunction(x) { return x; }
            const isFunction = (x) => typeof x === 'function';
            function _Function(x) { return x; }
            function \$Function(x) { return x; }
            function myFunction(x) { return x; }
            function init(arg) { assertFunction(1); isFunction(2); return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (r.syntaxErrors.any((e) => e.contains('Function'))) {
        return 'benign *Function identifiers must not be flagged: ${r.syntaxErrors}';
      }
      return r.isValid ? null : 'expected valid, got: ${r.syntaxErrors}';
    },
  ),
  // js_engine.rs:1182-1192
  JsValidationGoldenVector(
    name: 'validate_rejects_new_function_constructor',
    script: '''
            var x = new Function('return 1');
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('Function'))
        ? null
        : 'expected a Function error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1194-1204
  JsValidationGoldenVector(
    name: 'validate_rejects_globalthis_function_call',
    script: '''
            var x = globalThis.Function('return 1');
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('Function'))
        ? null
        : 'expected a Function error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1206-1216
  JsValidationGoldenVector(
    name: 'validate_rejects_bare_function_call',
    script: '''
            var f = Function('x', 'return x');
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('Function'))
        ? null
        : 'expected a Function error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1218-1234
  JsValidationGoldenVector(
    name: 'validate_accepts_benign_eval_substring_identifier',
    script: '''
            function myeval(x) { return x; }
            const resolvedEval = (x) => x;
            function init(arg) { myeval(1); resolvedEval(2); return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (r.syntaxErrors.any((e) => e.contains('eval'))) {
        return 'benign *eval identifiers must not be flagged: ${r.syntaxErrors}';
      }
      return r.isValid ? null : 'expected valid, got: ${r.syntaxErrors}';
    },
  ),
  // js_engine.rs:1236-1255
  JsValidationGoldenVector(
    name: 'validate_blocks_top_level_export',
    script: '''
            export function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) {
          final le = e.toLowerCase();
          return le.contains('esm') || le.contains('import') || le.contains('export');
        })
            ? null
            : 'expected an ESM/import/export error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1257-1277
  JsValidationGoldenVector(
    name: 'validate_blocks_top_level_import',
    script: '''
            import x from "y";
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) {
          final le = e.toLowerCase();
          return le.contains('esm') || le.contains('import') || le.contains('export');
        })
            ? null
            : 'expected an ESM/import/export error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1279-1310 (parametrised over the extended node types).
  JsValidationGoldenVector(
    name: 'validate_ui_node_extended_types_no_warning',
    script: '''
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "paginated_list", props: {} }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (r.warnings.any((w) => w.contains('Unknown UI node type'))) {
        return 'paginated_list should be allowlisted but warned: ${r.warnings}';
      }
      return r.isValid ? null : 'expected valid, got: ${r.syntaxErrors}';
    },
  ),
  // js_engine.rs:1312-1329
  JsValidationGoldenVector(
    name: 'validate_ui_node_removed_input_type_warns',
    script: '''
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "input", props: {} }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (!r.warnings.any(
          (w) => w.contains('Unknown UI node type') && w.contains('input'))) {
        return 'type input should be flagged unknown: ${r.warnings}';
      }
      return r.isValid ? null : 'expected valid, got: ${r.syntaxErrors}';
    },
  ),
  // js_engine.rs:1331-1348
  JsValidationGoldenVector(
    name: 'validate_blocks_intl',
    script: '''
            function init(arg) {
                var s = new Intl.NumberFormat('de-DE').format(1234.5);
                return { state: { s: s }, effects: [] };
            }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('Intl'))
        ? null
        : 'expected an Intl error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1350-1371
  JsValidationGoldenVector(
    name: 'validate_example_warns_on_secret_not_error',
    script: '''
            // EXAMPLE: demo
            function init(arg) {
                var pk = "sk-test123456789";
                return { state: { key: pk }, effects: [] };
            }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _example,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (!r.isValid) return 'expected valid, got: ${r.syntaxErrors}';
      if (!r.warnings.any((w) => w.contains('secret'))) {
        return 'expected a secret warning, got: ${r.warnings}';
      }
      return null;
    },
  ),
  // js_engine.rs:1373-1388 — RUNTIME stage (missing view/update).
  JsValidationGoldenVector(
    name: 'validate_missing_required_functions',
    script: '''
            function init(arg) { return { state: {}, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    needsRuntimeStage: true,
    assertion: (r) {
      if (r.isValid) return 'expected invalid, got valid';
      if (!r.syntaxErrors.any((e) => e.contains('view') && e.contains('not found'))) {
        return 'expected a view not-found error, got: ${r.syntaxErrors}';
      }
      if (!r.syntaxErrors.any((e) => e.contains('update') && e.contains('not found'))) {
        return 'expected an update not-found error, got: ${r.syntaxErrors}';
      }
      return null;
    },
  ),
  // js_engine.rs:1390-1398 — RUNTIME stage (syntax error).
  JsValidationGoldenVector(
    name: 'validate_syntax_error_reported',
    script: 'function init(arg) {',
    context: _prod,
    expectValid: false,
    needsRuntimeStage: true,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('Syntax error'))
        ? null
        : 'expected a Syntax error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1400-1415
  JsValidationGoldenVector(
    name: 'validate_ui_nodes_unknown_type_warns',
    script: '''
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) {
                return { type: "unknown_widget_type", props: { text: "x" } };
            }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) {
      if (!r.isValid) return 'expected valid, got: ${r.syntaxErrors}';
      if (!r.warnings.any((w) =>
          w.contains('Unknown UI node type') && w.contains('unknown_widget_type'))) {
        return 'expected an unknown_widget_type warning, got: ${r.warnings}';
      }
      return null;
    },
  ),
  // js_engine.rs:1417-1430
  JsValidationGoldenVector(
    name: 'validate_ui_nodes_empty_type_errors',
    script: '''
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "", props: { text: "x" } }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''',
    context: _prod,
    expectValid: false,
    assertion: (r) => r.syntaxErrors.any((e) => e.contains('empty type'))
        ? null
        : 'expected an empty-type error, got: ${r.syntaxErrors}',
  ),
  // js_engine.rs:1432-1441 — lint envelope shape. context=null (lint path).
  // The probe asserts the envelope keys directly; here the result is valid.
  JsValidationGoldenVector(
    name: 'lint_js_returns_json_shape',
    script: _iVu,
    context: null,
    expectValid: true,
    needsRuntimeStage: true,
    assertion: (r) => r.isValid
        ? null
        : 'expected the lint sample to be valid, got: ${r.syntaxErrors}',
  ),
];
