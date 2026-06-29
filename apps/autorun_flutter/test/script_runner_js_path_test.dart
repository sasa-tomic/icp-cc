import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';

/// Recording bridge: records which methods were called and with what args.
/// lua* methods return null/empty (the lua path isn't the focus here);
/// js* methods return canned JSON so the runtime can decode it.
class _RecordingBridge implements ScriptBridge {
  final List<String> calls = <String>[];
  String? lastExecScript;
  String? lastExecJsonArg;

  String jsExecResponse =
      json.encode(<String, dynamic>{'ok': true, 'result': 'js-ran'});
  String jsAppInitResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 0},
    'effects': <dynamic>[],
  });
  String jsAppViewResponse = json.encode(<String, dynamic>{
    'ok': true,
    'ui': <String, dynamic>{'type': 'text'},
    'effects': <dynamic>[],
  });
  String jsAppUpdateResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 1},
    'effects': <dynamic>[],
  });

  String luaExecResponse =
      json.encode(<String, dynamic>{'ok': true, 'result': 'lua-ran'});
  String luaAppInitResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 0},
    'effects': <dynamic>[],
  });
  String luaAppViewResponse = json.encode(<String, dynamic>{
    'ok': true,
    'ui': <String, dynamic>{'type': 'text'},
    'effects': <dynamic>[],
  });
  String luaAppUpdateResponse = json.encode(<String, dynamic>{
    'ok': true,
    'state': <String, dynamic>{'count': 1},
    'effects': <dynamic>[],
  });

  @override
  String? callAnonymous(
      {required String canisterId,
      required String method,
      required int kind,
      String args = '()',
      String? host}) {
    calls.add('callAnonymous');
    return null;
  }

  @override
  String? callAuthenticated(
      {required String canisterId,
      required String method,
      required int kind,
      required String privateKeyB64,
      String args = '()',
      String? host}) {
    calls.add('callAuthenticated');
    return null;
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    calls.add('luaExec');
    lastExecScript = script;
    lastExecJsonArg = jsonArg;
    return luaExecResponse;
  }

  @override
  String? luaLint({required String script}) {
    calls.add('luaLint');
    return json.encode(<String, dynamic>{'ok': true, 'errors': <dynamic>[]});
  }

  @override
  String? luaAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    calls.add('luaAppInit');
    return luaAppInitResponse;
  }

  @override
  String? luaAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    calls.add('luaAppView');
    return luaAppViewResponse;
  }

  @override
  String? luaAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    calls.add('luaAppUpdate');
    return luaAppUpdateResponse;
  }

  @override
  String? jsExec({required String script, String? jsonArg}) {
    calls.add('jsExec');
    lastExecScript = script;
    lastExecJsonArg = jsonArg;
    return jsExecResponse;
  }

  @override
  String? jsLint({required String script}) {
    calls.add('jsLint');
    return json.encode(<String, dynamic>{'ok': true, 'errors': <dynamic>[]});
  }

  @override
  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    calls.add('jsAppInit');
    return jsAppInitResponse;
  }

  @override
  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    calls.add('jsAppView');
    return jsAppViewResponse;
  }

  @override
  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    calls.add('jsAppUpdate');
    return jsAppUpdateResponse;
  }
}

void main() {
  group('ScriptRunner language routing', () {
    test('typescript routes to jsExec and skips helper injection', () async {
      final bridge = _RecordingBridge();
      const bundle = 'globalThis.init=()=>({state:{},effects:[]});';
      final runner = ScriptRunner(bridge);
      final res = await runner
          .run(ScriptRunPlan(luaSource: bundle, language: ScriptLanguage.typescript));

      expect(res.ok, true);
      expect(bridge.calls, contains('jsExec'));
      expect(bridge.calls.any((c) => c == 'luaExec'), isFalse);
      // The script passed to jsExec must be the RAW bundle, not helper-injected.
      expect(bridge.lastExecScript, bundle);
      expect(bridge.lastExecScript, isNot(contains('function icp_call')));
    });

    test('default language (lua) still routes to luaExec (back-compat)',
        () async {
      final bridge = _RecordingBridge();
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(luaSource: 'return 1'));

      expect(res.ok, true);
      expect(bridge.calls, contains('luaExec'));
      expect(bridge.calls.any((c) => c == 'jsExec'), isFalse);
      // Lua path still injects helpers.
      expect(bridge.lastExecScript, contains('function icp_call'));
    });
  });

  group('ScriptAppRuntime language routing', () {
    test('typescript routes init/view/update to js* methods', () async {
      final bridge = _RecordingBridge();
      final runtime =
          ScriptAppRuntime(bridge, language: ScriptLanguage.typescript);

      final initRes = await runtime.init(script: 'bundle');
      expect(bridge.calls, contains('jsAppInit'));
      expect(bridge.calls.any((c) => c == 'luaAppInit'), isFalse);
      expect(initRes['ok'], true);

      await runtime.view(script: 'bundle', state: <String, dynamic>{'count': 0});
      expect(bridge.calls, contains('jsAppView'));

      await runtime.update(
          script: 'bundle',
          msg: <String, dynamic>{'type': 'inc'},
          state: <String, dynamic>{'count': 0});
      expect(bridge.calls, contains('jsAppUpdate'));
    });

    test('default language (lua) still routes init to luaAppInit (back-compat)',
        () async {
      final bridge = _RecordingBridge();
      final runtime = ScriptAppRuntime(bridge);

      final initRes = await runtime.init(script: 'bundle');
      expect(bridge.calls, contains('luaAppInit'));
      expect(bridge.calls.any((c) => c == 'jsAppInit'), isFalse);
      expect(initRes['ok'], true);
    });
  });
}
