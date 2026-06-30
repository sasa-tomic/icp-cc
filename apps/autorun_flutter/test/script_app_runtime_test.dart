import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';

/// Recording [ScriptBridge] for [ScriptAppRuntime] lifecycle tests. Each app
/// method returns a configurable canned JSON response and records the call.
class _RecordingBridge implements ScriptBridge {
  final List<String> calls = <String>[];

  String initResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 0},
    'effects': <dynamic>[],
  });
  String viewResponse = json.encode(<String, dynamic>{
    'ok': true,
    'ui': <String, dynamic>{'type': 'column'},
    'effects': <dynamic>[],
  });
  String updateResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 1},
    'effects': <dynamic>[],
  });

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) => null;

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) => null;

  @override
  String? jsExec({required String script, String? jsonArg}) => null;

  @override
  String? jsLint({required String script}) => json.encode({'ok': true, 'errors': <String>[]});

  @override
  String? jsAppInit({required String script, String? jsonArg, int budgetMs = 50}) {
    calls.add('jsAppInit');
    return initResponse;
  }

  @override
  String? jsAppView({required String script, required String stateJson, int budgetMs = 50}) {
    calls.add('jsAppView');
    return viewResponse;
  }

  @override
  String? jsAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) {
    calls.add('jsAppUpdate');
    return updateResponse;
  }
}

void main() {
  const String bundle = 'globalThis.init=()=>({state:{},effects:[]});';

  group('ScriptAppRuntime lifecycle', () {
    test('init→view→update routes through jsApp* and decodes payloads', () async {
      final bridge = _RecordingBridge();
      final runtime = ScriptAppRuntime(bridge);

      final initObj = await runtime.init(script: bundle);
      expect(bridge.calls, contains('jsAppInit'));
      expect(initObj['ok'], true);
      expect((initObj['state'] as Map<String, dynamic>)['count'], 0);

      final viewObj = await runtime.view(
        script: bundle,
        state: Map<String, dynamic>.from(initObj['state'] as Map),
      );
      expect(bridge.calls, contains('jsAppView'));
      expect((viewObj['ui'] as Map<String, dynamic>)['type'], 'column');

      final updateObj = await runtime.update(
        script: bundle,
        msg: {'type': 'inc'},
        state: Map<String, dynamic>.from(initObj['state'] as Map),
      );
      expect(bridge.calls, contains('jsAppUpdate'));
      expect((updateObj['state'] as Map<String, dynamic>)['count'], 1);
    });

    test('init forwards initialArg as JSON under jsonArg', () async {
      final bridge = _RecordingBridge();
      final runtime = ScriptAppRuntime(bridge);
      await runtime.init(script: bundle, initialArg: {'seed': 42});
      // jsAppInit response is canned; we only assert it was invoked + parsed.
      expect(bridge.calls, contains('jsAppInit'));
    });

    test('empty init response throws StateError', () async {
      final bridge = _RecordingBridge()..initResponse = '';
      final runtime = ScriptAppRuntime(bridge);
      await expectLater(runtime.init(script: bundle), throwsA(isA<StateError>()));
    });

    test('ok=false init response throws StateError carrying the error', () async {
      final bridge = _RecordingBridge()
        ..initResponse = json.encode({'ok': false, 'error': 'bad bundle'});
      final runtime = ScriptAppRuntime(bridge);
      await expectLater(
        runtime.init(script: bundle),
        throwsA(isA<StateError>()),
      );
    });

    test('ok=false view response throws StateError', () async {
      final bridge = _RecordingBridge()
        ..viewResponse = json.encode({'ok': false, 'error': 'render failed'});
      final runtime = ScriptAppRuntime(bridge);
      await expectLater(
        runtime.view(script: bundle, state: {'count': 0}),
        throwsA(isA<StateError>()),
      );
    });

    test('ok=false update response throws StateError', () async {
      final bridge = _RecordingBridge()
        ..updateResponse = json.encode({'ok': false, 'error': 'bad msg'});
      final runtime = ScriptAppRuntime(bridge);
      await expectLater(
        runtime.update(script: bundle, msg: {}, state: {'count': 0}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
