import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../rust/native_bridge.dart';
import '../models/profile_keypair.dart';
import 'secure_keypair_repository.dart';

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
  final String example; // Minimal TypeScript snippet example
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
    this.keypairId,
    this.isAnonymous = false,
  });

  /// Logical name to expose this call's JSON output under in the bundle arg
  final String label;
  final String canisterId;
  final String method;

  /// 0=query, 1=update, 2=composite
  final int kind;
  final String argsJson;
  final String? host;

  /// Keypair specification options (in order of precedence):
  /// 1. keypairId: Reference to a stored keypair by ID
  /// 2. privateKeyB64: Direct private key specification (legacy)
  /// 3. isAnonymous: Force anonymous call
  final String? keypairId;

  /// If provided, performs authenticated call; otherwise anonymous
  final String? privateKeyB64;

  /// If true, forces anonymous call regardless of other keypair settings
  final bool isAnonymous;
}

class ScriptRunPlan {
  ScriptRunPlan({
    required this.bundle,
    this.calls = const <CanisterCallSpec>[],
    this.initialArg,
  });

  /// Source bundle (TypeScript/QuickJS IIFE).
  final String bundle;
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

  // Script app lifecycle (TS/QuickJS bundles).
  String? jsExec({required String script, String? jsonArg});
  String? jsLint({required String script});
  String? jsAppInit({required String script, String? jsonArg, int budgetMs});
  String? jsAppView(
      {required String script, required String stateJson, int budgetMs});
  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs});
}

class RustScriptBridge implements ScriptBridge {
  RustScriptBridge(this._bridge);
  final RustBridgeLoader _bridge;

  @override
  String? callAnonymous(
      {required String canisterId,
      required String method,
      required int kind,
      String args = '()',
      String? host}) {
    return _bridge.callAnonymous(
        canisterId: canisterId,
        method: method,
        kind: kind,
        args: args,
        host: host);
  }

  @override
  String? callAuthenticated(
      {required String canisterId,
      required String method,
      required int kind,
      required String privateKeyB64,
      String args = '()',
      String? host}) {
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
  String? jsExec({required String script, String? jsonArg}) {
    return _bridge.jsExec(script: script, jsonArg: jsonArg);
  }

  @override
  String? jsLint({required String script}) {
    return _bridge.jsLint(script: script);
  }

  @override
  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    return _bridge.jsAppInit(
        script: script, jsonArg: jsonArg, budgetMs: budgetMs);
  }

  @override
  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    return _bridge.jsAppView(
        script: script, stateJson: stateJson, budgetMs: budgetMs);
  }

  @override
  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    return _bridge.jsAppUpdate(
        script: script,
        msgJson: msgJson,
        stateJson: stateJson,
        budgetMs: budgetMs);
  }
}

class ScriptRunner {
  ScriptRunner(this._bridge, {SecureKeypairRepository? secureRepository})
      : _secureRepository = secureRepository;

  final ScriptBridge _bridge;
  final SecureKeypairRepository? _secureRepository;

