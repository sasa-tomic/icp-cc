@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/services/script_validation_service.dart';

import 'shared/ts_bundle_fixtures.dart';

void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();
  final String pilotBundle = loadPilotBundle();

  const String kMinimalBundle = '''
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

  const String kMalformedBundle = 'function {{{ broken';

  group('native QuickJS FFI (real lib)', () {
    test('jsExec evaluates a JS expression and returns ok JSON', () {
      final String? out = loader.jsExec(script: '1 + 2', jsonArg: null);
      if (out == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      expect(obj['ok'], true);
      expect(obj['result'], 3);
    });

    test('jsExec returns ok:false for a script that throws', () {
      final String? out = loader.jsExec(
          script: 'throw new Error("boom")', jsonArg: null);
      if (out == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      expect(obj['ok'], false);
      expect(obj['error'], 'js error: JavaScript exception',
          reason: 'rquickjs surfaces a thrown JS value as a generic exception');
    });

    test('jsLint flags a script missing the init/view/update contract', () {
      final String? out = loader.jsLint(script: 'var x = 1;');
      if (out == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      expect(obj['ok'], false);
      final errors = (obj['errors'] as List)
          .map((e) => (e as Map<String, dynamic>)['message'] as String)
          .toList();
      expect(errors.any((e) => e.contains('init')), true);
      expect(errors.any((e) => e.contains('view')), true);
      expect(errors.any((e) => e.contains('update')), true);
    });

    test('jsLint accepts a bundle exposing the init/view/update contract', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.jsLint(script: pilotBundle);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], true,
          reason: 'pilot bundle must satisfy the lint contract');
    });

    test('validateJsComprehensive accepts a valid TS bundle', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.validateJsComprehensive(
        script: kMinimalBundle,
        isExample: false,
        isTest: false,
        isProduction: false,
      );
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['is_valid'], true,
          reason: 'minimal TS bundle must pass comprehensive validation');
      expect(obj['line_count'], greaterThan(0));
      expect(obj['character_count'], greaterThan(0));
    });

    test('validateJsComprehensive rejects a sandbox escape (eval)', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.validateJsComprehensive(
        script:
            "globalThis.init = () => ({ state: {}, effects: [] }); eval('1+1');",
        isExample: false,
        isTest: false,
        isProduction: true,
      );
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['is_valid'], false, reason: 'eval must be rejected');
      final List<String> errors =
          (obj['syntax_errors'] as List<dynamic>).cast<String>();
      expect(
          errors.any((e) => e.contains('eval() detected')), true,
          reason: 'error must name eval as the forbidden primitive');
    });

    test('validateJsComprehensive rejects Intl.* (no ICU in runtime)', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.validateJsComprehensive(
        script:
            'function init(){return{state:{},effects:[]};} new Intl.NumberFormat("de").format(1);',
        isExample: false,
        isTest: false,
        isProduction: true,
      );
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['is_valid'], false, reason: 'Intl.* must be rejected');
      final List<String> errors =
          (obj['syntax_errors'] as List<dynamic>).cast<String>();
      expect(errors.any((e) => e.contains('Intl')), true);
    });

    test('jsAppInit runs the pilot bundle and yields the initial state', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.jsAppInit(
          script: pilotBundle, jsonArg: null, budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], true);
      final Map<String, dynamic> state =
          obj['state'] as Map<String, dynamic>;
      expect(state['count'], 0);
    });

    test('jsAppInit returns ok:false for a malformed bundle', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.jsAppInit(
          script: kMalformedBundle, jsonArg: null, budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], false);
      expect(obj['error'] as String, isNotEmpty);
    });

    test('jsAppView renders the pilot state into a column UI tree', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String state = json.encode({
        'count': 7,
        'items': <dynamic>[],
        'last': null,
        'name': '',
        'email': '',
        'enabled': true,
        'role': 'user',
        'showImage': false,
      });
      final String? out = loader.jsAppView(
          script: pilotBundle, stateJson: state, budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], true);
      expect((obj['ui'] as Map<String, dynamic>)['type'], 'column');
    });

    test('jsAppView returns ok:false for a malformed bundle', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.jsAppView(
          script: kMalformedBundle,
          stateJson: '{"count":0}',
          budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], false);
      expect(obj['error'] as String, isNotEmpty);
    });

    test('jsAppUpdate applies an inc message and bumps state.count', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String state = json.encode({'count': 41, 'items': <dynamic>[]});
      final String? out = loader.jsAppUpdate(
          script: pilotBundle,
          msgJson: '{"type":"inc"}',
          stateJson: state,
          budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], true);
      expect((obj['state'] as Map<String, dynamic>)['count'], 42);
    });

    test('jsAppUpdate returns ok:false for a malformed bundle', () {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.jsAppUpdate(
          script: kMalformedBundle,
          msgJson: '{"type":"inc"}',
          stateJson: '{"count":0}',
          budgetMs: 1000);
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['ok'], false);
      expect(obj['error'] as String, isNotEmpty);
    });
  });

  group('ScriptAppRuntime TS lifecycle (real lib)', () {
    test('init→view→update runs the pilot bundle through the abstraction stack',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }

      final runtime = ScriptAppRuntime(RustScriptBridge(loader));

      final Map<String, dynamic> initObj =
          await runtime.init(script: pilotBundle, budgetMs: 1000);
      expect(initObj['ok'], true);
      final Map<String, dynamic> initState =
          Map<String, dynamic>.from(initObj['state'] as Map);
      expect(initState['count'], 0);

      final Map<String, dynamic> viewObj = await runtime.view(
        script: pilotBundle,
        state: initState,
        budgetMs: 1000,
      );
      expect((viewObj['ui'] as Map<String, dynamic>)['type'], 'column');

      final Map<String, dynamic> updateObj = await runtime.update(
        script: pilotBundle,
        msg: {'type': 'inc'},
        state: initState,
        budgetMs: 1000,
      );
      expect((updateObj['state'] as Map<String, dynamic>)['count'], 1);
    });

    test('update emits an icp_batch effect for load_sample', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }

      final runtime = ScriptAppRuntime(RustScriptBridge(loader));
      final Map<String, dynamic> initObj =
          await runtime.init(script: pilotBundle, budgetMs: 1000);
      final Map<String, dynamic> initState =
          Map<String, dynamic>.from(initObj['state'] as Map);

      final Map<String, dynamic> updateObj = await runtime.update(
        script: pilotBundle,
        msg: {'type': 'load_sample'},
        state: initState,
        budgetMs: 1000,
      );

      final effects = updateObj['effects'] as List<dynamic>;
      expect(effects, isNotEmpty);
      final effect = effects.first as Map<String, dynamic>;
      expect(effect['kind'], 'icp_batch');
      expect(effect['id'], 'load');
      final items = effect['items'] as List<dynamic>;
      expect(items, hasLength(2));
    });

    test('ScriptRunner.run executes the pilot bundle via jsExec', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }

      final wrapped =
          '$pilotBundle\nJSON.stringify({ ok: true, result: { ran: true } });';
      final runner = ScriptRunner(RustScriptBridge(loader));
      final res = await runner.run(ScriptRunPlan(bundle: wrapped));
      expect(res.ok, true);
    });
  });

  group('ScriptValidationService over FFI (real lib)', () {
    test('validates the pilot bundle as a contract guard', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final result = await ScriptValidationService().validateScript(pilotBundle);
      expect(result.isValid, true,
          reason: 'pilot bundle must pass the authoritative validator');
      expect(result.errors, isEmpty);
    });
  });
}
