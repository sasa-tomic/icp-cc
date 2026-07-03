@TestOn('linux')
// Bundle-logic tests for 06_icp_poll.js. Runs init/view/update through the
// REAL FFI runtime (libicp_core.so) and feeds canned effect/result envelopes
// whose shapes match the live canister (captured in live_canister_auth_test).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

const String _backendId = 'uxrrr-q7777-77774-qaaaq-cai';
const String _host = 'http://127.0.0.1:4943';

Map<String, dynamic> _initialArg() =>
    <String, dynamic>{'backend_id': _backendId, 'host': _host};

/// Boot the bundle + run init once, returning the runtime and the resulting
/// state. Returns null (with a SKIP log) when libicp_core.so isn't available in
/// this environment — callers `return` on null. Collapses the skip-guard +
/// boot + init + state-extract block that would otherwise repeat per test.
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

/// Walk a UI tree and collect every text node's text + every button's label.
void _collectTextsAndButtons(Map<String, dynamic> node,
    List<String> texts, List<String> buttonLabels) {
  final String type = (node['type'] as String?) ?? '';
  final Map<String, dynamic> props =
      (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  if (type == 'text') {
    texts.add((props['text'] ?? '').toString());
  }
  if (type == 'button') {
    buttonLabels.add((props['label'] ?? '').toString());
  }
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) {
      _collectTextsAndButtons(c, texts, buttonLabels);
    }
  }
}

