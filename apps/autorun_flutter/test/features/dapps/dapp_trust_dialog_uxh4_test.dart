import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UX-H4 regression: the per-dapp "Trust this dapp?" prompt must
///   (a) render THREE buttons: Deny, Allow once, Trust this dapp;
///   (b) include a principal-visibility warning (the dapp can identify the
///       caller on every authenticated canister call);
///   (c) when the user taps "Allow once", proceed with the current call(s)
///       for this session WITHOUT persisting the grant; and
///   (d) when the user taps "Trust this dapp", persist the grant to
///       [DappTrustStore] (existing behaviour, kept honest here).
///
/// `dapp_trust_test.dart` covers the all-or-nothing semantics; this file
/// adds the UX-H4 affordances that were missing.

class _RecordingBridge implements ScriptBridge {
  int anonymousCalls = 0;
  final List<String> methods = <String>[];

  @override
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) async {
    anonymousCalls++;
    methods.add(method);
    return '{"ok":true,"result":[]}';
  }

  @override
  Future<String?> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) async {
    methods.add(method);
    return '{"ok":true,"result":"recorded"}';
  }

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
  const String dappId = 'uxh4_trust_dialog_test';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('UX-H4 — Trust dialog affordances', () {
    testWidgets(
      'renders three buttons: Deny, Allow once, Trust this dapp',
      (tester) async {
        final bridge = _RecordingBridge();
        final runtime = _EffectRuntime(
            initEffects: [_anonCall(id: 'e1', method: 'listPolls')]);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ScriptAppHost(
              runtime: runtime,
              script: '/* bundled dapp */',
              dappTrustId: dappId,
              testBridge: bridge,
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.text('Trust this dapp?'), findsOneWidget);
        expect(find.text('Deny'), findsOneWidget);
        expect(find.text('Allow once'), findsOneWidget,
            reason: 'UX-H4: the user MUST have a session-only path that does '
                'not persist trust.');
        expect(find.text('Trust this dapp'), findsOneWidget);
      },
    );

    testWidgets(
      'body warns that the dapp can identify the caller by principal',
      (tester) async {
        final bridge = _RecordingBridge();
        final runtime = _EffectRuntime(
            initEffects: [_anonCall(id: 'e1', method: 'listPolls')]);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ScriptAppHost(
              runtime: runtime,
              script: '/* bundled dapp */',
              dappTrustId: dappId,
              testBridge: bridge,
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.text('Trust this dapp?'), findsOneWidget);
        // The body must surface the deanonymization risk explicitly.
        expect(find.textContaining('principal'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Allow once" runs the current call(s) WITHOUT persisting trust',
      (tester) async {
        final bridge = _RecordingBridge();
        final runtime = _EffectRuntime(
            initEffects: [_anonCall(id: 'e1', method: 'listPolls')]);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ScriptAppHost(
              runtime: runtime,
              script: '/* bundled dapp */',
              dappTrustId: dappId,
              testBridge: bridge,
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.text('Allow once'), findsOneWidget);
        await tester.tap(find.text('Allow once'));
        await tester.pumpAndSettle();

        // The current effect proceeded.
        expect(bridge.anonymousCalls, 1,
            reason: 'Allow once must let the current call through.');

        // The persistent grant must NOT have been written.
        expect(await DappTrustStore.isTrusted(dappId), isFalse,
            reason: 'Allow once is session-only — must not persist trust.');
      },
    );

    testWidgets(
      'tapping "Trust this dapp" persists the grant (existing behaviour kept '
      'honest — UX-H4 does NOT weaken persistence)',
      (tester) async {
        final bridge = _RecordingBridge();
        final runtime = _EffectRuntime(
            initEffects: [_anonCall(id: 'e1', method: 'listPolls')]);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ScriptAppHost(
              runtime: runtime,
              script: '/* bundled dapp */',
              dappTrustId: dappId,
              testBridge: bridge,
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        await tester.tap(find.text('Trust this dapp'));
        await tester.pumpAndSettle();

        expect(bridge.anonymousCalls, 1);
        expect(await DappTrustStore.isTrusted(dappId), isTrue,
            reason: 'Trust this dapp must still persist the grant.');
      },
    );
  });
}
