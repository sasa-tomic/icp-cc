// R-3 WU-3 — jsApp lifecycle golden vectors (parity bar).
//
// Mirrors the `js_app_init`/`view`/`update` test suite in
// `crates/icp_core/src/js_engine.rs:947-1100` (`app_init_view_update_roundtrip`,
// `app_init_timeout`, `app_view_invalid_state_json`,
// `app_update_invalid_msg_json`, `sample_app_default_works`) PLUS the shipped
// `lib/examples/01_hello_world.js` run init→view→update.
//
// Each vector's [run] drives a (possibly multi-step) lifecycle through the REAL
// [WebQuickJsEngine] and returns a Map of named checkpoint envelopes; [assertion]
// inspects those checkpoints (`null` = pass, else a failure message). The
// browser probe (`web_probe_parity_main.dart`) executes them; the VM contract
// test pins the catalogue by name.
import 'dart:convert';

import 'js_app_engine_interface.dart';

/// One jsApp lifecycle golden vector.
class JsAppGoldenVector {
  const JsAppGoldenVector({
    required this.name,
    required this.run,
    required this.assertion,
  });
  final String name;

  /// Drives the lifecycle; returns named checkpoint envelopes (decoded).
  final Map<String, dynamic> Function(JsAppEngine engine) run;

  /// `null` = pass, else a failure message. Inspects [run]'s checkpoints.
  final String? Function(Map<String, dynamic> checkpoints) assertion;
}

