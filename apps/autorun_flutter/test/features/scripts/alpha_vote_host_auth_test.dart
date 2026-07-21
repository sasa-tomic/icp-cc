// ALPHA-Vote host auth-dispatch integration tests (spec §9.2).
//
// Three behavioural guarantees for the new bundle's effects, mirroring
// script_app_host_auth_test.dart's structure but using the ACTUAL bundle's
// emitted effect shapes (the list_neurons authenticated query from init +
// a manage_neuron vote update). All three cover the host-side auth
// invariant the bundle depends on — they do NOT re-test the bundle logic
// itself (that's alpha_vote_bundle_test.dart's job).
//
//   (a) authenticated effect + active keypair → host signs via that keypair
//       (asserted through a recording fake bridge — NO crypto is mocked).
//   (b) authenticated effect + NO keypair → LOUD error result, never a
//       silent fallback to anonymous.
//   (c) the trust prompt fires on the first authenticated effect with the
//       dapp's `alpha_vote` id (the descriptor's trust key).
//
// These re-prove the host path the bundle uses (script_app_host.dart:322-330
// + 705-723) for the new dapp. The host code itself is unchanged from UX-H12.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_keypair_factory.dart';

const String _alphaVoteId = 'alpha_vote';
const String _nnsCanister = 'rrkah-fqaaa-aaaaa-aaaaq-cai';

/// Records every canister call the host makes and returns canned JSON so the
/// effect/result round-trip completes without touching the network. Mirrors
/// script_app_host_auth_test.dart's recording bridge.
class _RecordingBridge implements ScriptBridge {
  String? lastPrivateKeyB64;
  String? lastAuthenticatedMethod;
  String? lastAnonymousMethod;
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
    lastAnonymousMethod = method;
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
    authenticatedCalls++;
    lastPrivateKeyB64 = privateKeyB64;
    lastAuthenticatedMethod = method;
    // Return the structured Error shape from the verified-live PoC (spec §10.2)
    // — proves the round-trip completes through the host's JSON decoder.
    return '{"ok":true,"result":{"command":[{"Error":{"error_message":'
        '"Neuron not found: NeuronId { id: 12345 }","error_type":4}}]}}';
  }

  // Lifecycle helpers unused here; required by the interface.
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

/// Fake runtime that emits a single authenticated effect from init (the
/// bundle's actual list_neurons OR manage_neuron shape — built via the
/// helpers below). Records every effect/result msg the host delivers back.
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

/// The bundle's actual list_neurons effect shape (mode 0, authenticated):
/// the discovery query emitted by init when principal is non-empty.
Map<String, dynamic> _listNeuronsEffect() => <String, dynamic>{
      'kind': 'icp_call',
      'id': 'list_neurons',
      'mode': 0,
      'canister_id': _nnsCanister,
      'method': 'list_neurons',
      'args': '(record { neuron_ids = vec {}; '
          'include_neurons_readable_by_caller = true; })',
      'authenticated': true,
    };

/// The bundle's actual manage_neuron RegisterVote effect shape (mode 1,
/// authenticated): emitted by the `vote` update message.
Map<String, dynamic> _manageNeuronVoteEffect() => <String, dynamic>{
      'kind': 'icp_call',
      'id': 'vote',
      'mode': 1,
      'canister_id': _nnsCanister,
      'method': 'manage_neuron',
      'args': '(record { id = opt record { id = 12345 : nat64 }; '
          'command = opt variant { RegisterVote = record { '
          'vote = 1 : int32; '
          'proposal = opt record { id = 143015 : nat64 }; } }; })',
      'authenticated': true,
    };

