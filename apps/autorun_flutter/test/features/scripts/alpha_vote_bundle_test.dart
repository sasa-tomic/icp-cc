@TestOn('linux')
// Bundle-logic tests for 10_alpha_vote.js. Boots the bundle through the REAL
// FFI runtime (libicp_core.so) and feeds canned effect/result envelopes
// whose shapes match the LIVE mainnet NNS Governance canister (proven via dfx
// + a real authenticated manage_neuron round-trip against
// rrkah-fqaaa-aaaaa-aaaaq-cai on 2026-07-21 — see spec §5 + §10.2 transcripts).
//
// This is the proof that the authenticated headliner dapp decodes real
// mainnet replies correctly end-to-end — including the structured
// `command = opt variant { Error = {...} }` shape that NNS returns for
// non-owned neurons (the auth round-trip PoC).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

// Real mainnet NNS Governance id + gateway — the descriptor defaults.
const String _nnsId = 'rrkah-fqaaa-aaaaa-aaaaq-cai';
const String _host = 'https://ic0.app';
const String _principal = 'test-principal-abc123';

Map<String, dynamic> _initialArg({String? principal}) =>
    <String, dynamic>{
      'backend_id': _nnsId,
      'host': _host,
      if (principal != null) 'principal': principal else 'principal': _principal,
    };

/// Boot the bundle + run init once, returning the runtime and the resulting
/// state. Returns null (with a SKIP log) when libicp_core.so isn't available.
Future<(ScriptAppRuntime, Map<String, dynamic>)?> _boot(String script,
    {String? principal}) async {
  final RustBridgeLoader loader = const RustBridgeLoader();
  if (!nativeLibAvailable(loader)) {
    stdout.writeln('SKIP: libicp_core.so did not load');
    return null;
  }
  final ScriptAppRuntime rt = bootRuntime();
  final Map<String, dynamic> state = Map<String, dynamic>.from((await rt.init(
              script: script,
              initialArg: _initialArg(principal: principal),
              budgetMs: 1000))[
          'state']
      as Map);
  return (rt, state);
}

void _collectTextsAndButtons(Map<String, dynamic> node, List<String> texts,
    List<String> buttonLabels, List<bool> buttonDisabled) {
  final String type = (node['type'] as String?) ?? '';
  final Map<String, dynamic> props =
      (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  if (type == 'text') {
    texts.add((props['text'] ?? '').toString());
  }
  if (type == 'button') {
    buttonLabels.add((props['label'] ?? '').toString());
    buttonDisabled.add((props['disabled'] as bool?) ?? false);
  }
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) {
      _collectTextsAndButtons(c, texts, buttonLabels, buttonDisabled);
    }
  }
}

/// A canned `list_proposals` reply matching the live mainnet shape (mirrors
/// nns_proposals_bundle_test's fixture, plus a `ballots` field carrying the
/// ALPHA-Vote neurons' votes for the signal-decoder coverage).
///
/// Per the Rust bridge (`canister_client.rs::idl_value_to_json`), `nat64`
/// values are serialised as STRINGS to avoid JSON number precision loss
/// (the Ωmega neuron ids exceed 2^53). The bundle's `unwrapOptInt` + the
/// `decodeBallots` `String(pair[0])` coercion handle both shapes.
Map<String, dynamic> _cannedProposalsReply() => <String, dynamic>{
      'ok': true,
      'result': <String, dynamic>{
        'proposal_info': <dynamic>[
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': '125487'}
            ],
            'status': 1, // OPEN (so the vote buttons render enabled)
            'topic': 12,
            'deadline_timestamp_seconds': <dynamic>['1893456000'],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': '2500000000000',
                'no': '80000000000',
                'total': '2580000000000',
                'timestamp_seconds': '0',
              }
            ],
            // ballots: vec record { nat64; Ballot }
            // 3 entries — one per ALPHA-Vote neuron — exercising the decoder.
            // Per the Rust bridge (canister_client.rs label_to_string +
            // IDLValue::Record), each entry's positional record arrives as a
            // MAP with string keys "0" (the nat64 id) + "1" (the Ballot).
            // Nat64 ids arrive as STRINGS (precision-preserved).
            'ballots': <dynamic>[
              <String, dynamic>{
                '0': '2947465672511369',
                '1': <String, dynamic>{
                  'vote': 1, 'voting_power': '10000000000'
                },
              },
              <String, dynamic>{
                '0': '18363645821499695760',
                '1': <String, dynamic>{
                  'vote': 2, 'voting_power': '9000000000'
                },
              },
              // Ωmega-reject has NOT voted yet (omitted from ballots).
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': <String>['https://forum.dfinity.org/t/example'],
                'title': <String>['Replica Version 2026-07-XX'],
                'summary': 'Upgrade replicas to a new replica version.',
              }
            ],
            'proposer': <dynamic>[
              <String, dynamic>{'id': '7'}
            ],
            'reward_status': 1,
          },
        ],
      },
    };