/// The catalogue. Consumed by the parity probe + VM contract test.
final List<JsAppGoldenVector> jsAppGoldenVectors = <JsAppGoldenVector>[
  // js_engine.rs:947-982 — init→view→update roundtrip.
  JsAppGoldenVector(
    name: 'app_init_view_update_roundtrip',
    run: (engine) => _roundtrip(
      engine,
      ScriptLifecycles.roundtrip,
      initArg: '{"start":1}',
      messages: const <String>['{"type":"inc"}'],
    ),
    assertion: (cp) {
      final init = cp['init'] as Map?;
      if (init == null || init['ok'] != true) return 'init not ok: $init';
      if (_path(init, ['state', 'count']) != 1) return 'init count != 1';
      final view = cp['view'] as Map?;
      if (view == null || view['ok'] != true) return 'view not ok: $view';
      if (_path(view, ['ui', 'type']) != 'column') return 'view ui.type != column';
      final upd = cp['update_0'] as Map?;
      if (upd == null || upd['ok'] != true) return 'update not ok: $upd';
      if (_path(upd, ['state', 'count']) != 2) return 'update count != 2';
      if (upd['effects'] is! List) return 'update effects not a list';
      return null;
    },
  ),

  // js_engine.rs:984-1004 — init with an infinite loop must hit the deadline.
  JsAppGoldenVector(
    name: 'app_init_timeout',
    run: (engine) {
      final out = engine.jsAppInit(ScriptLifecycles.initTimeout,
          budgetMs: 1);
      return <String, dynamic>{'init': jsonDecode(out)};
    },
    assertion: (cp) {
      final init = cp['init'] as Map?;
      if (init == null || init['ok'] == true) return 'init should have failed';
      final err = (init['error'] ?? '').toString().toLowerCase();
      if (!err.contains('timeout') && !err.contains('execution')) {
        return 'error should be a timeout, got: $err';
      }
      return null;
    },
  ),

  // js_engine.rs:1006-1017 — malformed state JSON.
  JsAppGoldenVector(
    name: 'app_view_invalid_state_json',
    run: (engine) {
      final out = engine.jsAppView(ScriptLifecycles.benign,
          stateJson: 'not-json', budgetMs: 50);
      return <String, dynamic>{'view': jsonDecode(out)};
    },
    assertion: (cp) {
      final view = cp['view'] as Map?;
      if (view == null || view['ok'] == true) return 'view should have failed';
      if (!(view['error'].toString().contains('invalid state JSON'))) {
        return "error should contain 'invalid state JSON': ${view['error']}";
      }
      return null;
    },
  ),

  // js_engine.rs:1019-1030 — malformed msg JSON (validated before state).
  JsAppGoldenVector(
    name: 'app_update_invalid_msg_json',
    run: (engine) {
      final out = engine.jsAppUpdate(ScriptLifecycles.benign,
          msgJson: 'not-json', stateJson: '{}', budgetMs: 50);
      return <String, dynamic>{'update': jsonDecode(out)};
    },
    assertion: (cp) {
      final upd = cp['update'] as Map?;
      if (upd == null || upd['ok'] == true) return 'update should have failed';
      if (!(upd['error'].toString().contains('invalid msg JSON'))) {
        return "error should contain 'invalid msg JSON': ${upd['error']}";
      }
      return null;
    },
  ),

  // js_engine.rs:1032-1100 — the bigger sample app, incl. an icp_batch effect.
  JsAppGoldenVector(
    name: 'sample_app_default_works',
    run: (engine) {
      final checkpoints = <String, dynamic>{};
      final initOut =
          engine.jsAppInit(ScriptLifecycles.sampleApp, budgetMs: 200);
      checkpoints['init'] = jsonDecode(initOut);
      final state = jsonEncode((checkpoints['init'] as Map)['state']);
      checkpoints['view'] =
          jsonDecode(engine.jsAppView(ScriptLifecycles.sampleApp,
              stateJson: state, budgetMs: 200));
      checkpoints['update_inc'] = jsonDecode(engine.jsAppUpdate(
          ScriptLifecycles.sampleApp,
          msgJson: '{"type":"inc"}',
          stateJson: state,
          budgetMs: 200));
      checkpoints['update_load_sample'] = jsonDecode(engine.jsAppUpdate(
          ScriptLifecycles.sampleApp,
          msgJson: '{"type":"load_sample"}',
          stateJson: state,
          budgetMs: 200));
      return checkpoints;
    },
    assertion: (cp) {
      final init = cp['init'] as Map;
      if (init['ok'] != true) return 'init not ok: $init';
      if (_path(init, ['state', 'count']) != 0) return 'init count != 0';
      final view = cp['view'] as Map;
      if (view['ok'] != true) return 'view not ok: $view';
      if (_path(view, ['ui', 'type']) != 'column') return 'view ui.type != column';
      final inc = cp['update_inc'] as Map;
      if (inc['ok'] != true) return 'update_inc not ok';
      if (_path(inc, ['state', 'count']) != 1) return 'update_inc count != 1';
      final load = cp['update_load_sample'] as Map;
      if (load['ok'] != true) return 'update_load_sample not ok';
      final effects = load['effects'] as List?;
      if (effects == null || effects.isEmpty) return 'no effects emitted';
      final eff0 = effects.first as Map;
      if (eff0['kind'] != 'icp_batch') return "effects[0].kind != 'icp_batch'";
      if ((eff0['items'] as List?)?.length != 2) return 'items len != 2';
      return null;
    },
  ),

  // The shipped lib/examples/01_hello_world.js — init→view→update produces the
  // same UI tree as native. Proves a REAL bundle works end-to-end on Web.
  JsAppGoldenVector(
    name: 'hello_world_bundle_init_view_update',
    run: (engine) {
      final checkpoints = <String, dynamic>{};
      final initOut = engine.jsAppInit(ScriptLifecycles.helloWorld);
      checkpoints['init'] = jsonDecode(initOut);
      final state = jsonEncode((checkpoints['init'] as Map)['state']);
      checkpoints['view'] = jsonDecode(
          engine.jsAppView(ScriptLifecycles.helloWorld, stateJson: state));
      checkpoints['update_inc'] = jsonDecode(engine.jsAppUpdate(
          ScriptLifecycles.helloWorld,
          msgJson: '{"type":"inc"}',
          stateJson: state));
      // Drive set_name, then re-view to confirm the greeting updates.
      final nameState = jsonEncode((checkpoints['update_inc'] as Map)['state']);
      checkpoints['update_set_name'] = jsonDecode(engine.jsAppUpdate(
          ScriptLifecycles.helloWorld,
          msgJson: '{"type":"set_name","value":"Web"}',
          stateJson: nameState));
      final finalState =
          jsonEncode((checkpoints['update_set_name'] as Map)['state']);
      checkpoints['view_named'] = jsonDecode(engine.jsAppView(
          ScriptLifecycles.helloWorld,
          stateJson: finalState));
      return checkpoints;
    },
    assertion: (cp) {
      final init = cp['init'] as Map;
      if (init['ok'] != true) return 'init not ok';
      if (_path(init, ['state', 'count']) != 0) return 'init count != 0';
      if (_path(init, ['state', 'name']) != '') return 'init name != ""';
      final view = cp['view'] as Map;
      if (view['ok'] != true) return 'view not ok';
      if (_path(view, ['ui', 'type']) != 'column') return 'view ui.type != column';
      // First text child greets "Hello, world!" (empty name).
      final greeting = _firstTextText(view['ui']);
      if (greeting != 'Hello, world!') return 'greeting != Hello, world! ($greeting)';
      final inc = cp['update_inc'] as Map;
      if (_path(inc, ['state', 'count']) != 1) return 'update_inc count != 1';
      final setName = cp['update_set_name'] as Map;
      if (_path(setName, ['state', 'name']) != 'Web') return "set_name != 'Web'";
      final viewNamed = cp['view_named'] as Map;
      final namedGreeting = _firstTextText(viewNamed['ui']);
      if (namedGreeting != 'Hello, Web!') {
        return 'named greeting != Hello, Web! ($namedGreeting)';
      }
      return null;
    },
  ),
];

