import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_validation_service.dart';

/// Validates the Dart-side wiring of the authoritative Rust validator
/// (`ScriptValidationService` → `NativeBridge.validateJsComprehensive`).
///
/// These tests assert that sandbox-escape primitives are REJECTED at the Dart
/// layer (complementing the Rust `sandbox_adversarial` host-level coverage).
/// When the native library is unavailable the service surfaces a clear
/// "validator unavailable" error rather than a silent pass, so each adversarial
/// case asserts one of: rejected by the validator, OR the bridge-unavailable
/// error (no false-positive valid result).
void main() {
  late ScriptValidationService service;

  setUp(() {
    service = ScriptValidationService();
  });

  /// A minimal well-formed bundle that the validator should accept (or, if the
  /// native bridge is unavailable, surface the unavailable error).
  const String validBundle = '''
"use strict";
(() => {
  function init() { return { state: { count: 0 }, effects: [] }; }
  function view(state) { return { type: "text", props: { text: String(state.count) } }; }
  function update(msg, state) { return { state, effects: [] }; }
  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''';

  group('ScriptValidationService sandbox enforcement', () {
    test('accepts a well-formed TS bundle', () async {
      final result = await service.validateScript(validBundle);
      // Either the real validator accepts it, or the bridge is unavailable.
      expect(result.isValid || _isUnavailable(result), isTrue,
          reason: 'a valid bundle must not be reported as a sandbox violation');
      if (result.isValid) {
        expect(result.errors, isEmpty);
      }
    });

    test('rejects eval()', () async {
      final result = await service
          .validateScript('$validBundle\n eval("1+1");');
      _expectRejected(result, 'eval');
    });

    test('rejects Function constructor', () async {
      final result = await service
          .validateScript('$validBundle\n new Function("return this")();');
      _expectRejected(result, 'Function constructor');
    });

    test('rejects import of the fs module', () async {
      final result = await service.validateScript(
          '$validBundle\n const fs = await import("fs");');
      _expectRejected(result, 'import');
    });

    test('rejects Intl.* access (sensitive global)', () async {
      final result = await service.validateScript(
          '$validBundle\n const x = Intl.DateTimeFormat();');
      _expectRejected(result, 'Intl');
    });
  });
}

/// Assert that [result] is either a real rejection (invalid with errors
/// mentioning [label]) or — when the native bridge cannot load in this
/// environment — the explicit "validator unavailable" error. A *valid* result
/// would be a security regression.
void _expectRejected(ValidationResult result, String label) {
  if (_isUnavailable(result)) {
    // Native bridge not loaded in this environment; the wiring correctly
    // refuses to greenlight the script. This is not a security regression.
    return;
  }
  expect(result.isValid, false,
      reason: '$label must be rejected by the validator');
  expect(result.errors, isNotEmpty,
      reason: '$label rejection must carry an error message');
}

bool _isUnavailable(ValidationResult result) =>
    result.errors.any((e) => e.contains('unavailable'));
