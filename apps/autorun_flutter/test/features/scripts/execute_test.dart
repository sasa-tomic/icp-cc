import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/models/profile_keypair.dart';

import '../../test_helpers/test_keypair_factory.dart';

class _FakeScriptBridge implements ScriptBridge {
  _FakeScriptBridge();

  final List<Map<String, dynamic>> callLog = [];
  String? luaExecResponse;
  String? lastLuaScript;
  String? lastJsonArg;

  void setLuaExecResponse(Map<String, dynamic> response) {
    luaExecResponse = json.encode(response);
  }

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) {
    callLog.add({
      'type': 'anonymous',
      'canisterId': canisterId,
      'method': method,
      'kind': kind,
      'args': args,
      'host': host,
    });
    return json.encode({'result': 'ok'});
  }

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int kind,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
    callLog.add({
      'type': 'authenticated',
      'canisterId': canisterId,
      'method': method,
      'kind': kind,
      'privateKeyB64': privateKeyB64,
      'args': args,
      'host': host,
    });
    return json.encode({'result': 'authenticated'});
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    lastLuaScript = script;
    lastJsonArg = jsonArg;
    return luaExecResponse ?? json.encode({'ok': true, 'result': null});
  }

  @override
  String? luaLint({required String script}) {
    return json.encode({'ok': true, 'errors': []});
  }

  @override
  String? luaAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    return null;
  }

  @override
  String? luaAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    return null;
  }

  @override
  String? luaAppUpdate({
    required String script,
    required String msgJson,
    required String stateJson,
    int budgetMs = 50,
  }) {
    return null;
  }

  @override
  String? jsExec({required String script, String? jsonArg}) {
    return null;
  }

  @override
  String? jsLint({required String script}) {
    return null;
  }

  @override
  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    return null;
  }

  @override
  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    return null;
  }

  @override
  String? jsAppUpdate({
    required String script,
    required String msgJson,
    required String stateJson,
    int budgetMs = 50,
  }) {
    return null;
  }
}

void main() {
  late ScriptRunner runner;
  late _FakeScriptBridge bridge;
  late ProfileKeypair testKeypair;

  setUpAll(() async {
    testKeypair = await TestKeypairFactory.getEd25519Keypair();
  });

  setUp(() {
    bridge = _FakeScriptBridge();
    runner = ScriptRunner(bridge);
  });

  group('execute lua script', () {
    test('script can return simple message via icp_message helper', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {'action': 'message', 'text': 'Hello World'}
      });

      final plan = ScriptRunPlan(
        luaSource: 'return icp_message("Hello World")',
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(result.result, isA<Map>());
      expect(result.result['action'], equals('message'));
      expect(result.result['text'], equals('Hello World'));
    });

    test('script can return list items via icp_ui_list helper', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'list',
            'items': [
              {'title': 'Item 1'},
              {'title': 'Item 2'},
              {'title': 'Item 3'},
            ]
          }
        }
      });

      final plan = ScriptRunPlan(
        luaSource:
            'return icp_ui_list({ items = { { title = "Item 1" }, { title = "Item 2" }, { title = "Item 3" } } })',
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(result.result['action'], equals('ui'));
      expect(result.result['ui']['type'], equals('list'));
      expect(result.result['ui']['items'], hasLength(3));
    });

    test('script handles lua syntax errors gracefully', () async {
      bridge.setLuaExecResponse(
          {'ok': false, 'error': 'syntax error near line 1'});

      final plan = ScriptRunPlan(
        luaSource: 'function init(arg) return { -- missing closing brace end',
      );

      final result = await runner.run(plan);

      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
      expect(result.error, contains('syntax'));
    });

    test('script can make ICP call effect via icp_call helper', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {
          'action': 'call',
          'canister_id': 'aaaaa-aa',
          'method': 'greet',
          'kind': 0,
          'args': '()',
        }
      });

      final plan = ScriptRunPlan(
        luaSource:
            'return icp_call({ canister_id = "aaaaa-aa", method = "greet", kind = 0 })',
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(result.result, isNotNull);
    });

    test('empty lua source returns error', () async {
      final plan = ScriptRunPlan(
        luaSource: '',
      );

      final result = await runner.run(plan);

      expect(result.ok, isFalse);
      expect(result.error, contains('empty'));
    });

    test('lua source with only whitespace returns error', () async {
      final plan = ScriptRunPlan(
        luaSource: '   ',
      );

      final result = await runner.run(plan);

      expect(result.ok, isFalse);
      expect(result.error, contains('empty'));
    });
  });

  group('script with canister calls', () {
    test('plan with calls executes anonymous call by default', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': 42});

      final plan = ScriptRunPlan(
        luaSource: 'return arg.calls.test.result',
        calls: [
          CanisterCallSpec(
            label: 'test',
            canisterId: 'test-canister',
            method: 'testMethod',
            kind: 0,
          ),
        ],
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'anonymous');
    });

    test('plan with keypair executes authenticated call', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': 42});

      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test',
            canisterId: 'test-canister',
            method: 'testMethod',
            kind: 1,
            privateKeyB64: testKeypair.privateKey,
          ),
        ],
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'authenticated');
      expect(bridge.callLog.first['privateKeyB64'], testKeypair.privateKey);
    });
  });

  group('script with initial arg', () {
    test('initialArg is passed to lua under arg.input', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': 'received'});

      final plan = ScriptRunPlan(
        luaSource: 'return arg.input.message',
        initialArg: {'message': 'Hello'},
      );

      final result = await runner.run(plan);

      expect(result.ok, isTrue);
      expect(bridge.lastJsonArg, isNotNull);
      final arg = json.decode(bridge.lastJsonArg!) as Map<String, dynamic>;
      expect(arg['input'], isNotNull);
      expect(arg['input']['message'], equals('Hello'));
    });
  });

  group('lua helper injection', () {
    test('icp_message helper is injected', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {'action': 'message', 'text': 'test'}
      });

      final plan = ScriptRunPlan(luaSource: 'return icp_message("test")');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_message'));
    });

    test('icp_call helper is injected', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {'action': 'call'}
      });

      final plan = ScriptRunPlan(luaSource: 'return icp_call({})');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_call'));
    });

    test('icp_batch helper is injected', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {'action': 'batch', 'calls': []}
      });

      final plan = ScriptRunPlan(luaSource: 'return icp_batch({})');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_batch'));
    });

    test('icp_ui_list helper is injected', () async {
      bridge.setLuaExecResponse({
        'ok': true,
        'result': {'action': 'ui'}
      });

      final plan = ScriptRunPlan(luaSource: 'return icp_ui_list({})');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_ui_list'));
    });

    test('icp_format_icp helper is injected', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': '1.0 ICP'});

      final plan = ScriptRunPlan(luaSource: 'return icp_format_icp(100000000)');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_format_icp'));
    });

    test('icp_filter_items helper is injected', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': []});

      final plan = ScriptRunPlan(
          luaSource: 'return icp_filter_items({}, "field", "value")');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_filter_items'));
    });

    test('icp_sort_items helper is injected', () async {
      bridge.setLuaExecResponse({'ok': true, 'result': []});

      final plan =
          ScriptRunPlan(luaSource: 'return icp_sort_items({}, "field", true)');
      await runner.run(plan);

      expect(bridge.lastLuaScript, contains('function icp_sort_items'));
    });
  });
}
