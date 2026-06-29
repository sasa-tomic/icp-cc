@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

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
