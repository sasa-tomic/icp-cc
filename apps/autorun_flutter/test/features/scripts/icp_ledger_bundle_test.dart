@TestOn('linux')
// Bundle-logic tests for 07_icp_ledger.js. Runs init/view/update through the
// REAL FFI runtime (libicp_core.so) and feeds canned effect/result envelopes
// whose shapes match the LIVE mainnet ICP ledger (proven via dfx:
//   symbol()   → record { symbol = "ICP" }
//   name()     → record { name = "Internet Computer" }
//   decimals() → record { decimals = 8 : nat32 }
// ). This is the proof that the always-working Dapps example decodes real
// mainnet canister replies correctly end-to-end.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

// The real well-known mainnet ICP ledger id + gateway — the bundle's defaults.
const String _ledgerId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _host = 'https://ic0.app';

Map<String, dynamic> _initialArg() =>
    <String, dynamic>{'backend_id': _ledgerId, 'host': _host};

/// Boot the bundle + run init once, returning the runtime and the resulting
/// state. Returns null (with a SKIP log) when libicp_core.so isn't available in
/// this environment — callers `return` on null.
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

void main() {
  final String ledgerBundle = loadLedgerBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('07_icp_ledger bundle', () {
    test(
        'init stores the mainnet canister id + host and AUTO-LOADS 3 read-only '
        'queries (UXR-6: works out of the box)', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final ScriptAppRuntime rt = bootRuntime();
      final obj = await rt.init(
          script: ledgerBundle, initialArg: _initialArg(), budgetMs: 1000);
      final state = Map<String, dynamic>.from(obj['state'] as Map);

      // The real mainnet ledger id + gateway are plumbed through verbatim.
      expect(state['backend_id'], _ledgerId);
      expect(state['host'], _host);

      // AUTO-LOAD: init emits the three read-only metadata queries so the tab
      // opens to real data. A regression to `effects: []` re-introduces an
      // empty screen + forced Refresh.
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(3));
      final methods = effects
          .map((e) => (e as Map<String, dynamic>)['method'] as String)
          .toSet();
      expect(methods, <String>{'symbol', 'name', 'decimals'});
      // ALL read-only: mode 0 (query), NOT authenticated (no signing needed).
      for (final dynamic e in effects) {
        final eff = e as Map<String, dynamic>;
        expect(eff['kind'], 'icp_call');
        expect(eff['mode'], 0, reason: '${eff['id']} must be a query');
        expect(eff['authenticated'], false,
            reason: '${eff['id']} must be read-only (no profile needed)');
        expect(eff['canister_id'], _ledgerId);
        expect(eff['host'], _host);
        expect(eff['args'], '()');
      }

      // The auto-load batch MUST equal a manual Refresh (DRY: init reuses
      // refreshEffects, not a hand-built duplicate).
      final refreshOut = await rt.update(
          script: ledgerBundle,
          msg: <String, dynamic>{'type': 'refresh'},
          state: state,
          budgetMs: 1000);
      expect(refreshOut['effects'], equals(effects));
    });

    test('decodes the live mainnet symbol/name/decimals replies (the proof)',
        () async {
      final boot = await _boot(ledgerBundle);
      if (boot == null) return;
      final ScriptAppRuntime rt = boot.$1;
      var state = boot.$2;

      // Feed the three replies in the EXACT shape the Rust FFI produces for the
      // live mainnet ledger (record { field: text/nat32 } → {field: value}).
      // symbol() → record { symbol = "ICP" }
      state = Map<String, dynamic>.from((await rt.update(
              script: ledgerBundle,
              msg: <String, dynamic>{
                'type': 'effect/result',
                'id': 'symbol',
                'ok': true,
                'data': <String, dynamic>{
                  'ok': true,
                  'result': <String, dynamic>{'symbol': 'ICP'},
                },
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);
      // name() → record { name = "Internet Computer" }
      state = Map<String, dynamic>.from((await rt.update(
              script: ledgerBundle,
              msg: <String, dynamic>{
                'type': 'effect/result',
                'id': 'name',
                'ok': true,
                'data': <String, dynamic>{
                  'ok': true,
                  'result': <String, dynamic>{'name': 'Internet Computer'},
                },
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);
      // decimals() → record { decimals = 8 : nat32 }
      state = Map<String, dynamic>.from((await rt.update(
              script: ledgerBundle,
              msg: <String, dynamic>{
                'type': 'effect/result',
                'id': 'decimals',
                'ok': true,
                'data': <String, dynamic>{
                  'ok': true,
                  'result': <String, dynamic>{'decimals': 8},
                },
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);

      expect(state['symbol'], 'ICP');
      expect(state['name'], 'Internet Computer');
      expect(state['decimals'], '8');
      expect(state['loaded'], true);

      // Render the view and assert the decoded metadata reaches the UI.
      final viewObj =
          await rt.view(script: ledgerBundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> texts = <String>[];
      _collectTexts(ui, texts);
      expect(texts, contains('Symbol: ICP'));
      expect(texts, contains('Name: Internet Computer'));
      expect(texts, contains('Decimals: 8'));
    });

    test('an ok:false result sets state.error LOUDLY with the method id',
        () async {
      final boot = await _boot(ledgerBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: ledgerBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'symbol',
            'ok': false,
            'error': 'canister unreachable',
          },
          state: state,
          budgetMs: 1000);
      final nextState = obj['state'] as Map<String, dynamic>;
      expect(nextState['error'], 'symbol: canister unreachable');
    });

    test(
        'a bridge-level ok:false envelope (data.ok=false) is surfaced loudly',
        () async {
      final boot = await _boot(ledgerBundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final obj = await rt.update(
          script: ledgerBundle,
          msg: <String, dynamic>{
            'type': 'effect/result',
            'id': 'decimals',
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
          'decimals: connection refused');
    });
  });
}
