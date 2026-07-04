// UX-10 — "Trust this dapp" gate for shipped example dapps.
//
// Three behavioural guarantees codified here:
//   (a) POSITIVE — when `dappTrustId` is set (the shipped example path), the
//       host shows AT MOST ONE prompt ("Trust this dapp?") on a fresh run,
//       then ALL of the dapp's methods run without further prompts (no second
//       per-method dialog). Mirrors the auto-load chain UX-11 added: listPolls
//       → getTally → … never prompts twice.
//   (b) PERSISTENCE — a trust grant previously stored in SharedPreferences is
//       honoured on a "restart" (a fresh host with the same dappTrustId) →
//       ZERO prompts, the bridge fires immediately.
//   (c) NEGATIVE — user/marketplace scripts (dappTrustId unset) keep the
//       strict per-method gate unchanged: two different methods → two distinct
//       "Allow canister call?" prompts. Guards against an accidental weakening
//       of security for arbitrary scripts.
//
// No crypto is mocked. The recording bridge returns canned JSON so the
// effect/result round-trip completes without touching the network; the
// permission-gate semantics under test are independent of signing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every canister call and returns canned JSON so effects complete
/// without touching the network. Mirrors the recording bridge in
/// script_app_host_auth_test.dart.
class _RecordingBridge implements ScriptBridge {
  int anonymousCalls = 0;
  int authenticatedCalls = 0;
  final List<String> methods = <String>[];

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) {
    anonymousCalls++;
    methods.add(method);
    return '{"ok":true,"result":[]}';
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
    authenticatedCalls++;
    methods.add(method);
    return '{"ok":true,"result":"recorded"}';
  }

  // Lifecycle helpers unused here; required by the interface.
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

/// Fake runtime whose `init` returns a list of effects (the auto-load chain).
class _EffectRuntime implements IScriptAppRuntime {
  _EffectRuntime({required this.initEffects});

  final List<Map<String, dynamic>> initEffects;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': initEffects,
    };
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'ui': <String, dynamic>{
        'type': 'column',
        'children': <dynamic>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> update({
    required String script,
    required Map<String, dynamic> msg,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': state,
      'effects': <dynamic>[],
    };
  }
}

const String _canister = 'uxrrr-q7777-77774-qaaaq-cai';

Map<String, dynamic> _anonCall({required String id, required String method}) =>
    <String, dynamic>{
      'kind': 'icp_call',
      'id': id,
      'mode': 0,
      'canister_id': _canister,
      'method': method,
      'args': '()',
      'authenticated': false,
    };

