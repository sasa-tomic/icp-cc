@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

import '../../shared/ts_bundle_fixtures.dart';

void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();
  final String bundle = loadPilotBundle();

  /// Bundle that registers init+update but NOT view: used to prove the runtime
  /// surfaces a precise error when a lifecycle export is missing.
  const String missingViewBundle = '''
"use strict";
(() => {
  function init() { return { state: { count: 0 }, effects: [] }; }
  function update(msg, state) { return { state, effects: [] }; }
  globalThis.init = init;
  globalThis.update = update;
})();
''';

  const String malformedBundle = 'function {{{ this is not valid js';

  group('TS bundle lifecycle — POSITIVE', () {
    test('init yields the canonical initial state and no effects', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final obj = await runtime.init(script: bundle, budgetMs: 1000);
      expect(obj['ok'], true);
      final state = Map<String, dynamic>.from(obj['state'] as Map);
      expect(state['count'], 0);
      expect(state['items'], <dynamic>[]);
      expect(state['enabled'], true);
      expect(state['role'], 'user');
      expect(obj['effects'] as List<dynamic>, isEmpty);
    });

    test('view renders the initial state into a column UI tree', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final viewObj =
          await runtime.view(script: bundle, state: state, budgetMs: 1000);
      expect(viewObj['ok'], true);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      expect(ui['type'], 'column');
      final children = ui['children'] as List<dynamic>;
      expect(children, isNotEmpty);
      final firstSection = children.first as Map<String, dynamic>;
      expect(firstSection['type'], 'section');
    });

    test('update(inc) transitions state.count by exactly one', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);
      expect(state['count'], 0);

      final obj = await runtime.update(
          script: bundle, msg: {'type': 'inc'}, state: state, budgetMs: 1000);
      expect(obj['ok'], true);
      expect((obj['state'] as Map<String, dynamic>)['count'], 1);
      expect(obj['effects'] as List<dynamic>, isEmpty);
    });

    test('repeated update(inc) cycles are stable and accumulate correctly',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      var state = Map<String, dynamic>.from(
          (await runtime.init(script: bundle, budgetMs: 1000))['state'] as Map);

      for (var i = 1; i <= 5; i++) {
        final obj = await runtime.update(
            script: bundle,
            msg: {'type': 'inc'},
            state: state,
            budgetMs: 1000);
        expect(obj['ok'], true, reason: 'cycle $i should succeed');
        state = Map<String, dynamic>.from(obj['state'] as Map);
        expect(state['count'], i, reason: 'after $i inc messages');
      }
      expect(state['count'], 5);
    });

    test('update(set_name) writes the provided string into state.name',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final obj = await runtime.update(
          script: bundle,
          msg: {'type': 'set_name', 'value': 'Satoshi'},
          state: state,
          budgetMs: 1000);
      expect(obj['ok'], true);
      expect((obj['state'] as Map<String, dynamic>)['name'], 'Satoshi');
    });

    test('update(load_sample) emits an icp_batch effect with two calls',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final obj = await runtime.update(
          script: bundle,
          msg: {'type': 'load_sample'},
          state: state,
          budgetMs: 1000);
      expect(obj['ok'], true);
      final effects = obj['effects'] as List<dynamic>;
      expect(effects, hasLength(1));
      final effect = effects.first as Map<String, dynamic>;
      expect(effect['kind'], 'icp_batch');
      expect(effect['id'], 'load');
      final items = effect['items'] as List<dynamic>;
      expect(items, hasLength(2));
      final labels = items
          .map((e) => (e as Map<String, dynamic>)['label'] as String)
          .toSet();
      expect(labels, {'gov', 'ledger'});
    });

    test('effect/result roundtrip hydrates state.items from batch data',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final obj = await runtime.update(
          script: bundle,
          msg: {
            'type': 'effect/result',
            'id': 'load',
            'ok': true,
            'data': {
              'gov': {'pending': 3},
              'ledger': {'blocks': 10}
            }
          },
          state: state,
          budgetMs: 1000);
      expect(obj['ok'], true);
      final items = (obj['state'] as Map<String, dynamic>)['items'] as List;
      expect(items, hasLength(2));
      final titles =
          items.map((i) => (i as Map<String, dynamic>)['title']).toSet();
      expect(titles, {'gov', 'ledger'});
    });
  });

  group('TS bundle lifecycle — NEGATIVE', () {
    test('init on a malformed bundle throws StateError naming init', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      expect(
        () => runtime.init(script: malformedBundle, budgetMs: 1000),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('app init error'))),
      );
    });

    test('view on a bundle missing the view export throws StateError', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      expect(
        () => runtime.view(
            script: missingViewBundle,
            state: {'count': 0},
            budgetMs: 1000),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains("Required function 'view' not found"))),
      );
    });

    test('update on a malformed bundle throws StateError naming update',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      expect(
        () => runtime.update(
            script: malformedBundle,
            msg: {'type': 'inc'},
            state: {'count': 0},
            budgetMs: 1000),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('app update error'))),
      );
    });
  });

  group('TS bundle lifecycle — EDGE', () {
    test('update with an empty message object is a no-op fallthrough',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final obj = await runtime.update(
          script: bundle, msg: <String, dynamic>{}, state: state, budgetMs: 1000);
      expect(obj['ok'], true);
      final nextState = obj['state'] as Map<String, dynamic>;
      expect(nextState['count'], 0, reason: 'count must not change');
      expect(nextState['last'], <String, dynamic>{},
          reason: 'default branch stores the raw message in state.last');
    });

    test('update carries a large string payload through FFI unchanged', () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      final initObj = await runtime.init(script: bundle, budgetMs: 1000);
      final state = Map<String, dynamic>.from(initObj['state'] as Map);

      final big = 'x' * 10000;
      final obj = await runtime.update(
          script: bundle,
          msg: {'type': 'set_name', 'value': big},
          state: state,
          budgetMs: 1000);
      expect(obj['ok'], true);
      final name = (obj['state'] as Map<String, dynamic>)['name'] as String;
      expect(name.length, 10000);
      expect(name, big);
    });

    test('view reflects state mutated by a prior update (read-after-write)',
        () async {
      if (!nativeLibAvailable(loader)) {
        stdout.writeln('SKIP: libicp_core.so did not load in this environment');
        return;
      }
      final runtime = bootRuntime();
      var state = Map<String, dynamic>.from(
          (await runtime.init(script: bundle, budgetMs: 1000))['state'] as Map);
      state = Map<String, dynamic>.from((await runtime.update(
              script: bundle,
              msg: {'type': 'toggle_image', 'value': true},
              state: state,
              budgetMs: 1000))['state'] as Map);

      final viewObj =
          await runtime.view(script: bundle, state: state, budgetMs: 1000);
      expect(viewObj['ok'], true);
      final ui = viewObj['ui'] as Map<String, dynamic>;
      final sectionTitles = (ui['children'] as List<dynamic>)
          .map((c) => (c as Map<String, dynamic>)['props'] as Map<String, dynamic>?)
          .map((p) => p?['title'])
          .toSet();
      expect(sectionTitles, contains('Image Demo'),
          reason: 'showImage=true must surface the image section in the view');
    });
  });
}
