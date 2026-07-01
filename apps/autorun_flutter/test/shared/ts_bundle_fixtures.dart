library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

const List<String> _pilotBundleCandidates = <String>[
  'test/assets/pilot_sample.bundle.js',
  'apps/autorun_flutter/test/assets/pilot_sample.bundle.js',
  '../../crates/icp_core/tests/fixtures/pilot_sample.bundle.js',
  '/code/icp-cc/apps/autorun_flutter/test/assets/pilot_sample.bundle.js',
  '/code/icp-cc/crates/icp_core/tests/fixtures/pilot_sample.bundle.js',
];

String loadPilotBundle() {
  for (final String path in _pilotBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('pilot_sample.bundle.js not found in any candidate location:\n'
      '${_pilotBundleCandidates.join("\n")}');
}

bool nativeLibAvailable(RustBridgeLoader loader) {
  final String? probe = loader.jsExec(script: '1', jsonArg: null);
  return probe != null;
}

ScriptAppRuntime bootRuntime() {
  return ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
}
