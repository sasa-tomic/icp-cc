import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';

import 'shared/fake_secure_keypair_repository.dart';
import 'shared/test_keypair_factory.dart';

/// Minimal in-memory [ScriptBridge] for [ScriptRunner] tests. The canister
/// methods return canned JSON keyed by `canisterId::method`; [jsExec] defaults
/// to an echo that sums two labelled call outputs (for the aggregation test)
/// but can be overridden per-test via [jsExecResponse].
class _FakeBridge implements ScriptBridge {
  _FakeBridge({Map<String, String>? responses, this.jsExecResponse})
      : _responses = responses ?? const {};

  final Map<String, String> _responses;

  /// Canned JSON returned by [jsExec]. When null, [jsExec] falls back to the
  /// aggregation echo logic.
  String? jsExecResponse;
  String? lastExecScript;
  String? lastExecJsonArg;
  final List<Map<String, dynamic>> callLog = [];

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) {
    callLog.add({
      'type': 'anonymous',
      'canisterId': canisterId,
      'method': method,
      'mode': mode,
      'args': args,
      'host': host,
    });
    return _responses['$canisterId::$method'];
  }

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
    callLog.add({
      'type': 'authenticated',
      'canisterId': canisterId,
      'method': method,
      'mode': mode,
      'privateKeyB64': privateKeyB64,
      'args': args,
      'host': host,
    });
    return _responses['$canisterId::$method'];
  }

  @override
  String? jsExec({required String script, String? jsonArg}) {
    lastExecScript = script;
    lastExecJsonArg = jsonArg;
    if (jsExecResponse != null) {
      return jsExecResponse;
    }
    // Default echo: sum two labelled call outputs when present, else 0.
    if (jsonArg != null) {
      final Map<String, dynamic> arg =
          json.decode(jsonArg) as Map<String, dynamic>;
      final calls = arg['calls'] as Map<String, dynamic>?;
      if (calls != null && calls.containsKey('a') && calls.containsKey('b')) {
        final a = (calls['a'] as Map<String, dynamic>)['value'] as int;
        final b = (calls['b'] as Map<String, dynamic>)['value'] as int;
        return json.encode({'ok': true, 'result': a + b});
      }
    }
    return json.encode({'ok': true, 'result': 0});
  }

  // Lifecycle/lint methods are exercised by ScriptAppRuntime tests; not needed
  // for ScriptRunner.run.
  @override
  String? jsLint({required String script}) =>
      json.encode({'ok': true, 'errors': <String>[]});

  @override
  String? jsAppInit({required String script, String? jsonArg, int budgetMs = 50}) => null;

  @override
  String? jsAppView({required String script, required String stateJson, int budgetMs = 50}) => null;

  @override
  String? jsAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) => null;
}

