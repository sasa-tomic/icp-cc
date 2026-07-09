// R-3 WU-2 — jsExec golden vectors (parity bar).
//
// Mirrors the `execute_js_json` test suite in
// `crates/icp_core/src/js_engine.rs:739-944` (`simple_math`, `with_arg_*`,
// `json_helpers`, the error variants, and every `helper_icp_*` helper). Each
// vector is the SAME (script, arg) pair the native engine is asserted against;
// the Web engine MUST produce an envelope whose decoded fields match.
//
// Two consumers:
//  - `web_probe_parity_main.dart` (browser) runs each vector through the REAL
//    WebQuickJsEngine and applies [assertion] to the decoded envelope. This is
//    the end-to-end parity proof (the engine is browser-only — plan §2.3).
//  - `js_exec_parity_test.dart` (VM) pins the catalog + the [expected]
//    envelopes so the contract is documented and a regression in the vector
//    definitions is caught without a browser.
//
// `assertion` returns `null` on pass or a human failure message. It encodes
// the EXPECTED behaviour (the same predicate the Rust test asserts), NOT a
// full-string equality — matching the Rust tests' granularity and avoiding
// JSON key-order fragility.

/// One jsExec golden vector (port of a Rust `execute_js_json` test).
class JsExecGoldenVector {
  const JsExecGoldenVector({
    required this.name,
    required this.script,
    this.jsonArg,
    required this.expectOk,
    required this.assertion,
    this.expected,
  });

  /// Stable identifier (matches the Rust test name where applicable).
  final String name;

  /// The script evaluated verbatim (no transpiler — plan §1.1).
  final String script;

  /// Optional `globalThis.arg` JSON (validated + parsed inside the sandbox).
  final String? jsonArg;

  /// Expected `ok` flag of the decoded envelope.
  final bool expectOk;

  /// Predicate over the decoded envelope: `null` = pass, else a failure msg.
  final String? Function(Map<String, dynamic> envelope) assertion;

  /// A hand-crafted passing envelope (for VM contract-pinning; `null` for the
  /// error vectors whose detail string differs between native and Web).
  final Map<String, dynamic>? expected;
}

/// Wraps a bare helper call as `(call)` — mirrors the Rust `run_helper_in_js`
/// (`js_engine.rs:784-789`): `execute_js_json(format!("({})", helper_call))`.
String _helper(String call) => '($call)';

