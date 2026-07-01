@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_validation_service.dart';

import '../../shared/ts_bundle_fixtures.dart';

const String _shellPrefix = '''
"use strict";
(() => {
  function init() { return { state: { count: 0 }, effects: [] }; }
  function view(state) { return { type: "text", props: { text: String(state.count) } }; }
  function update(msg, state) { return { state, effects: [] }; }
  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
''';

const String _shellSuffix = '''
})();
''';

String bundleWith(String forbiddenFragment) =>
    '$_shellPrefix$forbiddenFragment$_shellSuffix';

void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();
  final String pilotBundle = loadPilotBundle();

  group('ScriptValidationService — POSITIVE guard', () {
    test('the pilot bundle passes the authoritative validator', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final result = await ScriptValidationService().validateScript(pilotBundle);
      expect(result.isValid, true,
          reason: 'pilot bundle must be accepted by the Rust validator');
      expect(result.errors, isEmpty);
    });
  });

  group('ScriptValidationService — forbidden primitives rejected', () {
    void expectRejectedWithError(String source, String needle, String label) {
      test('$label is rejected with a specific error message', () async {
        if (!nativeLibAvailable(loader)) {
          stdout.writeln(
              'SKIP: libicp_core.so did not load in this environment');
          return;
        }
        final result = await ScriptValidationService().validateScript(source);
        expect(result.isValid, false, reason: '$label must be rejected');
        expect(
          result.errors.any((e) => e.contains(needle)),
          isTrue,
          reason: '$label rejection must mention: "$needle" '
              '(got errors: ${result.errors})',
        );
      });
    }

    expectRejectedWithError(
      bundleWith('eval("1+1");'),
      'eval() detected - dynamic code execution not allowed',
      'eval()',
    );

    expectRejectedWithError(
      bundleWith('var f = new Function("return 1");'),
      'Function() constructor detected - dynamic code execution not allowed',
      'new Function()',
    );

    expectRejectedWithError(
      bundleWith('return import("./missing");'),
      'dynamic import() not allowed',
      'dynamic import()',
    );

    expectRejectedWithError(
      bundleWith('require("fs");'),
      'require() - module loading not allowed',
      'require()',
    );

    expectRejectedWithError(
      bundleWith('return process.arch;'),
      'process access not allowed',
      'process.* access',
    );

    expectRejectedWithError(
      bundleWith('return new Intl.NumberFormat("de").format(1);'),
      'Intl.* is not allowed',
      'Intl.* access',
    );

    expectRejectedWithError(
      bundleWith('return globalThis["eval"];'),
      'globalThis property access by key not allowed',
      'globalThis[] keyed access',
    );
  });
}