// ── shared lifecycle driver ─────────────────────────────────────────────────

/// Run init→view→update(+N messages) and return the decoded checkpoint map.
Map<String, dynamic> _roundtrip(
  JsAppEngine engine,
  String script, {
  String? initArg,
  required List<String> messages,
}) {
  final checkpoints = <String, dynamic>{};
  final initOut = engine.jsAppInit(script, jsonArg: initArg, budgetMs: 200);
  checkpoints['init'] = jsonDecode(initOut);
  final state = jsonEncode((checkpoints['init'] as Map)['state']);
  checkpoints['view'] =
      jsonDecode(engine.jsAppView(script, stateJson: state, budgetMs: 200));
  for (var i = 0; i < messages.length; i++) {
    checkpoints['update_$i'] = jsonDecode(engine.jsAppUpdate(script,
        msgJson: messages[i], stateJson: state, budgetMs: 200));
  }
  return checkpoints;
}

Object? _path(dynamic v, List<String> keys) {
  dynamic cur = v;
  for (final k in keys) {
    if (cur is! Map) return null;
    cur = cur[k];
  }
  return cur;
}

/// The `props.text` of the FIRST `text`-typed child in a UI tree (or null).
/// Used to assert the hello-world greeting.
String? _firstTextText(dynamic ui) {
  if (ui is! Map) return null;
  final children = ui['children'];
  if (children is List) {
    for (final child in children) {
      if (child is Map && child['type'] == 'text') {
        final props = child['props'];
        if (props is Map) return props['text']?.toString();
      }
    }
  }
  return null;
}

// ── bundle sources (verbatim from the Rust tests / shipped examples) ────────

/// The exact script bodies the Rust lifecycle tests use + the shipped
/// `lib/examples/01_hello_world.js`. Kept inline so the probe (a Flutter web
/// build) is self-contained — no asset fetch — and the parity vectors are
/// reproducible from this one file.
class ScriptLifecycles {
  const ScriptLifecycles._();