  /// Catalog of integrations available to TS scripts.
  static const List<IntegrationInfo> integrationCatalog = <IntegrationInfo>[
    IntegrationInfo(
      id: 'icp_call',
      title: 'Canister call',
      description:
          'Perform a single canister method call. Supports anonymous or authenticated calls. Returns the raw JSON result.',
      example:
          'return icp_call({\n  canister_id: "aaaaa-aa",\n  method: "greet",\n  kind: 0, // 0=query, 1=update, 2=composite\n  args: "World"\n})',
    ),
    IntegrationInfo(
      id: 'icp_batch',
      title: 'Batch calls',
      description:
          'Execute multiple canister calls and return a map of label→result. Each item can include canister_id, method, kind, args, host, private_key_b64.',
      example:
          'const a = { label: "gov", canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai", method: "get_pending_proposals", kind: 0, args: "()" };\nconst b = { label: "ledger", canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai", method: "query_blocks", kind: 0, args: \'{"start":0,"length":10}\' };\nreturn icp_batch([a, b])',
    ),
    IntegrationInfo(
      id: 'icp_message',
      title: 'Message',
      description:
          'Return a simple message to the UI layer. Useful for debugging or informing the user.',
      example: 'return icp_message({ text: "Hello from TypeScript" })',
    ),
    IntegrationInfo(
      id: 'icp_ui_list',
      title: 'UI: List with buttons',
      description:
          'Describe a minimal UI list that the app renders. Items are shown with optional buttons that can trigger actions (e.g. icp_call).',
      example:
          'return icp_ui_list({\n  items: [{ title: "Item A" }, { title: "Item B" }],\n  buttons: [{ title: "Refresh", action: { action: "batch", calls: [] } }]\n})',
    ),
    IntegrationInfo(
      id: 'icp_result_display',
      title: 'Result Display',
      description:
          'Display canister call results with improved formatting, copy/export capabilities, and smart data visualization.',
      example:
          'return icp_result_display({\n  data: call_result,\n  title: "Query Results",\n  expandable: true,\n  expanded: false\n})',
    ),
    IntegrationInfo(
      id: 'icp_searchable_list',
      title: 'Searchable Result List',
      description:
          'Display a searchable, filterable list of results with advanced interaction capabilities.',
      example:
          'return icp_searchable_list({\n  items: processed_items,\n  title: "Transactions",\n  searchable: true\n})',
    ),
    IntegrationInfo(
      id: 'icp_format_icp',
      title: 'ICP Token Formatter',
      description:
          'Format ICP token values from e8s (8 decimals) to human-readable format.',
      example:
          'return icp_message({ text: "Balance: " + icp_format_icp(123456789) }) // "1.23456789"',
    ),
    IntegrationInfo(
      id: 'icp_format_timestamp',
      title: 'Timestamp Formatter',
      description:
          'Format nanosecond timestamps into human-readable date/time strings.',
      example:
          'return icp_message({ text: "Created: " + icp_format_timestamp(1704067200000000000) })',
    ),
    IntegrationInfo(
      id: 'icp_filter_items',
      title: 'Data Filter',
      description:
          'Filter lists of items by field values. Useful for processing canister results.',
      example:
          'const filtered = icp_filter_items(transactions, "type", "transfer");\nreturn icp_searchable_list({ items: filtered })',
    ),
    IntegrationInfo(
      id: 'icp_sort_items',
      title: 'Data Sorter',
      description:
          'Sort lists of items by field values in ascending or descending order.',
      example:
          'const sorted = icp_sort_items(transactions, "timestamp", false);\nreturn icp_searchable_list({ items: sorted })',
    ),
  ];

  /// Resolve keypair specification to a private key or null (for anonymous calls).
  /// Returns null if anonymous call is requested or if keypair resolution fails.
  Future<String?> _resolveKeypair(CanisterCallSpec spec) async {
    // 1. Explicit anonymous call takes precedence
    if (spec.isAnonymous) {
      return null;
    }

    // 2. Keypair ID reference (takes priority over direct private key)
    if (spec.keypairId != null && spec.keypairId!.trim().isNotEmpty) {
      final SecureKeypairRepository? repository = _secureRepository;
      if (repository == null) {
        throw Exception(
            'Keypair ID specified but no secure keypair repository provided');
      }

      try {
        final List<ProfileKeypair> keypairs = await repository.loadKeypairs();
        final ProfileKeypair? keypair =
            keypairs.cast<ProfileKeypair?>().firstWhere(
                  (id) => id?.id == spec.keypairId,
                  orElse: () => null,
                );

        if (keypair == null) {
          throw Exception('Keypair with ID "${spec.keypairId}" not found');
        }

        // Get private key from secure storage
        return await repository.getPrivateKey(keypair.id);
      } catch (e) {
        throw Exception('Failed to resolve keypair "${spec.keypairId}": $e');
      }
    }

    // 3. Direct private key specification (legacy support)
    if (spec.privateKeyB64 != null && spec.privateKeyB64!.trim().isNotEmpty) {
      return spec.privateKeyB64!.trim();
    }

    // 4. Default to anonymous if no keypair specification provided
    return null;
  }

  /// Build a [CanisterCallSpec] from a decoded action item. Used to share
  /// keypair-resolution logic across single-call and batch paths.
  CanisterCallSpec _specFromCallItem(Map<String, dynamic> item,
      {required String defaultLabel}) {
    final String label =
        ((item['label'] as String?) ?? (item['method'] as String? ?? '')).trim();
    final String canisterId = (item['canister_id'] as String?)?.trim() ?? '';
    final String method = (item['method'] as String?)?.trim() ?? '';
    final int kind = (item['kind'] as num?)?.toInt() ?? 0;
    final String args = (item['args'] as String?) ?? '()';
    final String? host = (item['host'] as String?)?.trim().isEmpty == true
        ? null
        : item['host'] as String?;
    final String? key = (item['private_key_b64'] as String?)?.trim();
    final String? keypairId = (item['keypair_id'] as String?)?.trim();
    final bool isAnonymous = (item['is_anonymous'] as bool?) ?? false;
    return CanisterCallSpec(
      label: label.isEmpty ? defaultLabel : label,
      canisterId: canisterId,
      method: method,
      kind: kind,
      argsJson: args,
      host: host,
      privateKeyB64: key,
      keypairId: keypairId,
      isAnonymous: isAnonymous,
    );
  }

