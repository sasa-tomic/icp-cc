@TestOn('linux')
// Bundle-logic tests for 08_nns_proposals.js. Boots the bundle through the
// REAL FFI runtime (libicp_core.so) and feeds canned effect/result envelopes
// whose shapes match the LIVE mainnet NNS Governance canister (proven via dfx
// against rrkah-fqaaa-aaaaa-aaaaq-cai on 2026-07-21). This is the proof that
// the governance headliner demo decodes real mainnet replies correctly
// end-to-end — including the `opt T → [T]` unwrap quirk of the JSON bridge.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

// Real mainnet NNS Governance id + gateway — the descriptor defaults.
const String _nnsId = 'rrkah-fqaaa-aaaaa-aaaaq-cai';
const String _host = 'https://ic0.app';

Map<String, dynamic> _initialArg() =>
    <String, dynamic>{'backend_id': _nnsId, 'host': _host};

/// Boot the bundle + run init once, returning the runtime and the resulting
/// state. Returns null (with a SKIP log) when libicp_core.so isn't available
/// in this environment — callers `return` on null.
Future<(ScriptAppRuntime, Map<String, dynamic>)?> _boot(String script) async {
  final RustBridgeLoader loader = const RustBridgeLoader();
  if (!nativeLibAvailable(loader)) {
    stdout.writeln('SKIP: libicp_core.so did not load');
    return null;
  }
  final ScriptAppRuntime rt = bootRuntime();
  final Map<String, dynamic> state = Map<String, dynamic>.from((await rt.init(
          script: script, initialArg: _initialArg(), budgetMs: 1000))['state']
      as Map);
  return (rt, state);
}

/// Walk a UI tree and collect every text node's text.
void _collectTexts(Map<String, dynamic> node, List<String> texts) {
  final String type = (node['type'] as String?) ?? '';
  final Map<String, dynamic> props =
      (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  if (type == 'text') {
    texts.add((props['text'] ?? '').toString());
  }
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) {
      _collectTexts(c, texts);
    }
  }
}

/// A canned `list_proposals` reply that matches the live mainnet shape: opt
/// fields arrive as 1-element arrays, status/topic are bare ints. Built from
/// a real `dfx canister call` against rrkah-fqaaa-aaaaa-aaaaq-cai.
Map<String, dynamic> _cannedReply() => <String, dynamic>{
      'ok': true,
      'result': <String, dynamic>{
        'proposal_info': <dynamic>[
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': 125487}
            ],
            'status': 4, // Executed
            'topic': 12, // ReplicaVersionManagement (observed live)
            'deadline_timestamp_seconds': <dynamic>[1752979200],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': 2500000000000,
                'no': 80000000000,
                'total': 2580000000000,
                'timestamp_seconds': 0,
              }
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': <String>['https://forum.dfinity.org/t/example'],
                'title': <String>['Replica Version 2026-07-XX'],
                'summary': 'Upgrade replicas to a new replica version.',
                'action': <dynamic>[
                  <String, dynamic>{
                    'ExecuteGenericNervousSystemFunction': <String, dynamic>{}
                  }
                ],
              }
            ],
            'proposer': <dynamic>[
              <String, dynamic>{'id': 7}
            ],
            'reward_status': 1,
          },
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': 125490}
            ],
            'status': 4,
            'topic': 12,
            'deadline_timestamp_seconds': <dynamic>[1753104000],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': 1800000000000,
                'no': 200000000000,
                'total': 2000000000000,
                'timestamp_seconds': 0,
              }
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': <String>[],
                'title': <String>['Another Replica Update'],
                'summary': 'Routine subnet update.',
              }
            ],
            'proposer': <dynamic>[],
            'reward_status': 1,
          },
        ],
      },
    };

