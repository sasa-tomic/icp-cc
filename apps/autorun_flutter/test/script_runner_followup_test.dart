import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';

class _FakeBridge2 implements ScriptBridge {
  _FakeBridge2();

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    return json.encode({'ok': true, 'echo': {'cid': canisterId, 'm': method, 'args': args}});
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) {
    return json.encode({'ok': true, 'auth': true});
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    // Script returns an icp_call spec
    final Map<String, dynamic> arg = json.decode(jsonArg!) as Map<String, dynamic>;
    expect(arg.containsKey('calls'), true);
    // Return call spec
    return json.encode({
      'ok': true,
      'result': {
        'action': 'call',
        'canister_id': 'abc',
        'method': 'go',
        'kind': 0,
        'args': json.encode({'x': 1}),
      }
    });
  }

  @override
  String? luaLint({required String script}) {
    return json.encode({'ok': true, 'errors': []});
  }

  @override
  String? luaAppInit({required String script, String? jsonArg, int budgetMs = 50}) => null;

  @override
  String? luaAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) => null;

  @override
  String? luaAppView({required String script, required String stateJson, int budgetMs = 50}) => null;
}

void main() {
  test('ScriptRunner respects icp_call follow-up action', () async {
    final runner = ScriptRunner(_FakeBridge2());
    final plan = ScriptRunPlan(luaSource: 'return icp_call({ canister_id = "abc", method = "go" })');
    final res = await runner.run(plan);
    expect(res.ok, true);
    expect((res.result as Map<String, dynamic>)['ok'], true);
  });
}