void main() {
  // Fresh SharedPreferences per test — the trust gate reads its persisted
  // grant from prefs, so without a reset a previous test's grant could leak
  // forward and skip the trust prompt (the (c) test below depends on this).
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ALPHA-Vote host auth dispatch (script_app_host.dart)', () {
    testWidgets(
        '(a) list_neurons authenticated effect with active keypair signs via '
        'that keypair (the bundle depends on this for neuron discovery)',
        (tester) async {
      final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
      final bridge = _RecordingBridge();
      final runtime = _EffectRuntime(initEffect: _listNeuronsEffect());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* 10_alpha_vote.js */',
            authenticatedKeypair: keypair,
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Permission dialog must label the identity source (the bundle's
      // list_neurons effect opts into auth; the host resolves the active
      // profile's keypair).
      expect(find.textContaining('Authenticated (active profile)'),
          findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();

      // The bridge received the keypair's private key — signing happened as
      // "me". The method is the bundle's list_neurons (not a generic name).
      expect(bridge.authenticatedCalls, 1);
      expect(bridge.anonymousCalls, 0);
      expect(bridge.lastPrivateKeyB64, keypair.privateKey);
      expect(bridge.lastAuthenticatedMethod, 'list_neurons');
    });

    testWidgets(
        '(a) manage_neuron RegisterVote authenticated effect signs via the '
        'active keypair (the bundle depends on this for the vote update)',
        (tester) async {
      final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
      final bridge = _RecordingBridge();
      final runtime = _EffectRuntime(initEffect: _manageNeuronVoteEffect());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* 10_alpha_vote.js */',
            authenticatedKeypair: keypair,
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('Authenticated (active profile)'),
          findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();

      // The bundle's vote is an UPDATE (mode 1) — the bridge must call
      // callAuthenticated, never callAnonymous.
      expect(bridge.authenticatedCalls, 1);
      expect(bridge.lastAuthenticatedMethod, 'manage_neuron');
      expect(bridge.lastPrivateKeyB64, keypair.privateKey);
    });

    testWidgets(
        '(b) list_neurons authenticated effect with NO keypair fails LOUDLY '
        '(never silently anonymous — missing-auth would corrupt discovery)',
        (tester) async {
      final bridge = _RecordingBridge();
      final runtime = _EffectRuntime(initEffect: _listNeuronsEffect());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* 10_alpha_vote.js */',
            // No authenticatedKeypair on purpose — simulate a keyless user
            // somehow tapping Discover (the bundle disables the button, but
            // the host invariant must hold independently of bundle UI state).
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // No permission dialog (the loud error short-circuits before any call).
      expect(find.textContaining('Allow canister call?'), findsNothing);
      expect(bridge.authenticatedCalls, 0);
      expect(bridge.anonymousCalls, 0,
          reason: 'must NOT silently fall back to anonymous');

      // The error must be delivered as an effect/result with ok:false +
      // the host's _kMissingAuthMessage body.
      expect(runtime.dispatchedMsgs, isNotEmpty);
      final error = runtime.dispatchedMsgs.firstWhere(
        (m) => m['type'] == 'effect/result' && m['id'] == 'list_neurons',
      );
      expect(error['ok'], false);
      expect(error['error'].toString(), contains('no active profile keypair'));
    });

    testWidgets(
        '(b) manage_neuron vote authenticated effect with NO keypair fails '
        'LOUDLY (a silent anon vote would be the worst-case failure mode)',
        (tester) async {
      final bridge = _RecordingBridge();
      final runtime = _EffectRuntime(initEffect: _manageNeuronVoteEffect());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* 10_alpha_vote.js */',
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // CRITICAL: a silent anon vote would either be rejected by NNS (good)
      // or accidentally counted as some default identity (catastrophic).
      // The host's missing-auth path catches this BEFORE the bridge call.
      expect(bridge.authenticatedCalls, 0);
      expect(bridge.anonymousCalls, 0);

      final error = runtime.dispatchedMsgs.firstWhere(
        (m) => m['type'] == 'effect/result' && m['id'] == 'vote',
      );
      expect(error['ok'], false);
      expect(error['error'].toString(), contains('no active profile keypair'));
    });

    testWidgets(
        '(c) first authenticated effect fires the trust prompt keyed by the '
        "dapp's alpha_vote descriptor id (the trust-once UX-10 gate)",
        (tester) async {
      // Use the bridge's auth + anon return shapes; the trust gate is
      // independent of the bridge call's outcome.
      final ProfileKeypair keypair =
          await TestKeypairFactory.getEd25519Keypair();
      final bridge = _RecordingBridge();
      final runtime = _EffectRuntime(initEffect: _listNeuronsEffect());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: runtime,
            script: '/* 10_alpha_vote.js */',
            authenticatedKeypair: keypair,
            dappTrustId: _alphaVoteId,
            testBridge: bridge,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // The TRUST dialog fires (not the per-method dialog) — keyed by the
      // dapp's alpha_vote id. This is the trust-once affordance: one prompt,
      // then all subsequent vote/follow/discover calls run unprompted.
      expect(find.text('Trust this dapp?'), findsOneWidget,
          reason: 'First authenticated effect must surface the trust prompt');
      expect(find.text('Allow canister call?'), findsNothing,
          reason: 'Trust gate replaces the per-method dialog');
    });
  });
}