void main() {
  const String dappId = 'icp_poll_test';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'UX-10 (a): shipped example with dappTrustId shows ONE trust prompt then '
      'auto-allows all methods (no second per-method dialog)', (tester) async {
    final bridge = _RecordingBridge();
    // Two distinct methods in the auto-load chain (mirrors listPolls +
    // getTally from UX-10/UX-11). Without the trust gate, the per-method
    // model would fire two prompts.
    final runtime = _EffectRuntime(initEffects: <Map<String, dynamic>>[
      _anonCall(id: 'e_list', method: 'listPolls'),
      _anonCall(id: 'e_tally', method: 'getTally'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundled poll dapp */',
          dappTrustId: dappId,
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // The trust dialog must appear (first effect → not trusted yet).
    expect(find.text('Trust this dapp?'), findsOneWidget,
        reason: 'First canister effect must surface the trust prompt');
    // The per-method dialog must NOT appear — trust gate replaces it.
    expect(find.text('Allow canister call?'), findsNothing);
    // No "Allow once" button in the trust dialog (trust is all-or-nothing).
    expect(find.text('Allow once'), findsNothing);

    await tester.tap(find.text('Trust this dapp'));
    await tester.pumpAndSettle();

    // Both effects must have run — the second method never prompted again.
    expect(bridge.anonymousCalls, 2,
        reason: 'listPolls + getTally both executed');
    expect(bridge.methods, containsAll(<String>['listPolls', 'getTally']));
    // No second dialog of either flavour remains on screen.
    expect(find.text('Trust this dapp?'), findsNothing);
    expect(find.text('Allow canister call?'), findsNothing);

    // The grant must have persisted (restart should not re-prompt).
    expect(await DappTrustStore.isTrusted(dappId), isTrue,
        reason: 'Trust must persist to SharedPreferences on grant');
  });

  testWidgets(
      'UX-10 (b): a previously-persisted trust grant means ZERO prompts on a '
      'fresh host (simulated restart)', (tester) async {
    // Prime the persisted trust — as if the user already trusted this dapp on
    // a previous app run, then restarted.
    await DappTrustStore.setTrusted(dappId);
    expect(await DappTrustStore.isTrusted(dappId), isTrue);

    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(initEffects: <Map<String, dynamic>>[
      _anonCall(id: 'e_list', method: 'listPolls'),
      _anonCall(id: 'e_tally', method: 'getTally'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundled poll dapp */',
          dappTrustId: dappId,
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // ZERO prompts — the loaded trust short-circuits the gate.
    expect(find.text('Trust this dapp?'), findsNothing,
        reason: 'Persisted trust must suppress the prompt on restart');
    expect(find.text('Allow canister call?'), findsNothing);

    // Both calls ran directly.
    expect(bridge.anonymousCalls, 2);
    expect(bridge.methods, containsAll(<String>['listPolls', 'getTally']));
  });

  testWidgets(
      'UX-10 (c) NEGATIVE: user/marketplace script (no dappTrustId) keeps the '
      'strict per-method gate — two different methods = two prompts',
      (tester) async {
    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(initEffects: <Map<String, dynamic>>[
      _anonCall(id: 'e_list', method: 'listPolls'),
      // Same canister, DIFFERENT method → per-method key differs → re-prompt.
      _anonCall(id: 'e_tally', method: 'getTally'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* user-downloaded script */',
          // dappTrustId intentionally unset → strict per-method gate.
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // First effect → per-method dialog (NOT the trust dialog).
    expect(find.text('Allow canister call?'), findsOneWidget);
    expect(find.text('Trust this dapp?'), findsNothing);

    // Allow the first method once (does NOT persist beyond this method).
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    // First call executed.
    expect(bridge.anonymousCalls, 1);
    expect(bridge.methods.last, 'listPolls');

    // The second method (different key) must re-prompt — per-method gate.
    expect(find.text('Allow canister call?'), findsOneWidget,
        reason: 'A different method must prompt again under the per-method gate');
    expect(find.textContaining('getTally'), findsOneWidget);

    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    expect(bridge.anonymousCalls, 2);
    expect(bridge.methods.last, 'getTally');

    // And nothing persisted — user/marketplace scripts never write a trust grant.
    expect(await DappTrustStore.isTrusted(dappId), isFalse);
  });

  testWidgets(
      'UX-10 (a) batch: a single trust prompt covers a multi-call batch',
      (tester) async {
    final bridge = _RecordingBridge();
    // A single icp_batch effect containing two methods. Under the per-method
    // model this would render the multi-line batch dialog; under trust mode it
    // collapses to one trust prompt (or zero, if already trusted).
    final runtime = _EffectRuntime(initEffects: <Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'icp_batch',
        'id': 'b1',
        'items': <dynamic>[
          <String, dynamic>{
            'mode': 0,
            'canister_id': _canister,
            'method': 'listPolls',
            'args': '()',
            'authenticated': false,
          },
          <String, dynamic>{
            'mode': 0,
            'canister_id': _canister,
            'method': 'getTally',
            'args': '()',
            'authenticated': false,
          },
        ],
      },
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundled poll dapp */',
          dappTrustId: dappId,
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Trust dialog (not the multi-line batch dialog).
    expect(find.text('Trust this dapp?'), findsOneWidget);
    expect(find.text('Allow batch canister calls?'), findsNothing);

    await tester.tap(find.text('Trust this dapp'));
    await tester.pumpAndSettle();

    expect(bridge.anonymousCalls, 2,
        reason: 'Both batch items executed after a single trust grant');
    expect(bridge.methods, containsAll(<String>['listPolls', 'getTally']));
  });

  testWidgets(
      'UX-10 deny: tapping Deny on the trust dialog denies the call (no silent '
      'fall-through) and does NOT persist trust', (tester) async {
    final bridge = _RecordingBridge();
    final runtime = _EffectRuntime(initEffects: <Map<String, dynamic>>[
      _anonCall(id: 'e_list', method: 'listPolls'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundled poll dapp */',
          dappTrustId: dappId,
          testBridge: bridge,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Trust this dapp?'), findsOneWidget);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    // No call executed — Deny short-circuits the effect to "permission denied".
    expect(bridge.anonymousCalls, 0);
    // The grant must NOT persist on denial.
    expect(await DappTrustStore.isTrusted(dappId), isFalse);
  });
}
