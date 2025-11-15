import 'dart:convert';

import '../rust/native_bridge.dart';

class IntegrationInfo {
  const IntegrationInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.example,
  });

  final String id; // e.g. icp_call
  final String title; // Short human label
  final String description; // Helpful description
  final String example; // Minimal Lua snippet example
}

class CanisterCallSpec {
  CanisterCallSpec({
    required this.label,
    required this.canisterId,
    required this.method,
    required this.kind,
    this.argsJson = '()',
    this.host,
    this.privateKeyB64,
  });

  /// Logical name to expose this call's JSON output under in the Lua arg
  final String label;
  final String canisterId;
  final String method;
  /// 0=query, 1=update, 2=composite
  final int kind;
  final String argsJson;
  final String? host;
  /// If provided, performs authenticated call; otherwise anonymous
  final String? privateKeyB64;
}

class ScriptRunPlan {
  ScriptRunPlan({
    required this.luaSource,
    this.calls = const <CanisterCallSpec>[],
    this.initialArg,
  });

  final String luaSource;
  final List<CanisterCallSpec> calls;
  /// Optional initial JSON to pass under arg.input
  final Map<String, dynamic>? initialArg;
}

class ScriptRunResult {
  ScriptRunResult({required this.ok, this.result, this.error});
  final bool ok;
  final dynamic result;
  final String? error;
}

/// Abstraction over the Rust FFI bridge to allow fakes in tests.
abstract class ScriptBridge {
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args,
    String? host,
  });

  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int kind,
    required String privateKeyB64,
    String args,
    String? host,
  });

  String? luaExec({required String script, String? jsonArg});
  String? luaLint({required String script});

  // TEA-style app
  String? luaAppInit({required String script, String? jsonArg, int budgetMs});
  String? luaAppView({required String script, required String stateJson, int budgetMs});
  String? luaAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs});
}

class RustScriptBridge implements ScriptBridge {
  RustScriptBridge(this._bridge);
  final RustBridgeLoader _bridge;

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    return _bridge.callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) {
    return _bridge.callAuthenticated(
      canisterId: canisterId,
      method: method,
      kind: kind,
      privateKeyB64: privateKeyB64,
      args: args,
      host: host,
    );
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    return _bridge.luaExec(script: script, jsonArg: jsonArg);
  }

  @override
  String? luaLint({required String script}) {
    return _bridge.luaLint(script: script);
  }

  @override
  String? luaAppInit({required String script, String? jsonArg, int budgetMs = 50}) {
    return _bridge.luaAppInit(script: script, jsonArg: jsonArg, budgetMs: budgetMs);
  }

  @override
  String? luaAppView({required String script, required String stateJson, int budgetMs = 50}) {
    return _bridge.luaAppView(script: script, stateJson: stateJson, budgetMs: budgetMs);
  }

  @override
  String? luaAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) {
    return _bridge.luaAppUpdate(script: script, msgJson: msgJson, stateJson: stateJson, budgetMs: budgetMs);
  }
}

class ScriptRunner {
  ScriptRunner(this._bridge);

  final ScriptBridge _bridge;

  /// Catalog of integrations available to Lua scripts.
  /// Extend this list as new helpers are added in [_injectHelpers].
  static const List<IntegrationInfo> integrationCatalog = <IntegrationInfo>[
    IntegrationInfo(
      id: 'icp_call',
      title: 'Canister call',
      description:
          'Perform a single canister method call. Supports anonymous or authenticated calls. Returns the raw JSON result.',
      example:
          'return icp_call({\n  canister_id = "aaaaa-aa",\n  method = "greet",\n  kind = 0, -- 0=query, 1=update, 2=composite\n  args = "(".."World"..")"\n})',
    ),
    IntegrationInfo(
      id: 'icp_batch',
      title: 'Batch calls',
      description:
          'Execute multiple canister calls and return a map of label→result. Each item can include canister_id, method, kind, args, host, private_key_b64.',
      example:
          'local a = { label = "gov", canister_id = "rrkah-fqaaa-aaaaa-aaaaq-cai", method = "get_pending_proposals", kind = 0, args = "()" }\nlocal b = { label = "ledger", canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai", method = "query_blocks", kind = 0, args = "{".."start"..":0,".."length"..":10}" }\nreturn icp_batch({ a, b })',
    ),
    IntegrationInfo(
      id: 'icp_message',
      title: 'Message',
      description:
          'Return a simple message to the UI layer. Useful for debugging or informing the user.',
      example: 'return icp_message("Hello from Lua")',
    ),
    IntegrationInfo(
      id: 'icp_ui_list',
      title: 'UI: List with buttons',
      description:
          'Describe a minimal UI list that the app renders. Items are shown with optional buttons that can trigger actions (e.g. icp_call).',
      example:
          'return icp_ui_list({\n  items = { { title = "Item A" }, { title = "Item B" } },\n  buttons = { { title = "Refresh", action = { action = "batch", calls = {} } } }\n})',
    ),
  ];

