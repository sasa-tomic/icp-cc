import 'dart:convert';

import '../models/canister_method.dart';

/// Generates a runnable TS/QuickJS app bundle (the `init`/`view`/`update`
/// contract consumed by [ScriptAppHost]) from a canister's Candid interface.
///
/// Phase 1 of the canister-frontend vision (`docs/specs/2026-07-23-canister-
/// frontend-vision.md`): given any canister id + its parsed Candid methods,
/// emit a starter UI — one callable section per method (zero-arg query methods
/// work immediately; methods with args get an editable Candid args field), with
/// a per-method result display and an optional "sign as me" toggle.
///
/// The output is a complete, self-contained bundle string ready to open in the
/// [ScriptAppHost] / script editor. It is a **starter** — users refine it into
/// their real dapp UI.
class FrontendScaffoldGenerator {
  const FrontendScaffoldGenerator();

  /// Emits the full IIFE bundle exporting `globalThis.init/view/update`.
  ///
  /// [canisterId] and [methods] are required; [host] is optional (defaults to
  /// the mainnet gateway when null/empty — baked into the bundle so the user
  /// can override at runtime via the arg, but the starter works out of the box).
  String generateBundle({
    required String canisterId,
    required List<CanisterMethod> methods,
    String? host,
  }) {
    final String safeHost = (host ?? '').trim();
    final String bakedHost =
        safeHost.isEmpty ? _kDefaultMainnetHost : safeHost;
    final String methodsJson = _methodsJson(methods, canisterId, bakedHost);

    final StringBuffer out = StringBuffer();
    out.writeln('// Auto-generated frontend scaffold for canister $canisterId.');
    out.writeln('// One callable section per Candid method. Zero-arg query');
    out.writeln('// methods work immediately; methods with args expose an');
    out.writeln('// editable Candid args field. Refine this starter into your');
    out.writeln('// real dapp UI.');
    out.writeln('"use strict";');
    out.writeln('(() => {');
    out.writeln('  var CANISTER_ID = ${json.encode(canisterId)};');
    out.writeln('  var HOST = ${json.encode(bakedHost)};');
    out.writeln('  var METHODS = $methodsJson;');
    out.writeln();
    out.write(_kBundleBody);
    out.writeln('})();');
    return out.toString();
  }

  String _methodsJson(
      List<CanisterMethod> methods, String canisterId, String host) {
    if (methods.isEmpty) {
      return '[]';
    }
    final entries = methods.map((m) {
      final hasArgs = m.args.isNotEmpty;
      return json.encode({
        'name': m.name,
        'mode': m.mode,
        'hasArgs': hasArgs,
        'defaultArgs': hasArgs ? _defaultArgs(m.args) : '()',
        'argsHint': hasArgs ? _argsHint(m.args) : '()',
        'returnType': m.returnType ?? '',
      });
    }).join(',\n    ');
    return '[\n    $entries\n  ]';
  }

  /// Builds a best-effort Candid text tuple of type-based defaults for the
  /// given args. A starter only — the user refines as needed. Conservative:
  /// unknown / opt / composite types fall back to `null` (valid for opt args).
  String _defaultArgs(List<CanisterArg> args) {
    final parts = args.map((a) => _candidDefault(a.type)).toList();
    return '(${parts.join(', ')})';
  }

  String _candidDefault(String type) {
    final t = type.toLowerCase().trim();
    if (t.contains('text') || t.contains('string')) return '""';
    if (t.contains('bool')) return 'false';
    if (_isNumericType(t)) return '0';
    if (t.contains('principal')) return 'principal "aaaaa-aa"';
    if (t == 'null') return 'null';
    return 'null';
  }

  bool _isNumericType(String t) {
    const numeric = {'nat', 'int', 'nat8', 'nat16', 'nat32', 'nat64',
        'int8', 'int16', 'int32', 'int64', 'float32', 'float64'};
    return numeric.contains(t) || t.startsWith('nat') || t.startsWith('int');
  }

  /// Human-readable type signature shown as the text-field placeholder, e.g.
  /// `(account: principal, amount: nat)`.
  String _argsHint(List<CanisterArg> args) {
    final parts =
        args.map((a) => '${a.name}: ${a.type}${a.optional ? ' (opt)' : ''}');
    return '(${parts.join(', ')})';
  }

  static const String _kDefaultMainnetHost = 'https://ic0.app';
}