  String? _dispatchCall(CanisterCallSpec spec, String? privateKey) {
    if (privateKey == null || privateKey.isEmpty) {
      return _bridge.callAnonymous(
        canisterId: spec.canisterId,
        method: spec.method,
        kind: spec.kind,
        args: spec.argsJson,
        host: spec.host,
      );
    }
    return _bridge.callAuthenticated(
      canisterId: spec.canisterId,
      method: spec.method,
      kind: spec.kind,
      privateKeyB64: privateKey,
      args: spec.argsJson,
      host: spec.host,
    );
  }

  /// Resolve the keypair, execute a single canister call, and decode its JSON
  /// output. [resolveContext] humanizes keypair-resolution errors; [emptyError]
  /// is surfaced verbatim when the call returns no body. Non-JSON responses are
  /// returned as raw strings.
  Future<ScriptRunResult> _executeCanisterCall(
    CanisterCallSpec spec, {
    required String resolveContext,
    required String emptyError,
  }) async {
    final String? privateKey;
    try {
      privateKey = await _resolveKeypair(spec);
    } catch (e) {
      return ScriptRunResult(
          ok: false, error: 'Failed to resolve keypair for $resolveContext: $e');
    }

    final String? callOut = _dispatchCall(spec, privateKey);

    if (callOut == null || callOut.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: emptyError);
    }
    try {
      return ScriptRunResult(ok: true, result: json.decode(callOut));
    } on FormatException catch (e) {
      debugPrint('ScriptRunner: canister response not JSON, returning raw: $e');
      return ScriptRunResult(ok: true, result: callOut);
    }
  }

  /// Execute every call spec in [calls], collecting outputs keyed by label
  /// (falls back to the method name when a label is absent). Returns the first
  /// failure encountered or the assembled output map on success.
  Future<ScriptRunResult> _executeBatch(List<dynamic> calls) async {
    if (calls.isEmpty) {
      return ScriptRunResult(ok: false, error: 'batch has no calls');
    }
    final Map<String, dynamic> outputs = <String, dynamic>{};
    for (final dynamic item in calls) {
      if (item is! Map<String, dynamic>) {
        return ScriptRunResult(
            ok: false, error: 'invalid call spec in batch');
      }
      final String label =
          ((item['label'] as String?) ?? (item['method'] as String? ?? ''))
              .trim();
      final CanisterCallSpec spec =
          _specFromCallItem(item, defaultLabel: 'batch_call');
      final String outputKey = label.isEmpty ? spec.method : label;

      if (spec.canisterId.isEmpty || spec.method.isEmpty) {
        return ScriptRunResult(
            ok: false, error: 'batch call missing canister_id/method');
      }

      final ScriptRunResult result = await _executeCanisterCall(
        spec,
        resolveContext: 'batch call "$label"',
        emptyError: 'Follow-up call returned empty for $outputKey',
      );
      if (!result.ok) {
        return result;
      }
      outputs[outputKey] = result.result;
    }
    return ScriptRunResult(ok: true, result: outputs);
  }

  /// Execute the plan: call canisters in order, build arg, run the TS bundle.
  /// Fails fast on any call/parse error.
  Future<ScriptRunResult> run(ScriptRunPlan plan) async {
    if (plan.bundle.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: 'bundle is empty');
    }

    // Collect call outputs as decoded JSON values
    final Map<String, dynamic> callOutputs = <String, dynamic>{};
    for (final CanisterCallSpec spec in plan.calls) {
      final String? privateKey;
      try {
        privateKey = await _resolveKeypair(spec);
      } catch (e) {
        return ScriptRunResult(
            ok: false,
            error: 'Failed to resolve keypair for ${spec.label}: $e');
      }

      final String? raw = _dispatchCall(spec, privateKey);
      if (raw == null || raw.trim().isEmpty) {
        return ScriptRunResult(
            ok: false, error: 'Empty response from ${spec.label}');
      }
      dynamic parsed;
      try {
        parsed = json.decode(raw);
      } catch (e) {
        return ScriptRunResult(
            ok: false, error: 'Invalid JSON from ${spec.label}: $e');
      }
      callOutputs[spec.label] = parsed;
    }

    // Build arg for the bundle: { input: <initialArg?>, calls: { label: json, ... } }
    final Map<String, dynamic> arg = <String, dynamic>{
      'input': plan.initialArg,
      'calls': callOutputs,
    };
    final String jsonArg = json.encode(arg);

    // The TS bundle is self-contained (no host-injected preamble).
    final String? out = _bridge.jsExec(script: plan.bundle, jsonArg: jsonArg);
    if (out == null || out.trim().isEmpty) {
      return ScriptRunResult(
          ok: false, error: 'Script execution returned empty');
    }

    try {
      final Map<String, dynamic> obj =
          json.decode(out) as Map<String, dynamic>;
      final bool ok = (obj['ok'] as bool?) ?? false;
      if (!ok) {
        return ScriptRunResult(
            ok: false, error: (obj['error'] as String?) ?? 'Script error');
      }
      final dynamic result = obj['result'];
      // If the script requests a follow-up call, perform it now
      if (result is Map<String, dynamic> &&
          (result['action'] as String?) == 'call') {
        final CanisterCallSpec spec =
            _specFromCallItem(result, defaultLabel: 'follow_up_call');
        if (spec.canisterId.isEmpty || spec.method.isEmpty) {
          return ScriptRunResult(
              ok: false, error: 'call action missing canister_id/method');
        }
        return _executeCanisterCall(
          spec,
          resolveContext: 'follow-up call',
          emptyError: 'Follow-up call returned empty',
        );
      }
      // Batch of follow-up calls
      if (result is Map<String, dynamic> &&
          (result['action'] as String?) == 'batch') {
        final List<dynamic> calls =
            (result['calls'] as List<dynamic>? ?? const <dynamic>[]);
        return _executeBatch(calls);
      }
      return ScriptRunResult(ok: true, result: result);
    } catch (e) {
      // If not in wrapper, try to parse as bare JSON result
      try {
        final dynamic any = json.decode(out);
        return ScriptRunResult(ok: true, result: any);
      } on FormatException catch (fe) {
        debugPrint('ScriptRunner: invalid script output: $e / bare decode: $fe');
        return ScriptRunResult(ok: false, error: 'Invalid script output: $e');
      }
    }
  }

  /// Perform a single action object returned by a script or UI buttons.
  /// Supports 'call' and 'batch'. Returns decoded JSON when possible.
  Future<ScriptRunResult> performAction(Map<String, dynamic> action) async {
    final String kindStr = (action['action'] as String? ?? '').trim();
    if (kindStr.isEmpty) {
      return ScriptRunResult(ok: false, error: 'performAction: missing action');
    }
    if (kindStr == 'call') {
      final CanisterCallSpec spec =
          _specFromCallItem(action, defaultLabel: 'action_call');
      if (spec.canisterId.isEmpty || spec.method.isEmpty) {
        return ScriptRunResult(
            ok: false, error: 'call action missing canister_id/method');
      }
      return _executeCanisterCall(
        spec,
        resolveContext: 'action call',
        emptyError: 'call returned empty',
      );
    }
    if (kindStr == 'batch') {
      final List<dynamic> calls =
          (action['calls'] as List<dynamic>? ?? const <dynamic>[]);
      return _executeBatch(calls);
    }
    return ScriptRunResult(ok: false, error: 'Unsupported action: $kindStr');
  }
}