const String _bundle = 'globalThis.init=()=>({state:{},effects:[]});';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScriptRunner.run', () {
    test('aggregates canister outputs and passes them to the bundle', () async {
      final bridge = _FakeBridge(responses: {
        'cid1::m1': json.encode({'value': 2}),
        'cid2::m2': json.encode({'value': 3}),
      });
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        bundle: _bundle,
        calls: [
          CanisterCallSpec(label: 'a', canisterId: 'cid1', method: 'm1', mode: 0, argsJson: '()'),
          CanisterCallSpec(label: 'b', canisterId: 'cid2', method: 'm2', mode: 0, argsJson: '()'),
        ],
      );

      final res = await runner.run(plan);

      expect(res.ok, true);
      expect(res.result, 5);
    });

    test('empty bundle fails with a clear error', () async {
      final runner = ScriptRunner(_FakeBridge());
      final res = await runner.run(ScriptRunPlan(bundle: '   '));
      expect(res.ok, false);
      expect(res.error, contains('empty'));
    });

    test('initialArg is forwarded under arg.input', () async {
      final bridge = _FakeBridge(jsExecResponse: json.encode({'ok': true, 'result': 'ok'}));
      final runner = ScriptRunner(bridge);
      await runner.run(ScriptRunPlan(
        bundle: _bundle,
        initialArg: {'message': 'Hello'},
      ));
      final arg = json.decode(bridge.lastExecJsonArg!) as Map<String, dynamic>;
      expect(arg['input'], {'message': 'Hello'});
    });

    test('script returning ok:false surfaces its error message', () async {
      final bridge = _FakeBridge(jsExecResponse: json.encode({
        'ok': false,
        'error': 'syntax error near line 1',
      }));
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(bundle: _bundle));
      expect(res.ok, false);
      expect(res.error, contains('syntax error near line 1'));
    });

    test('script returning a UI description is passed through unchanged', () async {
      final bridge = _FakeBridge(jsExecResponse: json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {'type': 'list', 'items': [{'title': 'A'}, {'title': 'B'}]},
        },
      }));
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(bundle: _bundle));
      expect(res.ok, true);
      final obj = res.result as Map<String, dynamic>;
      expect(obj['action'], 'ui');
      expect((obj['ui'] as Map<String, dynamic>)['type'], 'list');
    });

    test('follow-up call action triggers a single canister call', () async {
      final bridge = _FakeBridge(
        responses: {'abc::go': json.encode({'ok': true, 'echo': 'go'})},
        jsExecResponse: json.encode({
          'ok': true,
          'result': {'action': 'call', 'canister_id': 'abc', 'method': 'go', 'mode': 0, 'args': '()'},
        }),
      );
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(bundle: _bundle));
      expect(res.ok, true);
      expect((res.result as Map<String, dynamic>)['echo'], 'go');
      // Exactly one anonymous follow-up call.
      expect(bridge.callLog.where((c) => c['type'] == 'anonymous'), hasLength(1));
    });

    test('follow-up call with missing canister_id fails', () async {
      final bridge = _FakeBridge(jsExecResponse: json.encode({
        'ok': true,
        'result': {'action': 'call', 'method': 'go', 'mode': 0, 'args': '()'},
      }));
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(bundle: _bundle));
      expect(res.ok, false);
      expect(res.error, contains('missing canister_id/method'));
    });

    test('batch action executes multiple calls and collects outputs by label', () async {
      final bridge = _FakeBridge(
        responses: {
          'c1::m1': json.encode({'value': 1}),
          'c2::m2': json.encode({'value': 2}),
        },
        jsExecResponse: json.encode({
          'ok': true,
          'result': {
            'action': 'batch',
            'calls': [
              {'label': 'a', 'canister_id': 'c1', 'method': 'm1', 'mode': 0, 'args': '()'},
              {'label': 'b', 'canister_id': 'c2', 'method': 'm2', 'mode': 0, 'args': '()'},
            ],
          },
        }),
      );
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(bundle: _bundle));
      expect(res.ok, true);
      final out = res.result as Map<String, dynamic>;
      expect((out['a'] as Map)['value'], 1);
      expect((out['b'] as Map)['value'], 2);
    });

    test('empty response from a canister call fails', () async {
      final bridge = _FakeBridge(responses: {'cid::m': ''});
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(
        bundle: _bundle,
        calls: [CanisterCallSpec(label: 'a', canisterId: 'cid', method: 'm', mode: 0)],
      ));
      expect(res.ok, false);
      expect(res.error, contains('Empty response'));
    });

    test('non-JSON canister response is surfaced as a raw string', () async {
      final bridge = _FakeBridge(responses: {'cid::m': 'not-json'});
      final runner = ScriptRunner(bridge);
      final res = await runner.run(ScriptRunPlan(
        bundle: _bundle,
        calls: [CanisterCallSpec(label: 'a', canisterId: 'cid', method: 'm', mode: 0)],
      ));
      expect(res.ok, false);
      expect(res.error, contains('Invalid JSON'));
    });
  });

  group('ScriptRunner.performAction', () {
    test('call action executes and decodes JSON', () async {
      final runner = ScriptRunner(_FakeBridge(responses: {
        'abc::go': json.encode({'ok': true}),
      }));
      final res = await runner.performAction({
        'action': 'call',
        'canister_id': 'abc',
        'method': 'go',
        'mode': 0,
        'args': '()',
      });
      expect(res.ok, true);
      expect((res.result as Map<String, dynamic>)['ok'], true);
    });

    test('unsupported action fails', () async {
      final runner = ScriptRunner(_FakeBridge());
      final res = await runner.performAction({'action': 'rocket'});
      expect(res.ok, false);
      expect(res.error, contains('Unsupported action'));
    });

    test('missing action fails', () async {
      final runner = ScriptRunner(_FakeBridge());
      final res = await runner.performAction({});
      expect(res.ok, false);
      expect(res.error, contains('missing action'));
    });
  });

  group('ScriptRunner keypair resolution', () {
    late _FakeBridge bridge;
    late FakeSecureKeypairRepository secureRepo;
    late String keypairId1;
    late String privateKey1;
    late String keypairId2;
    late String privateKey2;

    setUp(() async {
      bridge = _FakeBridge(responses: {
        'test-canister::method': json.encode({'result': 'success'}),
      });
      final kp1 = await TestKeypairFactory.fromSeed(1);
      final kp2 = await TestKeypairFactory.fromSeed(2);
      keypairId1 = kp1.id;
      privateKey1 = kp1.privateKey;
      keypairId2 = kp2.id;
      privateKey2 = kp2.privateKey;
      secureRepo = FakeSecureKeypairRepository([kp1, kp2]);
    });

    ScriptRunPlan buildPlan(String id, {String? privateKey, bool anonymous = false}) =>
        ScriptRunPlan(
          bundle: _bundle,
          calls: [
            CanisterCallSpec(
              label: 'test_call',
              canisterId: 'test-canister',
              method: 'method',
              mode: 0,
              keypairId: id.isEmpty ? null : id,
              privateKeyB64: privateKey,
              isAnonymous: anonymous,
            ),
          ],
        );

    test('keypairId resolves via the repository and authenticates', () async {
      final runner = ScriptRunner(bridge, secureRepository: secureRepo);
      final res = await runner.run(buildPlan(keypairId1));
      expect(res.ok, true);
      expect(bridge.callLog.single['type'], 'authenticated');
      expect(bridge.callLog.single['privateKeyB64'], privateKey1);
    });

    test('privateKeyB64 authenticates directly', () async {
      final runner = ScriptRunner(bridge);
      final res = await runner.run(buildPlan('', privateKey: 'direct_private_key'));
      expect(res.ok, true);
      expect(bridge.callLog.single['type'], 'authenticated');
      expect(bridge.callLog.single['privateKeyB64'], 'direct_private_key');
    });

    test('keypairId takes priority over privateKeyB64', () async {
      final runner = ScriptRunner(bridge, secureRepository: secureRepo);
      final res = await runner.run(buildPlan(keypairId2, privateKey: 'ignored'));
      expect(res.ok, true);
      expect(bridge.callLog.single['privateKeyB64'], privateKey2);
    });

    test('isAnonymous=true forces anonymous even with a private key', () async {
      final runner = ScriptRunner(bridge);
      final res = await runner.run(buildPlan('', privateKey: 'ignored', anonymous: true));
      expect(res.ok, true);
      expect(bridge.callLog.single['type'], 'anonymous');
    });

    test('defaults to anonymous when no keypair specified', () async {
      final runner = ScriptRunner(bridge);
      final res = await runner.run(buildPlan(''));
      expect(res.ok, true);
      expect(bridge.callLog.single['type'], 'anonymous');
    });

    test('empty/whitespace privateKey defaults to anonymous', () async {
      final runner = ScriptRunner(bridge);
      final res = await runner.run(buildPlan('', privateKey: '   '));
      expect(res.ok, true);
      expect(bridge.callLog.single['type'], 'anonymous');
    });

    test('unknown keypairId fails with a clear error and makes no calls', () async {
      final runner = ScriptRunner(bridge, secureRepository: secureRepo);
      final res = await runner.run(buildPlan('non-existent-id'));
      expect(res.ok, false);
      expect(res.error, contains('Keypair with ID "non-existent-id" not found'));
      expect(bridge.callLog, isEmpty);
    });

    test('keypairId without a repository fails fast', () async {
      final runner = ScriptRunner(bridge); // no repository
      final res = await runner.run(buildPlan('test-id-1'));
      expect(res.ok, false);
      expect(res.error,
          contains('Keypair ID specified but no secure keypair repository provided'));
      expect(bridge.callLog, isEmpty);
    });
  });
}