/// The static JS body of the generated bundle. Kept as a single constant so
/// the dynamic data (METHODS array + baked canister/host) is the only part
/// computed at generation time. Mirrors the proven shape of the shipped example
/// bundles (`lib/examples/07_icp_ledger.js` et al.).
const String _kBundleBody = r'''
  function init(arg) {
    var a = arg || {};
    var state = {
      backend_id: a.backend_id || CANISTER_ID,
      host: a.host || HOST,
      auth: false,
      results: {},
      loading: {},
      argText: {}
    };
    for (var i = 0; i < METHODS.length; i++) {
      var m = METHODS[i];
      state.argText[m.name] = m.defaultArgs;
    }
    return { state: state, effects: [] };
  }

  function view(state) {
    var kids = [];
    kids.push({
      type: "text",
      props: { text: "Canister " + state.backend_id }
    });
    kids.push({
      type: "toggle",
      props: {
        label: "Sign calls with my profile keypair",
        value: state.auth,
        on_change: { type: "set_auth" }
      }
    });
    for (var i = 0; i < METHODS.length; i++) {
      kids.push(methodSection(METHODS[i], state));
    }
    return { type: "column", children: kids };
  }

  function methodSection(m, state) {
    var sectionKids = [];
    var title = m.name + " (" + modeLabel(m.mode) + ")";
    if (m.returnType && m.returnType.length > 0) {
      title += " -> " + m.returnType;
    }
    if (m.hasArgs) {
      sectionKids.push({
        type: "text_field",
        props: {
          label: "Candid args",
          value: state.argText[m.name] || "()",
          placeholder: m.argsHint,
          on_change: { type: "set_args", method: m.name }
        }
      });
    }
    var loading = !!state.loading[m.name];
    sectionKids.push({
      type: "button",
      props: {
        label: loading ? "Calling " + m.name + "\u2026" : "Call " + m.name,
        disabled: loading,
        on_press: { type: "call", method: m.name }
      }
    });
    if (Object.prototype.hasOwnProperty.call(state.results, m.name)) {
      var r = state.results[m.name];
      var err = (r && r.ok === false) ? String(r.error || "call failed") : null;
      var data = (r && r.ok === true) ? r.value : null;
      sectionKids.push({
        type: "result_display",
        props: { title: m.name + " result", data: data, error: err }
      });
    }
    return { type: "section", props: { title: title }, children: sectionKids };
  }

  function modeLabel(mode) {
    if (mode === 1) return "update";
    if (mode === 2) return "composite";
    return "query";
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";
    if (t === "set_auth") {
      return { state: setShallow(state, { auth: !!msg.value }), effects: [] };
    }
    if (t === "set_args") {
      var nextArgs = Object.assign({}, state.argText);
      nextArgs[msg.method] = msg.value;
      return { state: setShallow(state, { argText: nextArgs }), effects: [] };
    }
    if (t === "call") {
      var m = findMethod(msg.method);
      if (!m) return { state: state, effects: [] };
      var nextLoading = Object.assign({}, state.loading);
      nextLoading[m.name] = true;
      var nextResults = Object.assign({}, state.results);
      delete nextResults[m.name];
      var args = state.argText[m.name] || m.defaultArgs || "()";
      return {
        state: setShallow(state, {
          loading: nextLoading,
          results: nextResults
        }),
        effects: [callEffect(m, args, state)]
      };
    }
    if (t === "effect/result") {
      return handleResult(msg, state);
    }
    return { state: state, effects: [] };
  }

  function callEffect(m, args, state) {
    return {
      kind: "icp_call",
      id: m.name,
      mode: m.mode,
      canister_id: state.backend_id,
      method: m.name,
      args: args,
      host: state.host || "",
      authenticated: !!state.auth
    };
  }

  function handleResult(msg, state) {
    var id = msg.id || "";
    var parsed = readEffect(msg);
    var nextResults = Object.assign({}, state.results);
    nextResults[id] = parsed;
    var nextLoading = Object.assign({}, state.loading);
    nextLoading[id] = false;
    return {
      state: setShallow(state, {
        results: nextResults,
        loading: nextLoading
      }),
      effects: []
    };
  }

  // Normalize a delivered effect/result into {ok, value|error}. Mirrors the
  // shipped example bundles' reader: the host wraps host-level failures as
  // {ok:false,error}, success as {ok:true,data}; the bridge further wraps
  // payloads as {ok:true,result} / {ok:false,error}.
  function readEffect(msg) {
    if (msg.ok === false) {
      return { ok: false, error: String(msg.error || "effect failed") };
    }
    var data = msg.data;
    if (data && typeof data === "object" && data.ok === false) {
      return { ok: false, error: String(data.error || "canister call failed") };
    }
    return { ok: true, value: data ? data.result : undefined };
  }

  function findMethod(name) {
    for (var i = 0; i < METHODS.length; i++) {
      if (METHODS[i].name === name) return METHODS[i];
    }
    return null;
  }

  function setShallow(state, patch) {
    return Object.assign({}, state, patch);
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;

''';
