// Tests for the app-lifecycle host's authenticated-effect resolution.
// Covers the two STEP-1 guarantees:
//   (a) `authenticated: true` + an active profile keypair → the host signs via
//       that keypair (asserted through a recording fake bridge — NO crypto is
//       mocked; the real end-to-end signing proof lives in
//       live_canister_auth_test.dart).
//   (b) `authenticated: true` with NO keypair → a LOUD error result, never a
//       silent fallback to anonymous.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

import '../../shared/test_keypair_factory.dart';

/// Records every canister call the host makes and returns canned JSON so the
/// effect/result round-trip completes without touching the network.
class _RecordingBridge implements ScriptBridge {
  String? lastPrivateKeyB64;
  String? lastAnonymousCanisterId;
  int authenticatedCalls = 0;
  int anonymousCalls = 0;

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) {
    anonymousCalls++;
    lastAnonymousCanisterId = canisterId;
    return '{"ok":true,"result":[]}';
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
    authenticatedCalls++;
    lastPrivateKeyB64 = privateKeyB64;
    return '{"ok":true,"result":"recorded-caller"}';
  }

  // Lifecycle helpers are unused by these tests but required by the interface.
  @override
  String? jsExec({required String script, String? jsonArg}) => null;
  @override
  String? jsLint({required String script}) => null;
  @override
  String? jsAppInit({required String script, String? jsonArg, int budgetMs = 50}) =>
      null;
  @override
  String? jsAppView(
          {required String script,
          required String stateJson,
          int budgetMs = 50}) =>
      null;
  @override
  String? jsAppUpdate(
          {required String script,
          required String msgJson,
          required String stateJson,
          int budgetMs = 50}) =>
      null;
}

/// Fake runtime: returns an authenticated effect from init, and records every
/// effect/result msg the host delivers back so tests can assert on outcomes.
class _EffectRuntime implements IScriptAppRuntime {
  _EffectRuntime({required this.initEffect});

  final Map<String, dynamic> initEffect;
  final List<Map<String, dynamic>> dispatchedMsgs = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> init(
      {required String script,
      Map<String, dynamic>? initialArg,
      int budgetMs = 50}) async {
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': <Map<String, dynamic>>[initEffect],
    };
  }

  @override
  Future<Map<String, dynamic>> view(
      {required String script,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    return <String, dynamic>{
      'ok': true,
      'ui': <String, dynamic>{
        'type': 'column',
        'children': <dynamic>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> update(
      {required String script,
      required Map<String, dynamic> msg,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    dispatchedMsgs.add(msg);
    return <String, dynamic>{
      'ok': true,
      'state': state,
      'effects': <dynamic>[],
    };
  }
}

const String _canister = 'uxrrr-q7777-77774-qaaaq-cai';

Map<String, dynamic> _authEffect({String id = 'whoami'}) => <String, dynamic>{
      'kind': 'icp_call',
      'id': id,
      'mode': 0,
      'canister_id': _canister,
      'method': 'whoami',
      'args': '()',
      'authenticated': true,
    };

void main() {
  testWidgets(
      'authenticated effect with active keypair signs via that keypair (active profile label shown)',
      (tester) async {
    final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(initEffect: _authEffect());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundle */',
          authenticatedKeypair: keypair,
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // The host must ask permission and name the identity source.
    expect(find.textContaining('Authenticated (active profile)'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    // The bridge received the keypair's private key — signing happened as "me".
    expect(bridge.authenticatedCalls, 1);
    expect(bridge.anonymousCalls, 0);
    expect(bridge.lastPrivateKeyB64, keypair.privateKey);
  });

  testWidgets(
      'authenticated effect with NO keypair fails LOUDLY, never silently anonymous',
      (tester) async {
    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(initEffect: _authEffect());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundle */',
          // No authenticatedKeypair on purpose.
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // No permission dialog (the loud error short-circuits before any call).
    expect(find.textContaining('Allow canister call?'), findsNothing);
    expect(bridge.authenticatedCalls, 0);
    expect(bridge.anonymousCalls, 0);

    // The error must be delivered as an effect/result with ok:false.
    expect(runtime.dispatchedMsgs, isNotEmpty);
    final error = runtime.dispatchedMsgs.firstWhere(
      (m) => m['type'] == 'effect/result' && m['id'] == 'whoami',
    );
    expect(error['ok'], false);
    expect(error['error'].toString(), contains('no active profile keypair'));
  });

  testWidgets('explicit private_key_b64 still wins (compat path)', (tester) async {
    final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(
      initEffect: <String, dynamic>{
        ..._authEffect(id: 'compat'),
        'private_key_b64': keypair.privateKey,
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundle */',
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // Explicit key → "explicit key" identity source, regardless of profile.
    expect(find.textContaining('Authenticated (explicit key)'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(bridge.authenticatedCalls, 1);
    expect(bridge.lastPrivateKeyB64, keypair.privateKey);
  });
}