/// The structured ManageNeuronResponse shape that NNS Governance returns for
/// a real authenticated call against a neuron the caller doesn't own (the
/// auth round-trip PoC shape — verified live 2026-07-21, spec §10.2).
Map<String, dynamic> _neuronNotFoundReply() => <String, dynamic>{
      'ok': true,
      'result': <String, dynamic>{
        'command': <dynamic>[
          <String, dynamic>{
            'Error': <String, dynamic>{
              'error_message': 'Neuron not found: NeuronId { id: 12345 }',
              'error_type': 4,
            }
          }
        ],
      },
    };

void main() {
  final String bundle = loadAlphaVoteBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('10_alpha_vote bundle — init / auto-load', () {
    test(
        'init stores mainnet id/host/principal and AUTO-LOADS list_proposals '
        '(anon) + list_neurons (auth) when principal is set', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: bundle, initialArg: _initialArg(), budgetMs: 1000);
      final state = Map<String, dynamic>.from(obj['state'] as Map);

      expect(state['backend_id'], _nnsId);
      expect(state['host'], _host);
      expect(state['principal'], _principal);
      expect(state['neuron_id'], '');
      expect(state['discovered_neuron_ids'], isEmpty);
      expect(state['action_in_flight'], false);

      // AUTO-LOAD: init emits exactly two effects — list_proposals (anon)
      // and list_neurons (auth, because principal is non-empty).
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(2));
      final byId = <String, Map<String, dynamic>>{};
      for (final e in effects) {
        final m = e as Map<String, dynamic>;
        byId[m['id'] as String] = m;
      }

      final listProposals = byId['list_proposals']!;
      expect(listProposals['mode'], 0, reason: 'list_proposals is a query');
      expect(listProposals['authenticated'], false,
          reason: 'list_proposals is anonymous (works keyless)');
      expect(listProposals['canister_id'], _nnsId);
      expect(listProposals['method'], 'list_proposals');

      final listNeurons = byId['list_neurons']!;
      expect(listNeurons['mode'], 0, reason: 'list_neurons is a query');
      expect(listNeurons['authenticated'], true,
          reason: 'list_neurons is authenticated (principal-scoped)');
      expect(listNeurons['method'], 'list_neurons');
      expect(listNeurons['args'],
          contains('include_neurons_readable_by_caller = true'));
    });

    test(
        'init with EMPTY principal emits ONLY list_proposals (no list_neurons '
        'auth call that would fail missing-auth on first frame)', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: bundle,
          initialArg: <String, dynamic>{
            'backend_id': _nnsId,
            'host': _host,
            'principal': '',
          },
          budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1),
          reason: 'keyless init must NOT emit the auth list_neurons call');
      expect((effects[0] as Map)['id'], 'list_proposals');
    });
  });

  group('10_alpha_vote bundle — neuron-id state + discovery', () {
    test('set_neuron_id patches state, no effect emitted', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{'type': 'set_neuron_id', 'value': '987654321'},
          state: state,
          budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect((obj['state'] as Map)['neuron_id'], '987654321');
    });

    test('discover_neurons emits an AUTHENTICATED list_neurons query',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{'type': 'discover_neurons'},
          state: state,
          budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['id'], 'list_neurons');
      expect(eff['mode'], 0);
      expect(eff['method'], 'list_neurons');
      expect(eff['authenticated'], true);
      // The verified-live candid args from spec §5.6.
      expect(eff['args'],
          '(record { neuron_ids = vec {}; include_neurons_readable_by_caller = true; })');
      expect(eff['canister_id'], _nnsId);
      expect(eff['host'], _host);
    });

    test(
        'discover_neurons with EMPTY principal raises a LOUD error and emits '
        'no effect (no silent skip)', () async {
      final boot = await _boot(bundle, principal: '');
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{'type': 'discover_neurons'},
          state: state,
          budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect((obj['state'] as Map)['error'],
          'Sign in with a profile to discover your neurons.');
    });
  });

  group('10_alpha_vote bundle — vote / follow effect builders', () {
    test(
        'vote emits an authenticated UPDATE manage_neuron with the EXACT '
        'candid verified in spec §5.2', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      // Set a neuron id first so the precondition passes.
      final withNeuron = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345';

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'vote',
            'proposal_id': 143015,
            'vote': 1
          },
          state: withNeuron,
          budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['id'], 'vote');
      expect(eff['mode'], 1, reason: 'RegisterVote is an update');
      expect(eff['method'], 'manage_neuron');
      expect(eff['authenticated'], true);
      expect(eff['canister_id'], _nnsId);
      // The exact textual candid verified live via dfx (spec §5.2).
      expect(eff['args'],
          '(record { id = opt record { id = 12345 : nat64 }; '
          'command = opt variant { RegisterVote = record { '
          'vote = 1 : int32; '
          'proposal = opt record { id = 143015 : nat64 }; } }; })');
      // action_in_flight must be flipped on (UI shows "Signing…").
      expect((obj['state'] as Map)['action_in_flight'], true);
    });

    test(
        'vote with EMPTY neuron_id raises a LOUD error and emits no effect '
        '(precondition check)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'vote',
            'proposal_id': 143015,
            'vote': 1
          },
          state: state, // neuron_id is "" by default
          budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect((obj['state'] as Map)['error'],
          'Set your neuron id first (paste one or tap Discover).');
    });

    test(
        'follow emits an authenticated UPDATE manage_neuron Follow with the '
        'EXACT candid verified in spec §5.3', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final withNeuron = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345';

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'follow',
            'topic': '0',
            'followee_id': '4713806069430754115'
          },
          state: withNeuron,
          budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['id'], 'follow');
      expect(eff['mode'], 1, reason: 'Follow is an update');
      expect(eff['method'], 'manage_neuron');
      expect(eff['authenticated'], true);
      expect(eff['args'],
          '(record { id = opt record { id = 12345 : nat64 }; '
          'command = opt variant { Follow = record { '
          'topic = 0 : int32; '
          'followees = vec { record { id = 4713806069430754115 : nat64 } }; } }; })');
    });

    test('follow with EMPTY neuron_id raises a LOUD error (precondition)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'follow',
            'topic': '0',
            'followee_id': '4713806069430754115'
          },
          state: state,
          budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect((obj['state'] as Map)['error'],
          'Set your neuron id first (paste one or tap Discover).');
    });

    test('follow with EMPTY followee_id raises a LOUD error', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final withNeuron = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345';

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'follow',
            'topic': '0',
            'followee_id': ''
          },
          state: withNeuron,
          budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect((obj['state'] as Map)['error'],
          'Enter a followee neuron id to follow.');
    });
  });

  group('10_alpha_vote bundle — effect/result decoding', () {
    test(
        'list_proposals effect/result decodes into the same proposal array '
        'shape as 08_nns_proposals (regression: decoder is shared verbatim)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': _cannedProposalsReply(),
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);

      expect(state['loaded'], true);
      expect(state['error'], '');
      final proposals = state['proposals'] as List<dynamic>;
      expect(proposals, hasLength(1));

      final first = proposals[0] as Map<String, dynamic>;
      expect(first['id'], 125487);
      expect(first['status'], 'Open');
      expect(first['topic'], 'ReplicaVersionManagement');
      expect(first['title'], 'Replica Version 2026-07-XX');
      expect(first['yes'], 2500000000000);
      expect(first['no'], 80000000000);

      // ALPHA-Vote signal decoded: αlpha-vote=Yes, Ωmega-vote=No,
      // Ωmega-reject=not voted yet.
      final signal = first['alpha_signal'] as List<dynamic>;
      expect(signal, hasLength(3));
      final byLabel = <String, String>{
        for (final s in signal)
          (s as Map<String, dynamic>)['label'] as String:
              s['vote_label'] as String,
      };
      expect(byLabel['αlpha-vote'], 'Yes');
      expect(byLabel['Ωmega-vote'], 'No');
      expect(byLabel['Ωmega-reject'], 'not voted yet');
    });

    test(
        'list_neurons effect/result with EMPTY neuron_infos surfaces a friendly '
        'inline state (NOT a loud error — caller simply owns no neurons)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_neurons',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'neuron_infos': <dynamic>[],
                'full_neurons': <dynamic>[],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['discovered_neuron_ids'], isEmpty);
      expect(nextState['neuron_id'], '',
          reason: 'no neuron to auto-pick');
      // NOT a loud error — caller simply owns no neurons (anonymous or
      // neuron-less callers are an expected state, surfaced inline).
      expect(nextState['error'], '');
    });

    test(
        'list_neurons effect/result with 1 neuron populates the pick list and '
        'AUTO-PICKS it as the active neuron_id', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_neurons',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                // neuron_infos: vec record { nat64; NeuronInfo }
                'neuron_infos': <dynamic>[
                  <dynamic>[9876543210, <String, dynamic>{}],
                ],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['discovered_neuron_ids'], <String>['9876543210']);
      expect(nextState['neuron_id'], '9876543210',
          reason: 'first discovered neuron is auto-picked');
    });

    test(
        'list_neurons missing-auth envelope is surfaced LOUDLY (not the silent '
        'view-only path — the user explicitly tapped Discover)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_neurons',
            'ok': false,
            'error': 'authenticated call requested but no active profile keypair',
          },
          state: state,
          budgetMs: 1000);
      // CRITICAL: missing-auth on list_neurons is LOUD (unlike 06_icp_poll's
      // whoami, which treats missing-auth as the expected view-only path).
      // The user explicitly tapped Discover; an empty principal there is a
      // real failure that must surface, not be swallowed.
      expect((obj['state'] as Map)['error'],
          contains('list_neurons:'));
      expect((obj['state'] as Map)['error'],
          contains('no active profile keypair'));
    });

    test(
        'vote effect/result success (RegisterVoteResponse) clears '
        'action_in_flight + surfaces "Vote recorded."', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'command': <dynamic>[
                  <String, dynamic>{
                    'RegisterVoteResponse': <String, dynamic>{},
                  }
                ],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['action_in_flight'], false);
      expect(nextState['last_action_ok'], true);
      expect(nextState['last_action_result'], 'Vote recorded.');
    });

    test(
        'follow effect/result success (FollowResponse) explains the '
        'set-and-forget semantics', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'follow',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'command': <dynamic>[
                  <String, dynamic>{
                    'FollowResponse': <String, dynamic>{},
                  }
                ],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['action_in_flight'], false);
      expect(nextState['last_action_ok'], true);
      expect(nextState['last_action_result'],
          contains('Follow recorded.'));
      // The follow affordance's whole value prop — surface it.
      expect(nextState['last_action_result'],
          contains("you don't need this dapp open"));
    });

    test(
        'vote effect/result with the structured "Neuron not found" Error (the '
        'auth round-trip PoC shape from spec §10.2) surfaces friendlyNnsError '
        'copy + last_action_ok=false', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': _neuronNotFoundReply(),
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['action_in_flight'], false);
      expect(nextState['last_action_ok'], false);
      // The friendlyNnsError "Neuron not found" branch.
      expect(nextState['last_action_result'],
          contains("doesn't see this neuron"));
      expect(nextState['last_action_result'],
          contains('Neuron not found: NeuronId { id: 12345 }'));
    });

    test(
        'vote effect/result with "already voted" Error surfaces the specific '
        'friendly copy (distinct branch)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'command': <dynamic>[
                  <String, dynamic>{
                    'Error': <String, dynamic>{
                      'error_message':
                          'This neuron has already voted on this proposal',
                      'error_type': 7,
                    }
                  }
                ],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['last_action_ok'], false);
      expect(nextState['last_action_result'],
          contains("already voted on this proposal"));
      expect(nextState['last_action_result'],
          contains("doesn't allow changing a vote"));
    });

    test(
        'vote effect/result with malformed shape (unknown variant) surfaces a '
        'LOUD error — never swallowed', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      // A variant the bundle does NOT know how to handle (e.g. a future
      // ManageNeuron command like StakeMaturity). Per AGENTS.md: never silent.
      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'command': <dynamic>[
                  <String, dynamic>{
                    'StakeMaturityResponse': <String, dynamic>{
                      'maturity_e8s': 1000
                    }
                  }
                ],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['last_action_ok'], false);
      expect(nextState['last_action_result'],
          contains('unexpected variant StakeMaturityResponse'));
    });

    test(
        'vote effect/result with completely malformed reply (no command field) '
        'surfaces a LOUD error with raw context', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              // The bridge returned an unexpected envelope shape.
              'result': <String, dynamic>{'unrelated': 'payload'},
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['last_action_ok'], false);
      expect(nextState['last_action_result'],
          contains('malformed reply (command missing)'));
    });

    test(
        'host-level bridge failure on vote (data.ok=false, kind=net) surfaces '
        'a "vote:" prefix + the bridge error (LOUD, never silent)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;
      state = Map<String, dynamic>.from(state)
        ..['neuron_id'] = '12345'
        ..['action_in_flight'] = true;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'vote',
            'ok': true,
            'data': <String, dynamic>{
              'ok': false,
              'kind': 'net',
              'error': 'connection refused',
            },
          },
          state: state,
          budgetMs: 1000);
      final nextState = out['state'] as Map<String, dynamic>;
      expect(nextState['last_action_ok'], false);
      expect(nextState['last_action_result'], 'vote: connection refused');
      expect(nextState['action_in_flight'], false);
    });

    test(
        'list_proposals host-level bridge failure surfaces loudly with a '
        '"list_proposals:" prefix (mirrors 08 + 06 patterns)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': false,
            'error': 'canister unreachable',
          },
          state: state,
          budgetMs: 1000);
      expect((out['state'] as Map)['error'],
          'list_proposals: canister unreachable');
    });
  });

  group('10_alpha_vote bundle — view rendering', () {
    test(
        'view renders the ALPHA-Vote signal section for each proposal (3 '
        'neuron labels appear as text nodes)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Seed state with one OPEN proposal carrying ballots.
      final seeded = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': _cannedProposalsReply(),
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(seeded['state'] as Map);

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      final List<String> buttonLabels = <String>[];
      final List<bool> buttonDisabled = <bool>[];
      _collectTextsAndButtons(ui, texts, buttonLabels, buttonDisabled);

      // ALPHA-Vote signal labels are rendered.
      expect(texts.any((s) => s.contains('αlpha-vote:')), isTrue);
      expect(texts.any((s) => s.contains('Ωmega-vote:')), isTrue);
      expect(texts.any((s) => s.contains('Ωmega-reject:')), isTrue);
      // Decoded votes appear (αlpha-vote=Yes, Ωmega-vote=No).
      expect(texts.any((s) => s.contains('αlpha-vote: Yes')), isTrue);
      expect(texts.any((s) => s.contains('Ωmega-vote: No')), isTrue);
      expect(texts.any((s) => s.contains('Ωmega-reject: not voted yet')), isTrue);

      // Vote buttons with the per-tap intent label.
      expect(buttonLabels.any((s) => s.contains('Vote YES on #125487')), isTrue);
      expect(buttonLabels.any((s) => s.contains('Vote NO on #125487')), isTrue);
      // Follow buttons for the 3 ALPHA-Vote + D-QUORUM neurons.
      expect(buttonLabels.any((s) => s.startsWith('Follow αlpha-vote')), isTrue);
      expect(buttonLabels.any((s) => s.startsWith('Follow D-QUORUM')), isTrue);
    });

    test(
        'view DISABLES vote + follow buttons when neuron_id is empty '
        '(precondition surfaces in the UI, not just the update path)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      final seeded = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': _cannedProposalsReply(),
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(seeded['state'] as Map);
      expect(state['neuron_id'], '',
          reason: 'precondition: no neuron set');

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      final List<String> buttonLabels = <String>[];
      final List<bool> buttonDisabled = <bool>[];
      _collectTextsAndButtons(ui, texts, buttonLabels, buttonDisabled);

      // Every Vote button must be disabled when neuron_id is empty.
      final voteIndices = <int>[];
      for (var i = 0; i < buttonLabels.length; i++) {
        if (buttonLabels[i].startsWith('Vote ')) voteIndices.add(i);
      }
      expect(voteIndices, isNotEmpty, reason: 'sanity: vote buttons rendered');
      for (final i in voteIndices) {
        expect(buttonDisabled[i], isTrue,
            reason: '${buttonLabels[i]} must be disabled when neuron_id empty');
      }
      // Same for Follow buttons.
      final followIndices = <int>[];
      for (var i = 0; i < buttonLabels.length; i++) {
        if (buttonLabels[i].startsWith('Follow ')) followIndices.add(i);
      }
      expect(followIndices, isNotEmpty);
      for (final i in followIndices) {
        expect(buttonDisabled[i], isTrue);
      }
    });

    test(
        'view renders the identity banner (principal visible when signed in, '
        'view-only copy when keyless)', () async {
      // Signed-in path.
      var boot = await _boot(bundle);
      if (boot == null) return;
      final rt = boot.$1;
      var state = boot.$2;
      var viewObj = await rt.view(script: bundle, state: state, budgetMs: 1000);
      var ui = viewObj['ui'] as Map<String, dynamic>;
      var texts = <String>[];
      _collectTextsAndButtons(ui, texts, <String>[], <bool>[]);
      expect(texts.first, contains('signed as: $_principal'));

      // Keyless path.
      boot = await _boot(bundle, principal: '');
      if (boot == null) return;
      final rt2 = boot.$1;
      state = boot.$2;
      viewObj = await rt2.view(script: bundle, state: state, budgetMs: 1000);
      ui = viewObj['ui'] as Map<String, dynamic>;
      texts.clear();
      _collectTextsAndButtons(ui, texts, <String>[], <bool>[]);
      expect(texts.first, contains('view-only'));
    });

    test(
        'pagination: Next page sends before_proposal cursor with the min '
        'proposal id from the previous page', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Feed a FULL page (PAGE_SIZE=10 proposals) so has_more=true.
      // IDs descend: 100..91 → min = 91.
      final fullPage = <String, dynamic>{
        'ok': true,
        'result': <String, dynamic>{
          'proposal_info': List<Map<String, dynamic>>.generate(
              10,
              (i) => <String, dynamic>{
                    'id': <dynamic>[
                      <String, dynamic>{'id': '${100 - i}'}
                    ],
                    'status': 1,
                    'topic': 12,
                    'deadline_timestamp_seconds': <dynamic>['1893456000'],
                    'latest_tally': <dynamic>[
                      <String, dynamic>{
                        'yes': '1000', 'no': '500', 'total': '1500',
                        'timestamp_seconds': '0',
                      }
                    ],
                    'proposal': <dynamic>[
                      <String, dynamic>{
                        'url': <String>[],
                        'title': <String>['Proposal ${100 - i}'],
                        'summary': 'Test.',
                      }
                    ],
                    'proposer': <dynamic>[],
                    'reward_status': 1,
                  }),
        },
      };

      var out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': fullPage,
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);

      expect(state['has_more'], true);
      final history = state['cursor_history'] as List<dynamic>;
      expect(history[1], 91);

      out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{'type': 'page', 'delta': 1},
          state: state,
          budgetMs: 1000);
      final effects = out['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final args = (effects[0] as Map<String, dynamic>)['args'] as String;
      expect(args,
          contains('before_proposal = opt record { id = 91 : nat64 }'));
    });
  });
}
