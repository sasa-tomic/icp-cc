// R-3 WU-2 — jsExec golden-vector CONTRACT test (VM).
//
// The QuickJS engine is browser-only (dart:js_interop can't run in the VM —
// plan §2.3), so this test does NOT execute the engine. It pins the contract
// the browser harness verifies, so a regression in the vector definitions or
// the assertion logic is caught without launching a browser:
//   1. The [jsExecGoldenVectors] catalogue covers every Rust `execute_js_json`
//      test by name (the parity bar — nothing silently dropped).
//   2. Each success vector's hand-crafted [expected] envelope PASSES its own
//      [assertion] (the predicate is self-consistent with the expected value).
//   3. The error vectors assert the right variant prefix (`js error:` vs
//      `json error:`) — the envelope SHAPE that must match native regardless of
//      the descriptive detail differing.
//
// The REAL end-to-end parity proof (engine actually produces these) is the
// Playwright harness:  just verify-quickjs-web-parity

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/js_exec_golden_vectors.dart';

void main() {
  group('jsExec golden-vector catalogue (WU-2 contract)', () {
    // The Rust test names this catalogue must cover (js_engine.rs:739-944).
    const expectedNames = <String>{
      'simple_math',
      'with_arg_roundtrip',
      'json_helpers',
      'execute_returns_err_on_syntax_error',
      'execute_returns_json_error_on_bad_arg',
      'helper_icp_call',
      'helper_icp_call_no_arg',
      'helper_icp_batch',
      'helper_icp_message',
      'helper_icp_message_defaults',
      'helper_icp_ui_list',
      'helper_icp_result_display',
      'helper_icp_searchable_list',
      'helper_icp_searchable_list_default_true',
      'helper_icp_section',
      'helper_icp_table',
      'helper_icp_format_number',
      'helper_icp_format_number_invalid',
      'helper_icp_format_icp',
      'helper_icp_format_timestamp',
      'helper_icp_format_bytes',
      'helper_icp_truncate_is_identity',
      'helper_icp_filter_items',
      'helper_icp_sort_items_ascending',
      'helper_icp_sort_items_descending',
      'helper_icp_group_by',
    };

    test('catalogue covers every Rust execute_js_json test by name', () {
      final names = jsExecGoldenVectors.map((v) => v.name).toSet();
      for (final n in expectedNames) {
        expect(names, contains(n), reason: 'missing parity vector: $n');
      }
      expect(jsExecGoldenVectors.length, greaterThanOrEqualTo(expectedNames.length));
    });

    test('every success vector has a self-consistent expected envelope', () {
      // The hand-crafted [expected] must PASS its own [assertion] — proves the
      // predicate encodes the right expectation (and the expected value is the
      // native output). Error vectors carry no [expected] (detail differs).
      for (final v in jsExecGoldenVectors) {
        if (!v.expectOk) continue;
        final expected = v.expected;
        if (expected == null) continue; // e.g. helper_icp_call_no_arg (omitted)
        final fail = v.assertion(expected);
        expect(
          fail,
          isNull,
          reason:
              '${v.name}: assertion rejects its own expected envelope — $fail',
        );
        // The expected envelope must itself be JSON-serialisable (the shape the
        // engine produces and the host decodes).
        expect(() => jsonEncode(expected), returnsNormally);
      }
    });

    test('error vectors assert the native variant prefix', () {
      // Native FFI maps JsExecError::Js → "js error: …" and ::Json →
      // "json error: …" (err_ptr + #[error("js error: {0}")]). The web bridge
      // MUST use the same prefixes so the envelope shape matches even though
      // the descriptive detail differs.
      final byName = {for (final v in jsExecGoldenVectors) v.name: v};
      expect(
        byName['execute_returns_err_on_syntax_error']!
            .assertion(<String, dynamic>{'ok': false, 'error': 'js error: boom'}),
        isNull,
        reason: 'syntax-error vector must accept the "js error:" prefix',
      );
      expect(
        byName['execute_returns_err_on_syntax_error']!
            .assertion(<String, dynamic>{'ok': false, 'error': 'boom'}),
        isNotNull,
        reason: 'syntax-error vector must reject a missing "js error:" prefix',
      );
      expect(
        byName['execute_returns_json_error_on_bad_arg']!.assertion(
            <String, dynamic>{'ok': false, 'error': 'json error: bad'}),
        isNull,
        reason: 'bad-arg vector must accept the "json error:" prefix',
      );
    });
  });
}