  /// js_engine.rs:948-964.
  static const String roundtrip = r'''
            function init(arg) {
                var start = (arg && arg.start) || 0;
                return { state: { count: start, last: null }, effects: [] };
            }
            function view(state) {
                return { type: "column", props: {}, children: [
                    { type: "text", props: { text: String(state.count) } }
                ] };
            }
            function update(msg, state) {
                var t = (msg && msg.type) || "";
                if (t === "inc") { state.count = (state.count || 0) + 1; }
                state.last = msg;
                return { state: state, effects: [] };
            }
        ''';

  /// js_engine.rs:986-994.
  static const String initTimeout = r'''
            function init(arg) {
                var i = 0;
                while (true) { i = i + 1; }
                return { state: {}, effects: [] };
            }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''';

  /// A benign script used by the invalid-JSON view/update vectors
  /// (js_engine.rs:1008-1012 / 1021-1025). Defines all three exports.
  static const String benign = r'''
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "text", props: { text: "ok" } }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        ''';

  /// js_engine.rs:1034-1072.
  static const String sampleApp = r'''
            function init(arg) {
                return {
                    state: { count: 0, items: [], last: null },
                    effects: []
                };
            }
            function view(state) {
                var children = [{
                    type: "section", props: { title: "Sample UI-enabled Script" }, children: [
                        { type: "text", props: { text: "Counter: " + String(state.count || 0) } },
                        { type: "row", children: [
                            { type: "button", props: { label: "Increment", onPress: { type: "inc" } } },
                            { type: "button", props: { label: "Load ICP samples", onPress: { type: "load_sample" } } }
                        ] }
                    ]
                }];
                var items = state.items || [];
                if (Array.isArray(items) && items.length > 0) {
                    children.push({ type: "section", props: { title: "Loaded results" }, children: [
                        { type: "list", props: { items: items } }
                    ] });
                }
                return { type: "column", children: children };
            }
            function update(msg, state) {
                var t = (msg && msg.type) || "";
                if (t === "inc") {
                    state.count = (state.count || 0) + 1;
                    return { state: state, effects: [] };
                }
                if (t === "load_sample") {
                    var gov = { label: "gov", kind: 0, canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai", method: "get_pending_proposals", args: "()" };
                    var ledger = { label: "ledger", kind: 0, canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai", method: "query_blocks", args: '{"start":0,"length":3}' };
                    return { state: state, effects: [{ kind: "icp_batch", id: "load", items: [gov, ledger] }] };
                }
                state.last = msg;
                return { state: state, effects: [] };
            }
        ''';

  /// The shipped `apps/autorun_flutter/lib/examples/01_hello_world.js` —
  /// verbatim. Proves a REAL bundle runs init→view→update on Web.
  static const String helloWorld = r'''
"use strict";
(() => {
  function init() {
    return { state: { count: 0, name: "" }, effects: [] };
  }

  function view(state) {
    const count = state.count || 0;
    const name = typeof state.name === "string" ? state.name : "";
    const greeting = name.length > 0 ? "Hello, " + name + "!" : "Hello, world!";
    return {
      type: "column",
      children: [
        { type: "text", props: { text: greeting } },
        { type: "text", props: { text: "Count: " + count } },
        {
          type: "row",
          children: [
            { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
            { type: "button", props: { label: "Reset", on_press: { type: "reset" } } },
          ],
        },
        {
          type: "text_field",
          props: {
            label: "Your name",
            placeholder: "Enter your name",
            value: name,
            on_change: { type: "set_name" },
          },
        },
      ],
    };
  }

  function update(msg, state) {
    const t = (msg && msg.type) || "";
    if (t === "inc") {
      return { state: { ...state, count: (state.count || 0) + 1 }, effects: [] };
    }
    if (t === "reset") {
      return { state: { ...state, count: 0 }, effects: [] };
    }
    if (t === "set_name") {
      return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''';
}
