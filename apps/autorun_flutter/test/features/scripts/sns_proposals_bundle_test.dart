@TestOn('linux')
// Bundle-logic tests for 09_sns_proposals.js. Boots the bundle through the
// REAL FFI runtime (libicp_core.so) and feeds canned effect/result envelopes
// whose shapes match the LIVE OpenChat SNS governance canister (proven via
// dfx against 2jvtu-yqaaa-aaaaq-aaama-cai on 2026-07-21). This is the proof
// the SNS headliner decodes real mainnet replies correctly end-to-end —
// including the three SNS-specific quirks the NNS bundle doesn't have:
//
//   1. NO `status` field on ProposalData — INFERRED from timestamp fields.
//   2. NO `deadline_timestamp_seconds` — read wait_for_quiet_state instead.
//   3. `topic` is an opt VARIANT, decoded by the bridge as { TagName: null }.
//
// Also proves the theme knob (Unit 2): view() returns { theme: {...} } on
// the root node, and set_canister swaps DAOs in-flight.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

// Real mainnet OpenChat SNS governance id + gateway — the descriptor defaults.
const String _snsId = '2jvtu-yqaaa-aaaaq-aaama-cai';
const String _host = 'https://ic0.app';

Map<String, dynamic> _initialArg({String? canisterId}) =>
    <String, dynamic>{'backend_id': canisterId ?? _snsId, 'host': _host};

Future<(ScriptAppRuntime, Map<String, dynamic>)?> _boot(
  String script, {
  String? canisterId,
}) async {
  final RustBridgeLoader loader = const RustBridgeLoader();
  if (!nativeLibAvailable(loader)) {
    stdout.writeln('SKIP: libicp_core.so did not load');
    return null;
  }
  final ScriptAppRuntime rt = bootRuntime();
  final Map<String, dynamic> state = Map<String, dynamic>.from((await rt.init(
          script: script,
          initialArg: _initialArg(canisterId: canisterId),
          budgetMs: 1000))['state']
      as Map);
  return (rt, state);
}

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

/// A canned `list_proposals` reply that matches the LIVE OpenChat SNS shape
/// (verified via dfx 2026-07-21). Three proposals exercise every status branch
/// of `inferStatus`:
///   - #2313: executed_timestamp_seconds != 0  → "Executed"
///   - #100:  failed_timestamp_seconds != 0    → "Failed"
///   - #50:   all three timestamps = 0          → "Open"
///           (wait_for_quiet_state carries the live deadline)
Map<String, dynamic> _cannedReply() => <String, dynamic>{
      'ok': true,
      'result': <String, dynamic>{
        'proposals': <dynamic>[
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': 2313}
            ],
            'topic': <dynamic>[
              <String, dynamic>{'DappCanisterManagement': null}
            ],
            'action': 10000,
            'decided_timestamp_seconds': 1783696546,
            'executed_timestamp_seconds': 1783696549,
            'failed_timestamp_seconds': 0,
            'wait_for_quiet_state': <dynamic>[
              <String, dynamic>{'current_deadline_timestamp_seconds': 1784041597}
            ],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': 5438884297900292,
                'no': 3378803334575,
                'total': 7114751861367136,
                'timestamp_seconds': 1784036081,
              }
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': 'https://github.com/open-chat-labs/open-chat/releases/tag/v2.0.1992-website',
                'title': 'Upgrade website to 2.0.1992',
                'summary': 'Fixes mentions, scroll-back holes, PWA cold-start.',
              }
            ],
          },
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': 100}
            ],
            'topic': <dynamic>[
              <String, dynamic>{'Governance': null}
            ],
            'action': 1,
            'decided_timestamp_seconds': 0,
            'executed_timestamp_seconds': 0,
            'failed_timestamp_seconds': 1780000000,
            'wait_for_quiet_state': <dynamic>[
              <String, dynamic>{'current_deadline_timestamp_seconds': 0}
            ],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': 100,
                'no': 200,
                'total': 300,
                'timestamp_seconds': 0,
              }
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': '',
                'title': 'A failed proposal',
                'summary': 'Should infer as Failed.',
              }
            ],
          },
          <String, dynamic>{
            'id': <dynamic>[
              <String, dynamic>{'id': 50}
            ],
            'topic': <dynamic>[
              <String, dynamic>{'TreasuryAssetManagement': null}
            ],
            'action': 2,
            'decided_timestamp_seconds': 0,
            'executed_timestamp_seconds': 0,
            'failed_timestamp_seconds': 0,
            'wait_for_quiet_state': <dynamic>[
              <String, dynamic>{'current_deadline_timestamp_seconds': 4102444800}
            ],
            'latest_tally': <dynamic>[
              <String, dynamic>{
                'yes': 60,
                'no': 40,
                'total': 100,
                'timestamp_seconds': 0,
              }
            ],
            'proposal': <dynamic>[
              <String, dynamic>{
                'url': 'https://example.com/p/50',
                'title': 'An open proposal',
                'summary': 'Should infer as Open and show a countdown.',
              }
            ],
          },
        ],
      },
    };