  /// Execute the plan: call canisters in order, build arg, run Lua.
  /// Fails fast on any call/parse error.
  Future<ScriptRunResult> run(ScriptRunPlan plan) async {
    if (plan.luaSource.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: 'luaSource is empty');
    }

    // Collect call outputs as decoded JSON values
    final Map<String, dynamic> callOutputs = <String, dynamic>{};
    for (final CanisterCallSpec spec in plan.calls) {
      final String? raw = (spec.privateKeyB64 == null || spec.privateKeyB64!.trim().isEmpty)
          ? _bridge.callAnonymous(
              canisterId: spec.canisterId,
              method: spec.method,
              kind: spec.kind,
              args: spec.argsJson,
              host: spec.host,
            )
          : _bridge.callAuthenticated(
              canisterId: spec.canisterId,
              method: spec.method,
              kind: spec.kind,
              privateKeyB64: spec.privateKeyB64!,
              args: spec.argsJson,
              host: spec.host,
            );
      if (raw == null || raw.trim().isEmpty) {
        return ScriptRunResult(ok: false, error: 'Empty response from ${spec.label}');
      }
      dynamic parsed;
      try {
        parsed = json.decode(raw);
      } catch (e) {
        return ScriptRunResult(ok: false, error: 'Invalid JSON from ${spec.label}: $e');
      }
      callOutputs[spec.label] = parsed;
    }

    // Build arg for Lua: { input: <initialArg?>, calls: { label: json, ... } }
    final Map<String, dynamic> arg = <String, dynamic>{
      'input': plan.initialArg,
      'calls': callOutputs,
    };
    final String jsonArg = json.encode(arg);

