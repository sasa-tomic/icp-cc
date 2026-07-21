// UX-H12 — Call Builder snippet generator emits the host contract.
//
// Before UX-H12 the snippet generator at `canister_call_builder.dart`'s
// `_generateBundle` emitted broken syntax for authenticated calls:
//   `keypair_id: "<id>"` — no such field exists on the host's `icp_call` effect
// plus a non-running `// Note: You'll need to set private_key_b64 or keypair_id`
// comment. The actual host contract (script_app_host.dart's `_resolveAuthForCall`)
// resolves `authenticated: true` to the active profile keypair; the bundle NEVER
// carries raw key material.
//
// These tests verify `CanisterCallBuilderDialog.generateBundle` (the
// `@visibleForTesting` pure function extracted from `_generateBundle`):
//   (a) when [isAuthenticated] is true → emits `authenticated: true,` and
//       NEVER `keypair_id` or `private_key_b64`;
//   (b) when [isAuthenticated] is false → contains neither;
//   (c) cross-validates the contract: an `icp_call` effect parametrised by the
//       snippet's auth flag drives the real [ScriptAppHost] — when the snippet
//       says `authenticated: true`, the host dispatches `callAuthenticated`;
//       when it doesn't, the host dispatches `callAnonymous`. This proves the
//       snippet matches the host contract end-to-end (no crypto mocked — the
//       recording bridge observes which path is taken and with what key).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/canister_call_builder.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

import '../../shared/test_keypair_factory.dart';

const String _kCanisterId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _kMethodName = 'account_balance_dfx';

void main() {
  group('generateBundle (snippet text)', () {
    test(
        'authenticated=true → snippet contains `authenticated: true,` and '
        'NEVER the broken legacy fields', () {
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: _kCanisterId,
        methodName: _kMethodName,
        callMode: 0,
        argsString: '()',
        isAuthenticated: true,
      );

      expect(snippet.contains('authenticated: true,'), isTrue,
          reason: 'Snippet must carry the host contract flag.');
      expect(snippet.contains('keypair_id'), isFalse,
          reason: 'Broken legacy field must not appear.');
      expect(snippet.contains('private_key_b64'), isFalse,
          reason: 'Bundles never carry raw key material.');
      expect(snippet.contains('method: "$_kMethodName"'), isTrue,
          reason: 'Sanity: the method NAME is emitted (not the object repr).');
      expect(snippet.contains('canister_id: "$_kCanisterId"'), isTrue,
          reason: 'Sanity: the canister id is emitted.');
    });

    test(
        'authenticated=false → snippet contains neither the auth flag nor the '
        'broken legacy fields', () {
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: _kCanisterId,
        methodName: _kMethodName,
        callMode: 0,
        argsString: '()',
        isAuthenticated: false,
      );

      expect(snippet.contains('authenticated:'), isFalse,
          reason: 'Anonymous calls must not carry the auth flag.');
      expect(snippet.contains('keypair_id'), isFalse);
      expect(snippet.contains('private_key_b64'), isFalse);
    });

    test('empty canister id → empty snippet (no partial output)', () {
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: '',
        methodName: _kMethodName,
        callMode: 0,
        argsString: '()',
        isAuthenticated: true,
      );
      expect(snippet, '');
    });

    test('null method name → empty snippet', () {
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: _kCanisterId,
        methodName: null,
        callMode: 0,
        argsString: '()',
        isAuthenticated: true,
      );
      expect(snippet, '');
    });
  });

  // ===========================================================================
  // Cross-validation: prove the snippet's auth flag is what the real host
  // consumes. Mirrors the harness in `script_app_host_auth_test.dart` (no
  // crypto is mocked — the recording bridge just observes which path is taken
  // and with what key material).
  // ===========================================================================
  group('cross-validation with real ScriptAppHost', () {
    testWidgets(
        'snippet with authenticated=true → host invokes callAuthenticated '
        'with the active keypair', (tester) async {
      final ProfileKeypair keypair =
          await TestKeypairFactory.getEd25519Keypair();

      // Generate the snippet — proves the generator emits the right token.
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: _kCanisterId,
        methodName: _kMethodName,
        callMode: 0,
        argsString: '()',
        isAuthenticated: true,
      );
      expect(snippet.contains('authenticated: true,'), isTrue);

      // Build the host effect mirroring the snippet's contract: an `icp_call`
      // effect with `authenticated: true` (the same field the host reads via
      // `_resolveAuthForCall`). The runtime returns it from init so the host
      // dispatches it automatically.
      final bridge = _RecordingBridge();
      final runtime = _SingleEffectRuntime(_effect(authenticated: true));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* generated bundle */',
            authenticatedKeypair: keypair,
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // The host must ask permission and name the identity source.
      expect(find.textContaining('Authenticated (active profile)'),
          findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();

      // The bridge received the active keypair's private key — proving the
      // snippet's `authenticated: true` flag reaches the authenticated bridge
      // path end-to-end.
      expect(bridge.authenticatedCalls, 1);
      expect(bridge.anonymousCalls, 0);
      expect(bridge.lastPrivateKeyB64, keypair.privateKey);
    });

    testWidgets(
        'snippet with authenticated=false → host invokes callAnonymous '
        '(no auth consumed even with a keypair present)', (tester) async {
      // Generate the snippet — proves the generator OMITS the auth token.
      final snippet = CanisterCallBuilderDialog.generateBundle(
        canisterId: _kCanisterId,
        methodName: _kMethodName,
        callMode: 0,
        argsString: '()',
        isAuthenticated: false,
      );
      expect(snippet.contains('authenticated:'), isFalse);

      final bridge = _RecordingBridge();
      final runtime = _SingleEffectRuntime(_effect(authenticated: false));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* generated bundle */',
            // Active keypair is present but the effect does NOT opt into
            // auth — the host MUST NOT sign.
            authenticatedKeypair:
                await TestKeypairFactory.getEd25519Keypair(),
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('Anonymous'), findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();

      expect(bridge.anonymousCalls, 1);
      expect(bridge.authenticatedCalls, 0);
      expect(bridge.lastPrivateKeyB64, isNull);
    });
  });
}