void main() {
  final String pollBundle = loadPollBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('06_icp_poll bundle', () {
    test('init stores backend_id/host and starts empty', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      // This test inspects init's output directly, so it does its own boot
      // (the _boot() helper below consumes init and returns only state+rt).
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: pollBundle, initialArg: _initialArg(), budgetMs: 1000);
      final state = Map<String, dynamic>.from(obj['state'] as Map);
      expect(state['backend_id'], _backendId);
      expect(state['host'], _host);
      expect(state['principal'], '');
      expect(state['polls'], isEmpty);
      expect(obj['effects'] as List, isEmpty);
    });

    test('refresh emits whoami(auth) + listPolls(anon) with the right target',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: pollBundle, msg: {'type': 'refresh'}, state: state, budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(2));

      final whoami = effects.firstWhere(
          (e) => (e as Map<String, dynamic>)['id'] == 'whoami') as Map;
      expect(whoami['mode'], 0); // query
      expect(whoami['canister_id'], _backendId);
      expect(whoami['host'], _host);
      expect(whoami['method'], 'whoami');
      expect(whoami['authenticated'], true);

      final listPolls = effects.firstWhere(
          (e) => (e as Map<String, dynamic>)['id'] == 'listPolls') as Map;
      expect(listPolls['mode'], 0);
      expect(listPolls['canister_id'], _backendId);
      expect(listPolls['host'], _host);
      expect(listPolls['method'], 'listPolls');
      expect(listPolls['authenticated'], false); // anon
    });

    test('vote emits an authenticated UPDATE effect with mode 1', () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: pollBundle,
          msg: {'type': 'vote', 'pollId': '3', 'optionIndex': 1},
          state: state,
          budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['id'], 'vote');
      expect(eff['mode'], 1); // update
      expect(eff['authenticated'], true);
      expect(eff['canister_id'], _backendId);
      // `: nat` annotation required by the canister.
      expect(eff['args'], '("3", 1 : nat)');
    });

    test('listPolls effect/result builds poll UI with vote buttons + tally',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      // listPolls + getTally each return an updated state we re-feed.
      var state = boot.$2;

      // Feed listPolls success (real shape: data.ok=true, data.result=[polls]).
      // Principal serializes as a STRING in the `creator` field.
      final listOut = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'listPolls',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <dynamic>[
                <String, dynamic>{
                  'id': '3',
                  'question': 'Best language?',
                  'options': <String>['Rust', 'Motoko'],
                  'creator': 'oiulm-7yrmr-h77zd-olex7-wywh3-vp366-3dolp-s5p3r-5pv7g-htte3-7qe',
                },
              ],
            },
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(listOut['state'] as Map);
      expect((state['polls'] as List).length, 1);
      // listPolls success fans out a getTally effect per poll.
      final tallyFx = listOut['effects'] as List<dynamic>;
      expect(tallyFx, hasLength(1));
      expect((tallyFx.first as Map)['method'], 'getTally');
      expect((tallyFx.first as Map)['id'], 'tally:3');

      // Feed getTally success (real shape: vec nat → numeric strings).
      final tallyOut = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'tally:3',
            'ok': true,
            'data': <String, dynamic>{
              'ok': true,
              'result': <String>['7', '2'],
            },
          },
          state: state,
          budgetMs: 1000);
      state = Map<String, dynamic>.from(tallyOut['state'] as Map);
      final tallies = state['tallies'] as Map<String, dynamic>;
      expect(tallies['3'], <num>[7, 2]);

      // Render the view and assert the poll UI nodes appear.
      final viewObj =
          await rt.view(script: pollBundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      final List<String> buttonLabels = <String>[];
      _collectTextsAndButtons(ui, texts, buttonLabels);

      expect(texts, contains('Best language?'));
      expect(buttonLabels, containsAll(<String>['Rust', 'Motoko']));
      // Tally values are rendered as text nodes.
      expect(texts, contains('7'));
      expect(texts, contains('2'));
    });

    test('an ok:false result sets state.error LOUDLY', () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'listPolls',
            'ok': false,
            'error': 'permission denied',
          },
          state: state,
          budgetMs: 1000);
      expect((obj['state'] as Map<String, dynamic>)['error'],
          contains('permission denied'));
    });

    test('create validates inputs client-side (LOUD error, no effect emitted)',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      // Empty question + empty options → question check fires first; no effect.
      final obj = await rt.update(
          script: pollBundle, msg: {'type': 'create'}, state: state, budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      // Verify the SPECIFIC message so a regression that swaps branches or
      // drops the text is caught — not just "some non-empty string".
      expect((obj['state'] as Map<String, dynamic>)['error'],
          'Question must not be empty');
    });

    test('create with one option is rejected at the ≥2 boundary', () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;
      // Non-empty question but only ONE option → options check must fire.
      state['newQuestion'] = 'Favourite colour?';
      state['newOptions'] = 'red';

      final obj = await rt.update(
          script: pollBundle, msg: {'type': 'create'}, state: state, budgetMs: 1000);
      expect((obj['effects'] as List), isEmpty);
      expect(
          (obj['state'] as Map<String, dynamic>)['error'],
          'Provide at least 2 options (comma-separated)');
    });

    test('create with exactly two options emits an authed createPoll UPDATE',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;
      // Boundary: exactly 2 options is the minimum legal create.
      state['newQuestion'] = 'Tea or coffee?';
      state['newOptions'] = 'Tea, Coffee';

      final obj = await rt.update(
          script: pollBundle, msg: {'type': 'create'}, state: state, budgetMs: 1000);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['id'], 'create');
      expect(eff['method'], 'createPoll');
      expect(eff['mode'], 1); // update
      expect(eff['authenticated'], true);
      // Textual Candid record + vec literal, with escaping applied.
      expect(eff['args'], '("Tea or coffee?", vec { "Tea"; "Coffee" })');
      // Inputs are cleared after a successful (client-side) create so the form
      // doesn't double-submit.
      final nextState = obj['state'] as Map<String, dynamic>;
      expect(nextState['newQuestion'], '');
      expect(nextState['newOptions'], '');
      expect(nextState['error'], '');
    });

    test('whoami missing-auth error keeps principal empty (view-only, NOT loud)',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      // Host delivers the exact missing-auth envelope (mirrors
      // _kMissingAuthMessage in script_app_host.dart) — the only whoami failure
      // that is treated as expected/non-fatal.
      final obj = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'whoami',
            'ok': false,
            'error': 'authenticated call requested but no active profile keypair',
          },
          state: state,
          budgetMs: 1000);
      final nextState = obj['state'] as Map<String, dynamic>;
      expect(nextState['principal'], '');
      // Critical: this branch must NOT raise a loud error — the user simply
      // stays view-only. A regression that surfaces this as an error would spam
      // every keyless session on refresh.
      expect(nextState['error'], '');
    });

    test('whoami OTHER error is surfaced LOUDLY with a whoami: prefix',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      // Any whoami failure that is NOT missing-auth (replica down, canister
      // fault, ...) must be loud so the user knows the view is stale.
      final obj = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'whoami',
            'ok': false,
            'error': 'replica unreachable',
          },
          state: state,
          budgetMs: 1000);
      expect((obj['state'] as Map<String, dynamic>)['error'],
          'whoami: replica unreachable');
    });

    test('getTally error surfaces a "tally <id>:" prefix in state.error (M1 fix)',
        () async {
      final boot = await _boot(pollBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      // A failed tally (e.g. transient read_state error) must NOT be swallowed —
      // the bundle prefixes it with the poll id so the user can see WHICH poll
      // failed. This is the M1 loud-error fix.
      final obj = await rt.update(
          script: pollBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'tally:7',
            'ok': false,
            'error': 'network down',
          },
          state: state,
          budgetMs: 1000);
      expect((obj['state'] as Map<String, dynamic>)['error'],
          'tally 7: network down');
    });
  });
}
