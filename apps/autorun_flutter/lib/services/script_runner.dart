import 'dart:convert';

import '../rust/native_bridge.dart';

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
}

class ScriptRunner {
  ScriptRunner(this._bridge);

  final ScriptBridge _bridge;

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

  String _injectHelpers(String src) {
    // Provide a minimal helper the script can call: icp_call{...}
    const String helpers =
        'function icp_call(spec) spec = spec or {}; spec.action = "call"; return spec end\n'
        'function icp_batch(calls) calls = calls or {}; return { action = "batch", calls = calls } end\n';
    return '$helpers$src';
  }
}
