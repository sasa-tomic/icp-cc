@TestOn('linux')
// End-to-end tests for [FrontendScaffoldGenerator]. Runs the generated bundle
// through the REAL FFI runtime (libicp_core.so) and asserts the init/view/update
// lifecycle behaves correctly: one section per method, zero-arg queries callable
// immediately, arg methods expose an editable Candid field, results render.
//
// Mirrors the proven pattern of icp_ledger_bundle_test.dart: the generated
// bundle is a first-class app-lifecycle bundle and is exercised the same way as
// the hand-written shipped examples.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/canister_method.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/frontend_scaffold_generator.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/ts_bundle_fixtures.dart';

const String _ledgerId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _host = 'https://ic0.app';

/// A realistic canister interface: three zero-arg queries (the live ledger
/// symbol/name/decimals) + one method that takes an argument
/// (account_balance_dfx: record { account: blob }).
List<CanisterMethod> _ledgerMethods() => <CanisterMethod>[
      const CanisterMethod(name: 'symbol', mode: 0, args: []),
      const CanisterMethod(name: 'name', mode: 0, args: []),
      const CanisterMethod(name: 'decimals', mode: 0, args: []),
      const CanisterMethod(
        name: 'account_balance_dfx',
        mode: 0,
        args: [
          CanisterArg(name: 'account', type: 'blob'),
        ],
        returnType: 'record { e8s: nat }',
      ),
      const CanisterMethod(
        name: 'transfer',
        mode: 1,
        args: [
          CanisterArg(name: 'to', type: 'principal'),
          CanisterArg(name: 'amount', type: 'nat'),
        ],
      ),
    ];

const FrontendScaffoldGenerator _gen = FrontendScaffoldGenerator();

/// Boot the generated bundle + run init once, returning the runtime + state.
/// Returns null (with a SKIP log) when libicp_core.so isn't available.
Future<(ScriptAppRuntime, Map<String, dynamic>)?> _boot(String script) async {
  final RustBridgeLoader loader = const RustBridgeLoader();
  if (!nativeLibAvailable(loader)) {
    stdout.writeln('SKIP: libicp_core.so did not load');
    return null;
  }
  final ScriptAppRuntime rt = bootRuntime();
  final Map<String, dynamic> state = Map<String, dynamic>.from((await rt.init(
          script: script,
          initialArg: <String, dynamic>{
            'backend_id': _ledgerId,
            'host': _host,
          },
          budgetMs: 1000))['state']
      as Map);
  return (rt, state);
}

/// Walk a UI tree and collect all node `type`s.
void _collectTypes(Map<String, dynamic> node, List<String> types) {
  final String type = (node['type'] as String?) ?? '';
  if (type.isNotEmpty) types.add(type);
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) _collectTypes(c, types);
  }
}

/// Walk a UI tree and collect all section titles.
void _collectSectionTitles(Map<String, dynamic> node, List<String> titles) {
  final String type = (node['type'] as String?) ?? '';
  if (type == 'section') {
    final props =
        (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    titles.add((props['title'] ?? '').toString());
  }
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) _collectSectionTitles(c, titles);
  }
}