/// Minimal interface to decouple UI from concrete runtime for testing.
abstract class IScriptAppRuntime {
  Future<Map<String, dynamic>> init(
      {required String script, Map<String, dynamic>? initialArg, int budgetMs});
  Future<Map<String, dynamic>> view(
      {required String script,
      required Map<String, dynamic> state,
      int budgetMs});
  Future<Map<String, dynamic>> update(
      {required String script,
      required Map<String, dynamic> msg,
      required Map<String, dynamic> state,
      int budgetMs});
}

/// Runtime host for a TS app: init/view/update lifecycle.
class ScriptAppRuntime implements IScriptAppRuntime {
  ScriptAppRuntime(this._bridge);
  final ScriptBridge _bridge;

  @override
  Future<Map<String, dynamic>> init(
      {required String script,
      Map<String, dynamic>? initialArg,
      int budgetMs = 50}) async {
    final String? out = _bridge.jsAppInit(
        script: script,
        jsonArg: initialArg == null ? null : json.encode(initialArg),
        budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('app init returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('app init error: ${obj['error']}');
    }
    return obj;
  }

  @override
  Future<Map<String, dynamic>> view(
      {required String script,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    final String? out = _bridge.jsAppView(
        script: script, stateJson: json.encode(state), budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('app view returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('app view error: ${obj['error']}');
    }
    return obj;
  }

  @override
  Future<Map<String, dynamic>> update(
      {required String script,
      required Map<String, dynamic> msg,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    final String? out = _bridge.jsAppUpdate(
        script: script,
        msgJson: json.encode(msg),
        stateJson: json.encode(state),
        budgetMs: budgetMs);
    if (out == null || out.trim().isEmpty) {
      throw StateError('app update returned empty');
    }
    final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
    if ((obj['ok'] as bool?) != true) {
      throw StateError('app update error: ${obj['error']}');
    }
    return obj;
  }
}