    final String luaSourceWithHelper = _injectHelpers(plan.luaSource);
    final String? luaOut = _bridge.luaExec(script: luaSourceWithHelper, jsonArg: jsonArg);
    if (luaOut == null || luaOut.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: 'Lua execution returned empty');
    }

    try {
      final Map<String, dynamic> obj = json.decode(luaOut) as Map<String, dynamic>;
      final bool ok = (obj['ok'] as bool?) ?? false;
      if (!ok) {
        return ScriptRunResult(ok: false, error: (obj['error'] as String?) ?? 'Lua error');
      }
      final dynamic result = obj['result'];
      // If Lua requests a follow-up call, perform it now
      if (result is Map<String, dynamic> && (result['action'] as String?) == 'call') {
        final String canisterId = (result['canister_id'] as String?)?.trim() ?? '';
        final String method = (result['method'] as String?)?.trim() ?? '';
        final int kind = (result['kind'] as num?)?.toInt() ?? 0;
        final String args = (result['args'] as String?) ?? '()';
        final String? host = (result['host'] as String?)?.trim().isEmpty == true ? null : result['host'] as String?;
        final String? key = (result['private_key_b64'] as String?)?.trim();
        if (canisterId.isEmpty || method.isEmpty) {
          return ScriptRunResult(ok: false, error: 'call action missing canister_id/method');
        }
        String? callOut;
        if (key == null || key.isEmpty) {
          callOut = _bridge.callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
        } else {
          callOut = _bridge.callAuthenticated(
            canisterId: canisterId,
            method: method,
            kind: kind,
            privateKeyB64: key,
            args: args,
            host: host,
          );
        }
        if (callOut == null || callOut.trim().isEmpty) {
          return ScriptRunResult(ok: false, error: 'Follow-up call returned empty');
        }
        try {
          final dynamic parsed = json.decode(callOut);
          return ScriptRunResult(ok: true, result: parsed);
        } catch (e) {
          return ScriptRunResult(ok: true, result: callOut);
        }
      }
      // Batch of follow-up calls
      if (result is Map<String, dynamic> && (result['action'] as String?) == 'batch') {
        final List<dynamic> calls = (result['calls'] as List<dynamic>? ?? const <dynamic>[]);
        if (calls.isEmpty) {
          return ScriptRunResult(ok: false, error: 'batch has no calls');
        }
        final Map<String, dynamic> outputs = <String, dynamic>{};
        for (final dynamic item in calls) {
          if (item is! Map<String, dynamic>) {
            return ScriptRunResult(ok: false, error: 'invalid call spec in batch');
          }
          final String label = ((item['label'] as String?) ?? (item['method'] as String? ?? '')).trim();
          final String canisterId = (item['canister_id'] as String?)?.trim() ?? '';
          final String method = (item['method'] as String?)?.trim() ?? '';
          final int kind = (item['kind'] as num?)?.toInt() ?? 0;
          final String args = (item['args'] as String?) ?? '()';
          final String? host = (item['host'] as String?)?.trim().isEmpty == true ? null : item['host'] as String?;
          final String? key = (item['private_key_b64'] as String?)?.trim();
          if (canisterId.isEmpty || method.isEmpty) {
            return ScriptRunResult(ok: false, error: 'batch call missing canister_id/method');
          }
          String? callOut;
          if (key == null || key.isEmpty) {
            callOut = _bridge.callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
          } else {
            callOut = _bridge.callAuthenticated(
              canisterId: canisterId,
              method: method,
              kind: kind,
              privateKeyB64: key,
              args: args,
              host: host,
            );
          }
          if (callOut == null || callOut.trim().isEmpty) {
            return ScriptRunResult(ok: false, error: 'Follow-up call returned empty for $label');
          }
          try {
            outputs[label.isEmpty ? method : label] = json.decode(callOut);
          } catch (_) {
            outputs[label.isEmpty ? method : label] = callOut;
          }
        }
        return ScriptRunResult(ok: true, result: outputs);
      }
      // UI description passthrough (rendered by Flutter layer)
      if (result is Map<String, dynamic> && (result['action'] as String?) == 'ui') {
        return ScriptRunResult(ok: true, result: result);
      }
      return ScriptRunResult(ok: true, result: result);
    } catch (e) {
      // If not in wrapper, try to parse as bare JSON result
      try {
        final dynamic any = json.decode(luaOut);
        return ScriptRunResult(ok: true, result: any);
      } catch (_) {
        return ScriptRunResult(ok: false, error: 'Invalid Lua output: $e');
      }
    }
  }

  /// Perform a single action object returned by Lua or UI buttons.
  /// Supports 'call' and 'batch'. Returns decoded JSON when possible.
  Future<ScriptRunResult> performAction(Map<String, dynamic> action) async {
    final String kindStr = (action['action'] as String? ?? '').trim();
    if (kindStr.isEmpty) {
      return ScriptRunResult(ok: false, error: 'performAction: missing action');
    }
    if (kindStr == 'call') {
      final String canisterId = (action['canister_id'] as String?)?.trim() ?? '';
      final String method = (action['method'] as String?)?.trim() ?? '';
      final int kind = (action['kind'] as num?)?.toInt() ?? 0;
      final String args = (action['args'] as String?) ?? '()';
      final String? host = (action['host'] as String?)?.trim().isEmpty == true ? null : action['host'] as String?;
      final String? key = (action['private_key_b64'] as String?)?.trim();
      if (canisterId.isEmpty || method.isEmpty) {
        return ScriptRunResult(ok: false, error: 'call action missing canister_id/method');
      }
      String? callOut;
      if (key == null || key.isEmpty) {
        callOut = _bridge.callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
      } else {
        callOut = _bridge.callAuthenticated(
          canisterId: canisterId,
          method: method,
          kind: kind,
          privateKeyB64: key,
          args: args,
          host: host,
        );
      }
      if (callOut == null || callOut.trim().isEmpty) {
        return ScriptRunResult(ok: false, error: 'call returned empty');
      }
      try {
        final dynamic parsed = json.decode(callOut);
        return ScriptRunResult(ok: true, result: parsed);
      } catch (_) {
        return ScriptRunResult(ok: true, result: callOut);
      }
    }
    if (kindStr == 'batch') {
      final List<dynamic> calls = (action['calls'] as List<dynamic>? ?? const <dynamic>[]);
      if (calls.isEmpty) {
        return ScriptRunResult(ok: false, error: 'batch has no calls');
      }
      final Map<String, dynamic> outputs = <String, dynamic>{};
      for (final dynamic item in calls) {
        if (item is! Map<String, dynamic>) {
          return ScriptRunResult(ok: false, error: 'invalid call spec in batch');
        }
        final String label = ((item['label'] as String?) ?? (item['method'] as String? ?? '')).trim();
        final String canisterId = (item['canister_id'] as String?)?.trim() ?? '';
        final String method = (item['method'] as String?)?.trim() ?? '';
        final int kind = (item['kind'] as num?)?.toInt() ?? 0;
        final String args = (item['args'] as String?) ?? '()';
        final String? host = (item['host'] as String?)?.trim().isEmpty == true ? null : item['host'] as String?;
        final String? key = (item['private_key_b64'] as String?)?.trim();
        if (canisterId.isEmpty || method.isEmpty) {
          return ScriptRunResult(ok: false, error: 'batch call missing canister_id/method');
        }
        String? callOut;
        if (key == null || key.isEmpty) {
          callOut = _bridge.callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
        } else {
          callOut = _bridge.callAuthenticated(
            canisterId: canisterId,
            method: method,
            kind: kind,
            privateKeyB64: key,
            args: args,
            host: host,
          );
        }
        if (callOut == null || callOut.trim().isEmpty) {
          return ScriptRunResult(ok: false, error: 'Follow-up call returned empty for ${label.isEmpty ? method : label}');
        }
        try {
          outputs[label.isEmpty ? method : label] = json.decode(callOut);
        } catch (_) {
          outputs[label.isEmpty ? method : label] = callOut;
        }
      }
      return ScriptRunResult(ok: true, result: outputs);
    }
    return ScriptRunResult(ok: false, error: 'Unsupported action: $kindStr');
  }

  String _injectHelpers(String src) {
    // Provide minimal helpers the script can call.
    const String helpers =
        'function icp_call(spec) spec = spec or {}; spec.action = "call"; return spec end\n'
        'function icp_batch(calls) calls = calls or {}; return { action = "batch", calls = calls } end\n'
        'function icp_message(text) return { action = "message", text = tostring(text or "") } end\n'
        'function icp_ui_list(spec) spec = spec or {}; local items = spec.items or {}; local buttons = spec.buttons or {}; return { action = "ui", ui = { type = "list", items = items, buttons = buttons } } end\n';
    return '$helpers$src';
  }
}

