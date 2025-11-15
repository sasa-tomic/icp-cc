import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/identity_repository.dart';
import 'package:icp_autorun/services/script_runner.dart';

class _FakeBridge implements ScriptBridge {
  _FakeBridge({required this.responses});
  final Map<String, String> responses;
  final List<Map<String, dynamic>> callLog = [];

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    callLog.add({
      'type': 'anonymous',
      'canisterId': canisterId,
      'method': method,
      'kind': kind,
      'args': args,
      'host': host,
    });
    return responses['$canisterId::$method'];
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) {
    callLog.add({
      'type': 'authenticated',
      'canisterId': canisterId,
      'method': method,
      'kind': kind,
      'privateKeyB64': privateKeyB64,
      'args': args,
      'host': host,
    });
    return responses['$canisterId::$method'];
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    // Handle both the original test case and the new identity tests
    if (jsonArg == null) {
      return json.encode({'ok': true, 'result': 0});
    }

    final Map<String, dynamic> arg = json.decode(jsonArg) as Map<String, dynamic>;
    final calls = arg['calls'] as Map<String, dynamic>?;

    // For identity tests, just return 0 since we're only testing call routing
    if (calls != null && calls.containsKey('test_call')) {
      return json.encode({'ok': true, 'result': 0});
    }

    // Original test logic: echo sum of two call outputs if present
    if (calls != null && calls.containsKey('a') && calls.containsKey('b')) {
      final a = (calls['a'] as Map<String, dynamic>)['value'] as int;
      final b = (calls['b'] as Map<String, dynamic>)['value'] as int;
      final result = a + b;
      return json.encode({'ok': true, 'result': result});
    }

    return json.encode({'ok': true, 'result': 0});
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

  group('ScriptRunner Identity Resolution Tests', () {
    late _FakeBridge bridge;
    late IdentityRepository identityRepo;
    late Directory tempDir;

    setUp(() async {
      bridge = _FakeBridge(responses: {
        'test-canister::method': json.encode({'result': 'success'}),
      });
      tempDir = await Directory.systemTemp.createTemp('identity_test_');
      identityRepo = IdentityRepository(overrideDirectory: tempDir);

      // Create test identities
      final identities = [
        IdentityRecord(
          id: 'test-id-1',
          label: 'Test Identity 1',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'dGVzdF9wdWJsaWNfa2V5XzE=',
          privateKey: 'test_private_key_1',
          mnemonic: 'test mnemonic one',
          createdAt: DateTime.now(),
        ),
        IdentityRecord(
          id: 'test-id-2',
          label: 'Test Identity 2',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'dGVzdF9wdWJsaWNfa2V5XzI=',
          privateKey: 'test_private_key_2',
          mnemonic: 'test mnemonic two',
          createdAt: DateTime.now(),
        ),
      ];
      await identityRepo.persistIdentities(identities);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('CanisterCallSpec with identityId uses authenticated call with resolved identity', () async {
      final runner = ScriptRunner(bridge, identityRepository: identityRepo);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            identityId: 'test-id-1',
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an authenticated call was made with the resolved private key
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'authenticated');
      expect(bridge.callLog.first['privateKeyB64'], 'test_private_key_1');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec with privateKeyB64 uses authenticated call with provided key', () async {
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            privateKeyB64: 'direct_private_key',
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an authenticated call was made with the direct private key
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'authenticated');
      expect(bridge.callLog.first['privateKeyB64'], 'direct_private_key');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec with isAnonymous=true uses anonymous call even when privateKey provided', () async {
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            privateKeyB64: 'should_be_ignored',
            isAnonymous: true,
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an anonymous call was made despite having a private key
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'anonymous');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec defaults to anonymous when no identity specified', () async {
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an anonymous call was made
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'anonymous');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec prioritizes identityId over privateKeyB64', () async {
      final runner = ScriptRunner(bridge, identityRepository: identityRepo);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            privateKeyB64: 'should_be_ignored',
            identityId: 'test-id-2',
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that identityId takes priority over privateKeyB64
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'authenticated');
      expect(bridge.callLog.first['privateKeyB64'], 'test_private_key_2');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec fails when identityId not found', () async {
      final runner = ScriptRunner(bridge, identityRepository: identityRepo);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            identityId: 'non-existent-id',
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, false);
      expect(res.error, contains('Identity with ID "non-existent-id" not found'));

      // Verify no calls were made
      expect(bridge.callLog.isEmpty, true);
      bridge.callLog.clear();
    });

    test('CanisterCallSpec fails when identityId specified but no repository provided', () async {
      final runner = ScriptRunner(bridge); // No identity repository
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            identityId: 'test-id-1',
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, false);
      expect(res.error, contains('Identity ID specified but no identity repository provided'));

      // Verify no calls were made
      expect(bridge.callLog.isEmpty, true);
      bridge.callLog.clear();
    });

    test('CanisterCallSpec with empty privateKey defaults to anonymous', () async {
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            privateKeyB64: '', // Empty string
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an anonymous call was made
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'anonymous');
      bridge.callLog.clear();
    });

    test('CanisterCallSpec with whitespace-only privateKey defaults to anonymous', () async {
      final runner = ScriptRunner(bridge);
      final plan = ScriptRunPlan(
        luaSource: 'return 0',
        calls: [
          CanisterCallSpec(
            label: 'test_call',
            canisterId: 'test-canister',
            method: 'method',
            kind: 0,
            privateKeyB64: '   ', // Whitespace only
          ),
        ],
      );

      final res = await runner.run(plan);
      expect(res.ok, true);

      // Verify that an anonymous call was made
      expect(bridge.callLog.length, 1);
      expect(bridge.callLog.first['type'], 'anonymous');
      bridge.callLog.clear();
    });
  });
}