Map<String, dynamic> _effect({required bool authenticated, String id = 'call1'}) =>
    <String, dynamic>{
      'kind': 'icp_call',
      'id': id,
      'mode': 0,
      'canister_id': _kCanisterId,
      'method': _kMethodName,
      'args': '()',
      'authenticated': authenticated,
    };

/// Mirror of the recording bridge in `script_app_host_auth_test.dart`. Returns
/// canned JSON so the effect round-trip completes without touching the network.
class _RecordingBridge implements ScriptBridge {
  String? lastPrivateKeyB64;
  int authenticatedCalls = 0;
  int anonymousCalls = 0;

  @override
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) async {
    anonymousCalls++;
    return '{"ok":true,"result":"anon"}';
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
    authenticatedCalls++;
    lastPrivateKeyB64 = privateKeyB64;
    return '{"ok":true,"result":"auth"}';
  }

  // Lifecycle helpers are unused by these tests but required by the interface.
  @override
  String? jsExec({required String script, String? jsonArg}) => null;
  @override
  String? jsLint({required String script}) => null;
  @override
  String? jsAppInit(
          {required String script, String? jsonArg, int budgetMs = 50}) =>
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

/// Mirror of the single-effect runtime in `script_app_host_auth_test.dart`.
class _SingleEffectRuntime implements IScriptAppRuntime {
  _SingleEffectRuntime(this.initEffect);

  final Map<String, dynamic> initEffect;

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
    return <String, dynamic>{
      'ok': true,
      'state': state,
      'effects': <dynamic>[],
    };
  }
}
