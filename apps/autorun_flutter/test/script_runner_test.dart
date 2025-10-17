import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';

class _FakeBridge implements ScriptBridge {
  _FakeBridge({required this.responses});
  final Map<String, String> responses;

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    return responses['$canisterId::$method'];
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) {
    return responses['$canisterId::$method'];
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    // Echo sum of two call outputs if present
    final Map<String, dynamic> arg = json.decode(jsonArg!) as Map<String, dynamic>;
    final calls = arg['calls'] as Map<String, dynamic>;
    final a = (calls['a'] as Map<String, dynamic>)['value'] as int;
    final b = (calls['b'] as Map<String, dynamic>)['value'] as int;
    final result = a + b;
    return json.encode({'ok': true, 'result': result});
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
  test('ScriptRunner aggregates canister outputs and executes Lua', () async {
    final bridge = _FakeBridge(responses: {
      'cid1::m1': json.encode({'value': 2}),
      'cid2::m2': json.encode({'value': 3}),
    });
    final runner = ScriptRunner(bridge);
    final plan = ScriptRunPlan(
      luaSource: 'return 0',
      calls: [
        CanisterCallSpec(label: 'a', canisterId: 'cid1', method: 'm1', kind: 0, argsJson: '()'),
        CanisterCallSpec(label: 'b', canisterId: 'cid2', method: 'm2', kind: 0, argsJson: '()'),
      ],
    );

    final res = await runner.run(plan);
    expect(res.ok, true);
    expect(res.result, 5);
  });
}