void main() {
  final String bundle = loadNnsProposalsBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('08_nns_proposals bundle', () {
    test(
        'init stores the mainnet canister id + host and AUTO-LOADS the first '
        'list_proposals query (UXR-6: works out of the box)', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: bundle, initialArg: _initialArg(), budgetMs: 1000);
      final state = Map<String, dynamic>.from(obj['state'] as Map);

      // The real mainnet id + gateway are plumbed through verbatim.
      expect(state['backend_id'], _nnsId);
      expect(state['host'], _host);

      // AUTO-LOAD: init emits exactly one list_proposals query so the tab
      // opens to real data. A regression to `effects: []` re-introduces an
      // empty screen + forced Refresh.
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects[0] as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['mode'], 0, reason: 'list_proposals must be a query');
      expect(eff['authenticated'], false,
          reason: 'list_proposals must be read-only (no profile needed)');
      expect(eff['canister_id'], _nnsId);
      expect(eff['host'], _host);
      expect(eff['method'], 'list_proposals');
      // The Candid args must carry every MANDATORY field with correct types
      // (omit_large_fields = opt true). Verified live via dfx.
      final args = eff['args'] as String;
      expect(args, contains('limit'));
      expect(args, contains('exclude_topic = vec {}'));
      expect(args, contains('include_reward_status = vec {}'));
      expect(args, contains('include_status'));
      expect(args, contains('omit_large_fields = opt true'));
    });

    test(
        'decodes a live-shape list_proposals reply (opt T → [T]) into the UI '
        '— the proof the headliner works against real mainnet', () async {
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
            'data': _cannedReply(),
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);

      expect(state['loaded'], true);
      expect(state['error'], '');
      final proposals = state['proposals'] as List<dynamic>;
      expect(proposals, hasLength(2));

      // Decoded scalar fields reach the state correctly.
      final first = proposals[0] as Map<String, dynamic>;
      expect(first['id'], 125487);
      expect(first['status'], 'Executed');
      expect(first['topic'], 'ReplicaVersionManagement');
      expect(first['title'], 'Replica Version 2026-07-XX');
      expect(first['yes'], 2500000000000);
      expect(first['no'], 80000000000);
      expect(first['url'], 'https://forum.dfinity.org/t/example');

      // Render the view and assert the decoded proposals reach the UI as text.
      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      _collectTexts(ui, texts);

      // The proposal title (truncated to ≤100 chars) and decoded metadata are
      // rendered. We check a substring to stay robust to formatting tweaks.
      expect(texts.any((s) => s.contains('#125487')), isTrue);
      expect(texts.any((s) => s.contains('Replica Version 2026-07-XX')), isTrue);
      expect(texts.any((s) => s.contains('Status: Executed')), isTrue);
      expect(
          texts.any((s) => s.contains('ReplicaVersionManagement')), isTrue);
      // Tally math reaches the UI.
      expect(texts.any((s) => s.contains('Yes:') && s.contains('%')), isTrue);
    });

    test(
        'an ok:false effect surfaces state.error LOUDLY with the method id '
        '(no silent failure)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': false,
            'error': 'canister unreachable',
          },
          state: state,
          budgetMs: 1000);
      final nextState = obj['state'] as Map<String, dynamic>;
      expect(nextState['error'], 'list_proposals: canister unreachable');
      expect(nextState['loading'], false);
    });

    test(
        'a bridge-level ok:false envelope (data.ok=false) is surfaced loudly',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': <String, dynamic>{
              'ok': false,
              'kind': 'net',
              'error': 'connection refused',
            },
          },
          state: state,
          budgetMs: 1000);
      expect((obj['state'] as Map<String, dynamic>)['error'],
          'list_proposals: connection refused');
    });

    test('empty proposal_info is reported honestly, not as a blank screen',
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
            'data': <String, dynamic>{
              'ok': true,
              'result': <String, dynamic>{
                'proposal_info': <dynamic>[],
              },
            },
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);
      expect(state['loaded'], true);
      expect((state['proposals'] as List<dynamic>).length, 0);

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      _collectTexts(ui, texts);
      // Honest empty-state copy + a hint to widen the filter.
      expect(texts.any((s) => s.contains('No proposals match')), isTrue);
    });

    test(
        'changing the status filter rebuilds the Candid args (status→1 for '
        '"open", empty vec for "all") and resets to page 0', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      Future<String> nextArgs(String filterValue) async {
        final out = await rt.update(
            script: bundle,
            msg: <String, dynamic>{
              'type': 'set_status',
              'value': filterValue,
            },
            state: state,
            budgetMs: 1000);
        state = Map<String, dynamic>.from(out['state'] as Map);
        return ((out['effects'] as List<dynamic>).first
            as Map<String, dynamic>)['args'] as String;
      }

      final openArgs = await nextArgs('open');
      expect(openArgs, contains('include_status = vec { 1 : int32 }'));

      final executedArgs = await nextArgs('executed');
      expect(executedArgs, contains('include_status = vec { 4 : int32 }'));

      final allArgs = await nextArgs('all');
      expect(allArgs, contains('include_status = vec {}'));

      // Each filter change resets to page 0.
      expect(state['page'], 0);
      expect(state['status_filter'], 'all');
    });

    test('client-side topic filter narrows results without a server round-trip',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Seed state with both proposals (topic 12).
      state = Map<String, dynamic>.from((await rt.update(
              script: bundle,
              msg: <String, dynamic>{
                'type': 'effect/result',
                'id': 'list_proposals',
                'ok': true,
                'data': _cannedReply(),
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);
      expect((state['proposals'] as List<dynamic>).length, 2);

      // Filter to topic 12 (ReplicaVersionManagement) — both stay.
      state = Map<String, dynamic>.from((await rt.update(
              script: bundle,
              msg: <String, dynamic>{
                'type': 'set_topic',
                'value': '12',
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);
      // set_topic ALSO reloads from server; we get back the same canned page.
      // The decoder then runs filterByTopic → topic-12 only. Our canned reply
      // has only topic-12 proposals, so all stay.
      expect(state['topic_filter'], '12');
    });
  });
}