void main() {
  final String bundle = loadSnsProposalsBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('09_sns_proposals bundle', () {
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

      expect(state['backend_id'], _snsId);
      expect(state['host'], _host);

      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects[0] as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['mode'], 0, reason: 'list_proposals must be a query');
      expect(eff['authenticated'], false,
          reason: 'list_proposals must be read-only (no profile needed)');
      expect(eff['canister_id'], _snsId);
      expect(eff['method'], 'list_proposals');
      // SNS Candid args (verified live): exclude_TYPE (not exclude_topic),
      // NO omit_large_fields. Any regression here gets a loud server error.
      final args = eff['args'] as String;
      expect(args, contains('limit'));
      expect(args, contains('exclude_type = vec {}'));
      expect(args, contains('include_reward_status = vec {}'));
      expect(args, contains('include_status'));
      expect(args, isNot(contains('omit_large_fields')),
          reason: 'SNS has no omit_large_fields field');
      expect(args, isNot(contains('exclude_topic')),
          reason: "SNS uses 'exclude_type', not 'exclude_topic'");
    });

    test(
        'init WITHOUT a backend_id does NOT auto-load — waits for the user to '
        'paste a canister id (the SNS-specific empty-state path)', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: bundle,
          initialArg: _initialArg(canisterId: ''),
          budgetMs: 1000);
      final state = Map<String, dynamic>.from(obj['state'] as Map);
      expect(state['backend_id'], '');
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, isEmpty,
          reason: 'no canister id → no auto-load (would only error server-side)');

      // The empty-state prompt is visible in view().
      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      _collectTexts(ui, texts);
      expect(texts.any((s) => s.contains('Paste an SNS governance canister')),
          isTrue);
    });

    test(
        'decodes a live-shape SNS reply: status INFERRED from timestamps, '
        'deadline read from wait_for_quiet_state, topic read from variant tag',
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
            'data': _cannedReply(),
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);

      expect(state['loaded'], true);
      expect(state['error'], '');
      final proposals = state['proposals'] as List<dynamic>;
      expect(proposals, hasLength(3));

      final executed = proposals[0] as Map<String, dynamic>;
      expect(executed['id'], 2313);
      expect(executed['status'], 'Executed',
          reason: 'executed_timestamp_seconds != 0 wins');
      expect(executed['topic'], 'DappCanisterManagement',
          reason: 'variant tag extracted from {Tag: null}');
      expect(executed['title'], 'Upgrade website to 2.0.1992');
      expect(executed['url'],
          'https://github.com/open-chat-labs/open-chat/releases/tag/v2.0.1992-website');

      final failed = proposals[1] as Map<String, dynamic>;
      expect(failed['status'], 'Failed',
          reason: 'failed_timestamp_seconds != 0 → Failed');
      expect(failed['topic'], 'Governance');

      final open = proposals[2] as Map<String, dynamic>;
      expect(open['status'], 'Open',
          reason: 'all three timestamps 0 → Open');
      expect(open['topic'], 'TreasuryAssetManagement');
      expect(open['deadline'], 4102444800,
          reason: 'deadline read from wait_for_quiet_state, not a top-level field');

      // Render and assert the inferred statuses + variant-derived topics reach
      // the UI as text.
      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      _collectTexts(ui, texts);
      expect(texts.any((s) => s.contains('Status: Executed')), isTrue);
      expect(texts.any((s) => s.contains('Status: Failed')), isTrue);
      expect(texts.any((s) => s.contains('Status: Open')), isTrue);
      expect(texts.any((s) => s.contains('DappCanisterManagement')), isTrue);
    });

    test('an ok:false effect surfaces state.error LOUDLY with the method id',
        () async {
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
      expect((obj['state'] as Map<String, dynamic>)['error'],
          'list_proposals: canister unreachable');
      expect((obj['state'] as Map<String, dynamic>)['loading'], false);
    });

    test(
        'set_canister swaps the DAO in-flight: clears proposals, sets the new '
        'canister id, and re-queries', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Seed state with one decoded proposal (proves set_canister wipes it).
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
      expect((state['proposals'] as List<dynamic>).length, 3);

      // Swap to a new DAO.
      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'set_canister',
            'value': 'aaaaa-bbbbb-ccccc',
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);
      expect(state['backend_id'], 'aaaaa-bbbbb-ccccc');
      expect((state['proposals'] as List<dynamic>).length, 0,
          reason: 'old DAO proposals must not bleed into the new DAO');
      expect(state['loading'], true);
      expect(state['page'], 0);

      // The next effect targets the NEW canister id.
      final eff = (out['effects'] as List<dynamic>).first as Map<String, dynamic>;
      expect(eff['canister_id'], 'aaaaa-bbbbb-ccccc');
    });

    test(
        'changing the status filter rebuilds Candid args (status→1 for "open", '
        'empty vec for "all") and resets to page 0', () async {
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

      expect(await nextArgs('open'),
          contains('include_status = vec { 1 : int32 }'));
      expect(await nextArgs('executed'),
          contains('include_status = vec { 4 : int32 }'));
      expect(await nextArgs('all'), contains('include_status = vec {}'));
      expect(state['page'], 0);
      expect(state['status_filter'], 'all');
    });

    test(
        'view() returns a theme map on the root node — the Unit-2 theme knob '
        'is exercised end-to-end (host paints page/card/accent colours)',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      final state = boot.$2;

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      // Root node opts into the host's theme override.
      expect(ui['type'], 'column');
      final theme = ui['theme'];
      expect(theme, isA<Map<String, dynamic>>(),
          reason: 'theme prop must be present for the host to apply it');
      final t = theme as Map<String, dynamic>;
      // Every key the host's _parseHexColor understands is supplied.
      expect(t['background'], isA<String>());
      expect(t['card_background'], isA<String>());
      expect(t['accent'], isA<String>());
      expect(t['text'], isA<String>());
      expect(t['text_muted'], isA<String>());
      // All are valid hex strings (#RRGGBB).
      for (final dynamic v in t.values) {
        expect(v, matches(RegExp(r'^#[0-9a-fA-F]{6}$')));
      }
    });

    test(
        'inferStatus distinguishes adopted vs rejected when decided '
        '(yes >= no → Adopted, yes < no → Rejected)', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Two decided proposals: one adopted (yes > no), one rejected (no > yes).
      final reply = <String, dynamic>{
        'ok': true,
        'result': <String, dynamic>{
          'proposals': <dynamic>[
            <String, dynamic>{
              'id': <dynamic>[
                <String, dynamic>{'id': 300}
              ],
              'topic': <dynamic>[
                <String, dynamic>{'Governance': null}
              ],
              'action': 10000,
              'decided_timestamp_seconds': 1783696546,
              'executed_timestamp_seconds': 0,
              'failed_timestamp_seconds': 0,
              'wait_for_quiet_state': <dynamic>[
                <String, dynamic>{'current_deadline_timestamp_seconds': 0}
              ],
              'latest_tally': <dynamic>[
                <String, dynamic>{
                  'yes': 9000, 'no': 1000, 'total': 10000,
                  'timestamp_seconds': 0,
                }
              ],
              'proposal': <dynamic>[
                <String, dynamic>{
                  'title': <String>['Adopted proposal'],
                  'summary': 'yes > no',
                  'url': <String>[],
                }
              ],
            },
            <String, dynamic>{
              'id': <dynamic>[
                <String, dynamic>{'id': 299}
              ],
              'topic': <dynamic>[
                <String, dynamic>{'Governance': null}
              ],
              'action': 10000,
              'decided_timestamp_seconds': 1783696546,
              'executed_timestamp_seconds': 0,
              'failed_timestamp_seconds': 0,
              'wait_for_quiet_state': <dynamic>[
                <String, dynamic>{'current_deadline_timestamp_seconds': 0}
              ],
              'latest_tally': <dynamic>[
                <String, dynamic>{
                  'yes': 1000, 'no': 9000, 'total': 10000,
                  'timestamp_seconds': 0,
                }
              ],
              'proposal': <dynamic>[
                <String, dynamic>{
                  'title': <String>['Rejected proposal'],
                  'summary': 'no > yes',
                  'url': <String>[],
                }
              ],
            },
          ],
        },
      };

      final out = await rt.update(
          script: bundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'list_proposals',
            'ok': true,
            'data': reply,
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(out['state'] as Map);
      final proposals = state['proposals'] as List<dynamic>;
      expect(proposals, hasLength(2));
      expect((proposals[0] as Map<String, dynamic>)['status'], 'Adopted');
      expect((proposals[1] as Map<String, dynamic>)['status'], 'Rejected');
    });

    test(
        'pagination: Next page sends before_proposal cursor with the min '
        'proposal id from the previous page', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Feed a FULL page (PAGE_SIZE=10 proposals) so has_more=true.
      final fullPage = <String, dynamic>{
        'ok': true,
        'result': <String, dynamic>{
          'proposals': List<Map<String, dynamic>>.generate(
              10,
              (i) => <String, dynamic>{
                    'id': <dynamic>[
                      <String, dynamic>{'id': 100 - i}
                    ],
                    'topic': <dynamic>[
                      <String, dynamic>{'Governance': null}
                    ],
                    'action': 10000,
                    'decided_timestamp_seconds': 0,
                    'executed_timestamp_seconds': 0,
                    'failed_timestamp_seconds': 0,
                    'wait_for_quiet_state': <dynamic>[
                      <String, dynamic>{'current_deadline_timestamp_seconds': 0}
                    ],
                    'latest_tally': <dynamic>[
                      <String, dynamic>{
                        'yes': 1000, 'no': 500, 'total': 1500,
                        'timestamp_seconds': 0,
                      }
                    ],
                    'proposal': <dynamic>[
                      <String, dynamic>{
                        'title': <String>['SNS ${100 - i}'],
                        'summary': 'Test.',
                        'url': <String>[],
                      }
                    ],
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

      // Send Next page.
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