/// The catalogue. Add WU-3 (lifecycle) vectors in a sibling file.
final List<JsExecGoldenVector> jsExecGoldenVectors = <JsExecGoldenVector>[
  JsExecGoldenVector(
    name: 'simple_math',
    script: '1 + 2',
    expectOk: true,
    assertion: _resultEquals(3),
    expected: <String, dynamic>{'ok': true, 'result': 3, 'messages': <dynamic>[]},
  ),
  JsExecGoldenVector(
    name: 'with_arg_roundtrip',
    script: 'get_arg().a',
    jsonArg: '{"a": 1}',
    expectOk: true,
    assertion: _resultEquals(1),
    expected: <String, dynamic>{
      'ok': true,
      'result': 1,
      'messages': <dynamic>[]
    },
  ),
  JsExecGoldenVector(
    name: 'json_helpers',
    script: 'JSON.parse(JSON.stringify({x: 10, y: 20})).x + '
        'JSON.parse(JSON.stringify({x: 10, y: 20})).y',
    expectOk: true,
    assertion: _resultEquals(30),
    expected: <String, dynamic>{
      'ok': true,
      'result': 30,
      'messages': <dynamic>[]
    },
  ),
  // Error vectors: the detail string differs between native (generic
  // "JavaScript exception") and Web (descriptive QuickJS message), so we assert
  // only the envelope SHAPE + the variant prefix. [expected] is therefore null.
  JsExecGoldenVector(
    name: 'execute_returns_err_on_syntax_error',
    script: 'function(}',
    expectOk: false,
    assertion: _errorContains('js error'),
  ),
  JsExecGoldenVector(
    name: 'execute_returns_json_error_on_bad_arg',
    script: '1',
    jsonArg: 'not-json',
    expectOk: false,
    assertion: _errorContains('json error'),
  ),
  // ── host helpers (runtime.rs:64-85) — every helper_icp_* Rust test ──────
  JsExecGoldenVector(
    name: 'helper_icp_call',
    script: _helper("icp_call({ canister: 'a-b', method: 'm', args: {} })"),
    expectOk: true,
    assertion: (env) => _all(env, {
      'action': 'call',
      'canister': 'a-b',
      'method': 'm',
    }),
    expected: <String, dynamic>{
      'ok': true,
      'result': <String, dynamic>{
        'canister': 'a-b',
        'method': 'm',
        'args': <String, dynamic>{},
        'action': 'call'
      },
      'messages': <dynamic>[]
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_call_no_arg',
    script: _helper('icp_call()'),
    expectOk: true,
    assertion: (env) => _fieldEquals(env, 'action', 'call'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_batch',
    script: _helper("icp_batch({ calls: [ { canister: 'a' }, { canister: 'b' } ] })"),
    expectOk: true,
    assertion: (env) {
      final r = env['result'];
      if (r is! Map) return 'result not a map';
      if (r['action'] != 'batch') return "action != 'batch'";
      final calls = r['calls'];
      if (calls is! Map) return 'calls not the passed object';
      final inner = calls['calls'];
      if (inner is! List || inner.length != 2) return 'calls.calls len != 2';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_message',
    script: _helper("icp_message({ text: 'Hello', type: 'info' })"),
    expectOk: true,
    assertion: (env) => _all(env, {
      'action': 'message',
      'text': 'Hello',
      'type': 'info',
    }),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_message_defaults',
    script: _helper('icp_message()'),
    expectOk: true,
    assertion: (env) => _all(env, {
      'text': '',
      'type': 'info',
    }),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_ui_list',
    script: _helper("icp_ui_list({ items: ['a', 'b', 'c'] })"),
    expectOk: true,
    assertion: (env) {
      final ui = (env['result'] as Map?)?['ui'];
      if (ui is! Map) return 'result.ui not a map';
      if (ui['type'] != 'list') return "ui.type != 'list'";
      if ((ui['items'] as List?)?.length != 3) return 'items len != 3';
      if (ui['buttons'] is! List) return 'buttons not an array';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_result_display',
    script: _helper("icp_result_display({ result: 'ok', type: 'success' })"),
    expectOk: true,
    assertion: (env) {
      final ui = (env['result'] as Map?)?['ui'];
      if (ui is! Map) return 'result.ui not a map';
      if (ui['type'] != 'result_display') return "ui.type != 'result_display'";
      final props = ui['props'];
      if (props is! Map) return 'props not a map';
      if (props['result'] != 'ok') return "props.result != 'ok'";
      if (props['type'] != 'success') return "props.type != 'success'";
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_searchable_list',
    script: _helper("icp_searchable_list({ items: [1, 2], title: 'Recent', searchable: true })"),
    expectOk: true,
    assertion: (env) {
      final props = ((env['result'] as Map?)?['ui'] as Map?)?['props'];
      if (props is! Map) return 'ui.props not a map';
      if (props['searchable'] != true) return 'searchable != true';
      if (props['title'] != 'Recent') return "title != 'Recent'";
      if ((props['items'] as List?)?.length != 2) return 'items len != 2';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_searchable_list_default_true',
    script: _helper('icp_searchable_list({ items: [1] })'),
    expectOk: true,
    assertion: (env) {
      final props = ((env['result'] as Map?)?['ui'] as Map?)?['props'];
      if (props is! Map) return 'ui.props not a map';
      if (props['searchable'] != true) return 'default searchable != true';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_section',
    script: _helper("icp_section({ title: 'T', content: 'C' })"),
    expectOk: true,
    assertion: (env) {
      final props = ((env['result'] as Map?)?['ui'] as Map?)?['props'];
      if (props is! Map) return 'ui.props not a map';
      if (props['title'] != 'T') return "title != 'T'";
      if (props['content'] != 'C') return "content != 'C'";
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_table',
    script: _helper("icp_table({ data: [{a:1}], headers: ['a'] })"),
    expectOk: true,
    assertion: (env) {
      final props = ((env['result'] as Map?)?['ui'] as Map?)?['props'];
      if (props is! Map) return 'ui.props not a map';
      if ((props['headers'] as List?)?.length != 1) return 'headers len != 1';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_format_number',
    script: _helper('icp_format_number(123.456, 2)'),
    expectOk: true,
    assertion: _resultEquals('123.456'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_format_number_invalid',
    script: _helper("icp_format_number('abc')"),
    expectOk: true,
    assertion: _resultEquals('0'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_format_icp',
    script: _helper('icp_format_icp(123456789, 8)'),
    expectOk: true,
    assertion: _resultEquals('1.23456789'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_format_timestamp',
    script: _helper('icp_format_timestamp(1634567890)'),
    expectOk: true,
    assertion: _resultEquals('1634567890'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_format_bytes',
    script: _helper('icp_format_bytes(1024)'),
    expectOk: true,
    assertion: _resultEquals('1024'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_truncate_is_identity',
    script: _helper("icp_truncate('a long text here', 5)"),
    expectOk: true,
    // Rust: `icp_truncate('a long text here', 5)` → the helper returns the
    // string verbatim (identity). We assert that directly.
    assertion: _resultEquals('a long text here'),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_filter_items',
    script: _helper("icp_filter_items([{c:'NY'},{c:'LA'},{c:'NY'}], 'c', 'NY')"),
    expectOk: true,
    assertion: (env) {
      final r = env['result'];
      if (r is! List || r.length != 2) return 'filtered len != 2';
      return null;
    },
  ),
  JsExecGoldenVector(
    name: 'helper_icp_sort_items_ascending',
    script: _helper("icp_sort_items([{n:'C'},{n:'A'},{n:'B'}], 'n', true)"),
    expectOk: true,
    assertion: (env) => _orderedField(env, <String>['A', 'B', 'C']),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_sort_items_descending',
    script: _helper("icp_sort_items([{n:'A'},{n:'C'},{n:'B'}], 'n', false)"),
    expectOk: true,
    assertion: (env) => _orderedField(env, <String>['C', 'B', 'A']),
  ),
  JsExecGoldenVector(
    name: 'helper_icp_group_by',
    script: _helper("icp_group_by([{c:'NY',n:'A'},{c:'LA',n:'B'},{c:'NY',n:'C'}], 'c')"),
    expectOk: true,
    assertion: (env) {
      final r = env['result'];
      if (r is! Map) return 'result not a map';
      if ((r['NY'] as List?)?.length != 2) return 'NY len != 2';
      if ((r['LA'] as List?)?.length != 1) return 'LA len != 1';
      return null;
    },
  ),
];

// ── assertion builders (null = pass, String = failure message) ──────────────

String? Function(Map<String, dynamic>) _resultEquals(Object expected) =>
    (env) => env['result'] == expected
        ? null
        : "result(${env['result']}) != expected($expected)";

String? Function(Map<String, dynamic>) _errorContains(String needle) =>
    (env) {
      final err = env['error']?.toString() ?? '';
      return err.contains(needle) ? null : "error($err) missing '$needle'";
    };

String? _fieldEquals(Map<String, dynamic> env, String key, Object expected) {
  final r = env['result'];
  if (r is! Map) return 'result not a map';
  return r[key] == expected ? null : "result.$key(${r[key]}) != $expected";
}

String? _all(Map<String, dynamic> env, Map<String, Object> fields) {
  final r = env['result'];
  if (r is! Map) return 'result not a map';
  for (final entry in fields.entries) {
    if (r[entry.key] != entry.value) {
      return 'result.${entry.key}(${r[entry.key]}) != ${entry.value}';
    }
  }
  return null;
}

String? _orderedField(Map<String, dynamic> env, List<String> expectedOrder) {
  final r = env['result'];
  if (r is! List) return 'result not a list';
  if (r.length != expectedOrder.length) return 'list len mismatch';
  for (var i = 0; i < expectedOrder.length; i++) {
    final item = r[i];
    if (item is! Map) return 'item $i not a map';
    if (item['n'] != expectedOrder[i]) {
      return 'item $i .n(${item['n']}) != ${expectedOrder[i]}';
    }
  }
  return null;
}