/// Minimal interface to decouple UI from concrete runtime for testing.
abstract class IScriptAppRuntime {
  Future<Map<String, dynamic>> init({required String script, Map<String, dynamic>? initialArg, int budgetMs});
  Future<Map<String, dynamic>> view({required String script, required Map<String, dynamic> state, int budgetMs});
  Future<Map<String, dynamic>> update({required String script, required Map<String, dynamic> msg, required Map<String, dynamic> state, int budgetMs});
}

/// Runtime host for TEA-style Lua app: init/view/update + effects execution.
class ScriptAppRuntime implements IScriptAppRuntime {
  ScriptAppRuntime(this._bridge);
  final ScriptBridge _bridge;

  @override
  Future<Map<String, dynamic>> init({required String script, Map<String, dynamic>? initialArg, int budgetMs = 50}) async {
    final String? out = _bridge.luaAppInit(script: script, jsonArg: initialArg == null ? null : json.encode(initialArg), budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('luaAppInit returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('luaAppInit error: ${obj['error']}');
    }
    return obj;
  }

  @override
  Future<Map<String, dynamic>> view({required String script, required Map<String, dynamic> state, int budgetMs = 50}) async {
    final String? out = _bridge.luaAppView(script: script, stateJson: json.encode(state), budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('luaAppView returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('luaAppView error: ${obj['error']}');
    }
    return obj;
  }

  @override
  Future<Map<String, dynamic>> update({required String script, required Map<String, dynamic> msg, required Map<String, dynamic> state, int budgetMs = 50}) async {
    final String? out = _bridge.luaAppUpdate(script: script, msgJson: json.encode(msg), stateJson: json.encode(state), budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('luaAppUpdate returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('luaAppUpdate error: ${obj['error']}');
    }
    return obj;
  }
}
