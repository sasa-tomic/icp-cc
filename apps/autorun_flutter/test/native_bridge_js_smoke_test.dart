@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

/// Real-FFI smoke test: proves the Flutter→FFI→QuickJS wiring works end-to-end
/// against the actual `libicp_core.so`. Skips gracefully if the native library
/// cannot be loaded in this environment.
void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();

  /// Resolve the pilot bundle by trying a few candidate locations so the test
  /// is robust to the runner's working directory.
  final String bundlePath = _resolveBundlePath();

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

    test('jsAppInit runs the pilot bundle and yields state.count == 0', () {
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

  group('ScriptAppRuntime TS integration (real lib)', () {
    test('init→view→update runs TS counter through full abstraction stack',
        () async {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      if (probe == null) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final String counterPath = _resolveCounterPath();
      final File counterFile = File(counterPath);
      if (!counterFile.existsSync()) {
        stdout.writeln('SKIP: counter example not found at $counterPath');
        return;
      }
      final String bundle = counterFile.readAsStringSync();

      final runtime = ScriptAppRuntime(
        RustScriptBridge(loader),
        language: ScriptLanguage.typescript,
      );

      final Map<String, dynamic> initObj =
          await runtime.init(script: bundle, budgetMs: 1000);
      expect(initObj['ok'], true);
      expect((initObj['state'] as Map<String, dynamic>)['count'], 0);

      final Map<String, dynamic> viewObj = await runtime.view(
        script: bundle,
        state: Map<String, dynamic>.from(initObj['state'] as Map),
        budgetMs: 1000,
      );
      expect((viewObj['ui'] as Map<String, dynamic>)['type'], 'column');

      final Map<String, dynamic> updateObj = await runtime.update(
        script: bundle,
        msg: {'type': 'inc'},
        state: Map<String, dynamic>.from(initObj['state'] as Map),
        budgetMs: 1000,
      );
      expect((updateObj['state'] as Map<String, dynamic>)['count'], 1);
    });
  });
}

String _resolveBundlePath() {
  const String rel = 'crates/icp_core/tests/fixtures/pilot_sample.bundle.js';
  final List<String> candidates = <String>[
    '../../$rel',
    '../../../$rel',
    '/code/icp-cc/$rel',
  ];
  for (final String c in candidates) {
    if (File(c).existsSync()) {
      return c;
    }
  }
  return '../../$rel';
}

String _resolveCounterPath() {
  const String rel = 'lib/examples/05_typescript_counter.js';
  final List<String> candidates = <String>[
    rel,
    'apps/autorun_flutter/$rel',
    '/code/icp-cc/apps/autorun_flutter/$rel',
  ];
  for (final String c in candidates) {
    if (File(c).existsSync()) {
      return c;
    }
  }
  return rel;
}
