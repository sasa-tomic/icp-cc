@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

/// Real-FFI smoke test: proves the Flutter→FFI→QuickJS wiring works end-to-end
/// against the actual `libicp_core.so`. Covers every public JS entry point
/// (`jsExec`, `jsLint`, `validateJsComprehensive`, `jsAppInit/View/Update`) and
/// the full TS app lifecycle (init→view→update + effects roundtrip) through the
/// real engine. Skips gracefully (without failing) only when the native library
/// cannot be loaded in this environment — every assertion below is real when it
/// can.
void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();

  /// Minimal valid TS bundle that the comprehensive validator accepts (exposes
  /// init/view/update on globalThis; no blocked primitives).
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

  /// Resolve the pilot bundle (the canonical TS bundle fixture) by trying a few
  /// candidate locations so the test is robust to the runner's working dir.
  final String bundlePath = _resolveAssetPath(
    'test/assets/pilot_sample.bundle.js',
    repoRelative: 'apps/autorun_flutter/test/assets/pilot_sample.bundle.js',
  );

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

    test('jsLint flags a script missing the init/view/update contract', () {
      final String? out = loader.jsLint(script: 'var x = 1;');
      if (out == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      // jsLint enforces the TS app contract: init/view/update must be present.
      expect(obj['ok'], false);
      final errors = (obj['errors'] as List)
          .map((e) => (e as Map<String, dynamic>)['message'] as String)
          .toList();
      expect(errors.any((e) => e.contains('init')), true);
      expect(errors.any((e) => e.contains('view')), true);
      expect(errors.any((e) => e.contains('update')), true);
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
    });

    test('validateJsComprehensive rejects a sandbox escape (eval)', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String? out = loader.validateJsComprehensive(
        script: "globalThis.init = () => ({ state: {}, effects: [] }); eval('1+1');",
        isExample: false,
        isTest: false,
        isProduction: true,
      );
      expect(out, isNotNull);
      final Map<String, dynamic> obj =
          json.decode(out!) as Map<String, dynamic>;
      expect(obj['is_valid'], false, reason: 'eval must be rejected');
    });

    test('jsAppInit runs the pilot bundle and yields the initial state', () {
      final File bundleFile = File(bundlePath);
      if (!bundleFile.existsSync()) {
        stdout.writeln('SKIP: pilot bundle not found at $bundlePath');
        return;
      }
      final String bundle = bundleFile.readAsStringSync();
      final String? out = loader.jsAppInit(
          script: bundle, jsonArg: null, budgetMs: 1000);
      if (out == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      expect(obj['ok'], true);
      final Map<String, dynamic> state =
          obj['state'] as Map<String, dynamic>;
      expect(state['count'], 0);
    });
  });

  group('ScriptAppRuntime TS lifecycle (real lib)', () {
    test('init→view→update runs the pilot bundle through the abstraction stack',
        () async {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final File bundleFile = File(bundlePath);
      if (!bundleFile.existsSync()) {
        stdout.writeln('SKIP: pilot bundle not found at $bundlePath');
        return;
      }
      final String bundle = bundleFile.readAsStringSync();

      final runtime = ScriptAppRuntime(RustScriptBridge(loader));

      // init → state.count == 0
      final Map<String, dynamic> initObj =
          await runtime.init(script: bundle, budgetMs: 1000);
      expect(initObj['ok'], true);
      final Map<String, dynamic> initState =
          Map<String, dynamic>.from(initObj['state'] as Map);
      expect(initState['count'], 0);

      // view → a column UI tree
      final Map<String, dynamic> viewObj = await runtime.view(
        script: bundle,
        state: initState,
        budgetMs: 1000,
      );
      expect((viewObj['ui'] as Map<String, dynamic>)['type'], 'column');

      // update(inc) → state.count == 1
      final Map<String, dynamic> updateObj = await runtime.update(
        script: bundle,
        msg: {'type': 'inc'},
        state: initState,
        budgetMs: 1000,
      );
      expect((updateObj['state'] as Map<String, dynamic>)['count'], 1);
    });

    test('update emits an icp_batch effect for load_sample', () async {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final File bundleFile = File(bundlePath);
      if (!bundleFile.existsSync()) {
        stdout.writeln('SKIP: pilot bundle not found at $bundlePath');
        return;
      }
      final String bundle = bundleFile.readAsStringSync();

      final runtime = ScriptAppRuntime(RustScriptBridge(loader));
      final Map<String, dynamic> initObj =
          await runtime.init(script: bundle, budgetMs: 1000);
      final Map<String, dynamic> initState =
          Map<String, dynamic>.from(initObj['state'] as Map);

      final Map<String, dynamic> updateObj = await runtime.update(
        script: bundle,
        msg: {'type': 'load_sample'},
        state: initState,
        budgetMs: 1000,
      );

      // The pilot bundle requests a batch of two canister queries for load_sample.
      final effects = updateObj['effects'] as List<dynamic>;
      expect(effects, isNotEmpty);
      final effect = effects.first as Map<String, dynamic>;
      expect(effect['kind'], 'icp_batch');
      expect(effect['id'], 'load');
      final items = effect['items'] as List<dynamic>;
      expect(items, hasLength(2));
    });

    test('ScriptRunner.run executes the pilot bundle via jsExec', () async {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final File bundleFile = File(bundlePath);
      if (!bundleFile.existsSync()) {
        stdout.writeln('SKIP: pilot bundle not found at $bundlePath');
        return;
      }
      final String bundle = bundleFile.readAsStringSync();

      // jsExec runs the whole IIFE; the bundle calls register() which returns
      // nothing, so wrap it so the bundle yields a JSON value the runner decodes.
      final wrapped =
          '$bundle\nJSON.stringify({ ok: true, result: { ran: true } });';
      final runner = ScriptRunner(RustScriptBridge(loader));
      final res = await runner.run(ScriptRunPlan(bundle: wrapped));
      expect(res.ok, true);
    });
  });
}

/// Resolve an asset path by trying a few candidate locations relative to the
/// repo root so the test is robust to the runner's working directory.
String _resolveAssetPath(String appRelative, {required String repoRelative}) {
  final List<String> candidates = <String>[
    appRelative,
    repoRelative,
    '/code/icp-cc/$repoRelative',
  ];
  for (final String c in candidates) {
    if (File(c).existsSync()) {
      return c;
    }
  }
  return appRelative;
}