/// Walk a UI tree and collect every text_field placeholder.
void _collectPlaceholders(Map<String, dynamic> node, List<String> phs) {
  final String type = (node['type'] as String?) ?? '';
  if (type == 'text_field') {
    final props =
        (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    phs.add((props['placeholder'] ?? '').toString());
  }
  final List<dynamic> children =
      (node['children'] as List<dynamic>?) ?? const <dynamic>[];
  for (final dynamic c in children) {
    if (c is Map<String, dynamic>) _collectPlaceholders(c, phs);
  }
}

void main() {
  group('FrontendScaffoldGenerator — structural (pure Dart)', () {
    test('embeds the canister id and default mainnet host', () {
      final bundle = _gen.generateBundle(
        canisterId: _ledgerId,
        methods: _ledgerMethods(),
      );
      expect(bundle, contains('ryjl3-tyaaa-aaaaa-aaaba-cai'));
      // Default host baked in when none provided.
      expect(bundle, contains('https://ic0.app'));
      expect(bundle, contains('"use strict";'));
      expect(bundle.trim().endsWith('})();'), isTrue);
    });

    test('respects an explicit host override', () {
      final bundle = _gen.generateBundle(
        canisterId: _ledgerId,
        methods: _ledgerMethods(),
        host: 'http://127.0.0.1:4943',
      );
      expect(bundle, contains('http://127.0.0.1:4943'));
    });

    test('zero-arg methods get hasArgs:false and defaultArgs "()"', () {
      final bundle = _gen.generateBundle(
        canisterId: _ledgerId,
        methods: const [
          CanisterMethod(name: 'symbol', mode: 0, args: []),
        ],
      );
      expect(bundle, contains('"name":"symbol"'));
      expect(bundle, contains('"hasArgs":false'));
      expect(bundle, contains('"defaultArgs":"()"'));
    });

    test('methods with args get hasArgs:true and a typed argsHint', () {
      final bundle = _gen.generateBundle(
        canisterId: _ledgerId,
        methods: const [
          CanisterMethod(
            name: 'transfer',
            mode: 1,
            args: [
              CanisterArg(name: 'to', type: 'principal'),
              CanisterArg(name: 'amount', type: 'nat'),
            ],
            returnType: 'record { block_height: nat64 }',
          ),
        ],
      );
      expect(bundle, contains('"hasArgs":true'));
      expect(bundle, contains('(to: principal, amount: nat)'));
      expect(bundle, contains('record { block_height: nat64 }'));
    });

    test('empty methods list yields a valid (empty) bundle', () {
      final bundle = _gen.generateBundle(
        canisterId: _ledgerId,
        methods: const [],
      );
      expect(bundle, contains('var METHODS = [];'));
      expect(bundle.trim().endsWith('})();'), isTrue);
    });
  });

  group('FrontendScaffoldGenerator — runtime (REAL FFI)', () {
    final String bundle = _gen.generateBundle(
      canisterId: _ledgerId,
      methods: _ledgerMethods(),
    );
    final RustBridgeLoader loader = const RustBridgeLoader();

    test('init stores backend_id/host and prefills argText per method',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }
      final boot = await _boot(bundle);
      if (boot == null) return;
      final state = boot.$2;

      expect(state['backend_id'], _ledgerId);
      expect(state['host'], _host);
      expect(state['auth'], false);
      final argText = state['argText'] as Map;
      // Zero-arg methods prefill with "()"; arg method gets a best-effort tuple.
      expect(argText['symbol'], '()');
      expect(argText['account_balance_dfx'], '(null)');
      expect(argText['transfer'], '(principal "aaaaa-aa", 0)');
    });

    test('view renders a section per method + an auth toggle', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;

      final List<String> types = [];
      _collectTypes(ui, types);
      expect(types, containsAll(<String>['column', 'text', 'toggle', 'section', 'button']));

      final List<String> titles = [];
      _collectSectionTitles(ui, titles);
      // Every method gets its own section.
      expect(titles, contains('symbol (query)'));
      expect(titles, contains('decimals (query)'));
      expect(titles, contains('account_balance_dfx (query) -> record { e8s: nat }'));
      expect(titles, contains('transfer (update)'));
    });

    test('zero-arg sections have NO text_field; arg sections DO', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final viewObj =
          await rt.view(script: bundle, state: state, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;

      final List<String> placeholders = [];
      _collectPlaceholders(ui, placeholders);
      // Only the two arg-taking methods contribute a text_field placeholder.
      expect(placeholders, hasLength(2));
      expect(placeholders, contains('(account: blob)'));
      expect(placeholders, contains('(to: principal, amount: nat)'));
    });

    test('call emits an icp_call effect with the right shape', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final out = await rt.update(
        script: bundle,
        msg: <String, dynamic>{'type': 'call', 'method': 'decimals'},
        state: state,
        budgetMs: 1000,
      );
      final effects = out['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final eff = effects.first as Map<String, dynamic>;
      expect(eff['kind'], 'icp_call');
      expect(eff['method'], 'decimals');
      expect(eff['mode'], 0);
      expect(eff['canister_id'], _ledgerId);
      expect(eff['host'], _host);
      expect(eff['args'], '()');
      expect(eff['authenticated'], false);
      // The effect id matches the method name.
      expect(eff['id'], 'decimals');
    });

    test('set_auth flips the authenticated flag on subsequent calls', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      var s = state;
      s = Map<String, dynamic>.from((await rt.update(
              script: bundle,
              msg: <String, dynamic>{'type': 'set_auth', 'value': true},
              state: s,
              budgetMs: 1000))['state']
          as Map);
      expect(s['auth'], true);

      final out = await rt.update(
        script: bundle,
        msg: <String, dynamic>{'type': 'call', 'method': 'transfer'},
        state: s,
        budgetMs: 1000,
      );
      final eff = (out['effects'].first as Map<String, dynamic>);
      expect(eff['authenticated'], true);
      expect(eff['mode'], 1); // update
      // Args come from the prefilled argText for transfer.
      expect(eff['args'], '(principal "aaaaa-aa", 0)');
    });

    test('set_args updates the candid args used by the next call', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      var s = state;
      s = Map<String, dynamic>.from((await rt.update(
              script: bundle,
              msg: <String, dynamic>{
                'type': 'set_args',
                'method': 'account_balance_dfx',
                'value': 'record { account = blob "ab" }',
              },
              state: s,
              budgetMs: 1000))['state']
          as Map);
      expect((s['argText'] as Map)['account_balance_dfx'],
          'record { account = blob "ab" }');

      final out = await rt.update(
        script: bundle,
        msg: <String, dynamic>{
          'type': 'call',
          'method': 'account_balance_dfx'
        },
        state: s,
        budgetMs: 1000,
      );
      final eff = (out['effects'].first as Map<String, dynamic>);
      expect(eff['args'], 'record { account = blob "ab" }');
    });

    test('a successful effect/result renders in result_display', () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final s = Map<String, dynamic>.from((await rt.update(
              script: bundle,
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

      final results = s['results'] as Map;
      expect(results['symbol'], isA<Map>());
      expect((results['symbol'] as Map)['ok'], true);
      expect((results['symbol'] as Map)['value'], {'symbol': 'ICP'});
      // loading cleared.
      expect((s['loading'] as Map)['symbol'], false);

      // The view surfaces a result_display node for symbol.
      final viewObj = await rt.view(script: bundle, state: s, budgetMs: 1000);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final List<String> types = [];
      _collectTypes(ui, types);
      expect(types, contains('result_display'));
    });

    test('a failed effect/result renders as an error in result_display',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final s = Map<String, dynamic>.from((await rt.update(
              script: bundle,
              msg: <String, dynamic>{
                'type': 'effect/result',
                'id': 'symbol',
                'ok': false,
                'error': 'canister unreachable',
              },
              state: state,
              budgetMs: 1000))['state']
          as Map);

      final results = s['results'] as Map;
      expect((results['symbol'] as Map)['ok'], false);
      expect((results['symbol'] as Map)['error'], 'canister unreachable');
    });

    test('a bridge-level ok:false envelope (data.ok=false) is surfaced loudly',
        () async {
      final boot = await _boot(bundle);
      if (boot == null) return;
      final (rt, state) = boot;

      final s = Map<String, dynamic>.from((await rt.update(
              script: bundle,
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
              budgetMs: 1000))['state']
          as Map);

      final results = s['results'] as Map;
      expect((results['decimals'] as Map)['ok'], false);
      expect((results['decimals'] as Map)['error'], 'connection refused');
    });
  });
}
