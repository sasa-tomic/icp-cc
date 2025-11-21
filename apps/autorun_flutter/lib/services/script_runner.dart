import 'dart:convert';

import '../rust/native_bridge.dart';
import '../models/profile_keypair.dart';
import 'secure_identity_repository.dart';

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
    this.identityId,
    this.isAnonymous = false,
  });

  /// Logical name to expose this call's JSON output under in the Lua arg
  final String label;
  final String canisterId;
  final String method;

  /// 0=query, 1=update, 2=composite
  final int kind;
  final String argsJson;
  final String? host;

  /// Identity specification options (in order of precedence):
  /// 1. identityId: Reference to a stored identity by ID
  /// 2. privateKeyB64: Direct private key specification (legacy)
  /// 3. isAnonymous: Force anonymous call
  final String? identityId;

  /// If provided, performs authenticated call; otherwise anonymous
  final String? privateKeyB64;

  /// If true, forces anonymous call regardless of other identity settings
  final bool isAnonymous;
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
  String? luaAppView(
      {required String script, required String stateJson, int budgetMs});
  String? luaAppUpdate(
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
  String? luaExec({required String script, String? jsonArg}) {
    return _bridge.luaExec(script: script, jsonArg: jsonArg);
  }

  @override
  String? luaLint({required String script}) {
    return _bridge.luaLint(script: script);
  }

  @override
  String? luaAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    return _bridge.luaAppInit(
        script: script, jsonArg: jsonArg, budgetMs: budgetMs);
  }

  @override
  String? luaAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    return _bridge.luaAppView(
        script: script, stateJson: stateJson, budgetMs: budgetMs);
  }

  @override
  String? luaAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    return _bridge.luaAppUpdate(
        script: script,
        msgJson: msgJson,
        stateJson: stateJson,
        budgetMs: budgetMs);
  }
}

class ScriptRunner {
  ScriptRunner(this._bridge, {SecureIdentityRepository? secureRepository})
      : _secureRepository = secureRepository;

  final ScriptBridge _bridge;
  final SecureIdentityRepository? _secureRepository;

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
    IntegrationInfo(
      id: 'icp_result_display',
      title: 'Result Display',
      description:
          'Display canister call results with improved formatting, copy/export capabilities, and smart data visualization.',
      example:
          'return icp_result_display({\n  data = call_result,\n  title = "Query Results",\n  expandable = true,\n  expanded = false\n})',
    ),
    IntegrationInfo(
      id: 'icp_searchable_list',
      title: 'Searchable Result List',
      description:
          'Display a searchable, filterable list of results with advanced interaction capabilities.',
      example:
          'return icp_searchable_list({\n  items = processed_items,\n  title = "Transactions",\n  searchable = true\n})',
    ),
    IntegrationInfo(
      id: 'icp_format_icp',
      title: 'ICP Token Formatter',
      description:
          'Format ICP token values from e8s (8 decimals) to human-readable format.',
      example:
          'return icp_message("Balance: " .. icp_format_icp(123456789)) -- "1.23456789 ICP"',
    ),
    IntegrationInfo(
      id: 'icp_format_timestamp',
      title: 'Timestamp Formatter',
      description:
          'Format nanosecond timestamps into human-readable date/time strings.',
      example:
          'return icp_message("Created: " .. icp_format_timestamp(1704067200000000000))',
    ),
    IntegrationInfo(
      id: 'icp_filter_items',
      title: 'Data Filter',
      description:
          'Filter lists of items by field values. Useful for processing canister results.',
      example:
          'local filtered = icp_filter_items(transactions, "type", "transfer")\nreturn icp_searchable_list({ items = filtered })',
    ),
    IntegrationInfo(
      id: 'icp_sort_items',
      title: 'Data Sorter',
      description:
          'Sort lists of items by field values in ascending or descending order.',
      example:
          'local sorted = icp_sort_items(transactions, "timestamp", false)\nreturn icp_searchable_list({ items = sorted })',
    ),
  ];

  /// Resolve identity specification to a private key or null (for anonymous calls).
  /// Returns null if anonymous call is requested or if identity resolution fails.
  Future<String?> _resolveIdentity(CanisterCallSpec spec) async {
    // 1. Explicit anonymous call takes precedence
    if (spec.isAnonymous) {
      return null;
    }

    // 2. Identity ID reference (takes priority over direct private key)
    if (spec.identityId != null && spec.identityId!.trim().isNotEmpty) {
      final SecureIdentityRepository? repository = _secureRepository;
      if (repository == null) {
        throw Exception(
            'Identity ID specified but no secure identity repository provided');
      }

      try {
        final List<ProfileKeypair> identities =
            await repository.loadIdentities();
        final ProfileKeypair? identity =
            identities.cast<ProfileKeypair?>().firstWhere(
                  (id) => id?.id == spec.identityId,
                  orElse: () => null,
                );

        if (identity == null) {
          throw Exception('Identity with ID "${spec.identityId}" not found');
        }

        // Get private key from secure storage
        return await repository.getPrivateKey(identity.id);
      } catch (e) {
        throw Exception('Failed to resolve identity "${spec.identityId}": $e');
      }
    }

    // 3. Direct private key specification (legacy support)
    if (spec.privateKeyB64 != null && spec.privateKeyB64!.trim().isNotEmpty) {
      return spec.privateKeyB64!.trim();
    }

    // 4. Default to anonymous if no identity specification provided
    return null;
  }

  /// Execute the plan: call canisters in order, build arg, run Lua.
  /// Fails fast on any call/parse error.
  Future<ScriptRunResult> run(ScriptRunPlan plan) async {
    if (plan.luaSource.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: 'luaSource is empty');
    }

    // Collect call outputs as decoded JSON values
    final Map<String, dynamic> callOutputs = <String, dynamic>{};
    for (final CanisterCallSpec spec in plan.calls) {
      final String? privateKey;
      try {
        privateKey = await _resolveIdentity(spec);
      } catch (e) {
        return ScriptRunResult(
            ok: false,
            error: 'Failed to resolve identity for ${spec.label}: $e');
      }

      final String? raw = (privateKey == null || privateKey.isEmpty)
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
              privateKeyB64: privateKey,
              args: spec.argsJson,
              host: spec.host,
            );
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

    // Build arg for Lua: { input: <initialArg?>, calls: { label: json, ... } }
    final Map<String, dynamic> arg = <String, dynamic>{
      'input': plan.initialArg,
      'calls': callOutputs,
    };
    final String jsonArg = json.encode(arg);

    final String luaSourceWithHelper = _injectHelpers(plan.luaSource);
    final String? luaOut =
        _bridge.luaExec(script: luaSourceWithHelper, jsonArg: jsonArg);
    if (luaOut == null || luaOut.trim().isEmpty) {
      return ScriptRunResult(ok: false, error: 'Lua execution returned empty');
    }

    try {
      final Map<String, dynamic> obj =
          json.decode(luaOut) as Map<String, dynamic>;
      final bool ok = (obj['ok'] as bool?) ?? false;
      if (!ok) {
        return ScriptRunResult(
            ok: false, error: (obj['error'] as String?) ?? 'Lua error');
      }
      final dynamic result = obj['result'];
      // If Lua requests a follow-up call, perform it now
      if (result is Map<String, dynamic> &&
          (result['action'] as String?) == 'call') {
        final String canisterId =
            (result['canister_id'] as String?)?.trim() ?? '';
        final String method = (result['method'] as String?)?.trim() ?? '';
        final int kind = (result['kind'] as num?)?.toInt() ?? 0;
        final String args = (result['args'] as String?) ?? '()';
        final String? host = (result['host'] as String?)?.trim().isEmpty == true
            ? null
            : result['host'] as String?;
        final String? key = (result['private_key_b64'] as String?)?.trim();
        final String? identityId = (result['identity_id'] as String?)?.trim();
        final bool isAnonymous = (result['is_anonymous'] as bool?) ?? false;

        if (canisterId.isEmpty || method.isEmpty) {
          return ScriptRunResult(
              ok: false, error: 'call action missing canister_id/method');
        }

        // Create a temporary CanisterCallSpec to reuse identity resolution logic
        final CanisterCallSpec tempSpec = CanisterCallSpec(
          label: 'follow_up_call',
          canisterId: canisterId,
          method: method,
          kind: kind,
          argsJson: args,
          host: host,
          privateKeyB64: key,
          identityId: identityId,
          isAnonymous: isAnonymous,
        );

        final String? privateKey;
        try {
          privateKey = await _resolveIdentity(tempSpec);
        } catch (e) {
          return ScriptRunResult(
              ok: false,
              error: 'Failed to resolve identity for follow-up call: $e');
        }

        final String? callOut;
        if (privateKey == null || privateKey.isEmpty) {
          callOut = _bridge.callAnonymous(
              canisterId: canisterId,
              method: method,
              kind: kind,
              args: args,
              host: host);
        } else {
          callOut = _bridge.callAuthenticated(
            canisterId: canisterId,
            method: method,
            kind: kind,
            privateKeyB64: privateKey,
            args: args,
            host: host,
          );
        }
        if (callOut == null || callOut.trim().isEmpty) {
          return ScriptRunResult(
              ok: false, error: 'Follow-up call returned empty');
        }
        try {
          final dynamic parsed = json.decode(callOut);
          return ScriptRunResult(ok: true, result: parsed);
        } catch (e) {
          return ScriptRunResult(ok: true, result: callOut);
        }
      }
      // Batch of follow-up calls
      if (result is Map<String, dynamic> &&
          (result['action'] as String?) == 'batch') {
        final List<dynamic> calls =
            (result['calls'] as List<dynamic>? ?? const <dynamic>[]);
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
          final String canisterId =
              (item['canister_id'] as String?)?.trim() ?? '';
          final String method = (item['method'] as String?)?.trim() ?? '';
          final int kind = (item['kind'] as num?)?.toInt() ?? 0;
          final String args = (item['args'] as String?) ?? '()';
          final String? host = (item['host'] as String?)?.trim().isEmpty == true
              ? null
              : item['host'] as String?;
          final String? key = (item['private_key_b64'] as String?)?.trim();
          final String? identityId = (item['identity_id'] as String?)?.trim();
          final bool isAnonymous = (item['is_anonymous'] as bool?) ?? false;

          if (canisterId.isEmpty || method.isEmpty) {
            return ScriptRunResult(
                ok: false, error: 'batch call missing canister_id/method');
          }

          // Create a temporary CanisterCallSpec to reuse identity resolution logic
          final CanisterCallSpec tempSpec = CanisterCallSpec(
            label: label.isEmpty ? 'batch_call' : label,
            canisterId: canisterId,
            method: method,
            kind: kind,
            argsJson: args,
            host: host,
            privateKeyB64: key,
            identityId: identityId,
            isAnonymous: isAnonymous,
          );

          final String? privateKey;
          try {
            privateKey = await _resolveIdentity(tempSpec);
          } catch (e) {
            return ScriptRunResult(
                ok: false,
                error:
                    'Failed to resolve identity for batch call "$label": $e');
          }

          String? callOut;
          if (privateKey == null || privateKey.isEmpty) {
            callOut = _bridge.callAnonymous(
                canisterId: canisterId,
                method: method,
                kind: kind,
                args: args,
                host: host);
          } else {
            callOut = _bridge.callAuthenticated(
              canisterId: canisterId,
              method: method,
              kind: kind,
              privateKeyB64: privateKey,
              args: args,
              host: host,
            );
          }
          if (callOut == null || callOut.trim().isEmpty) {
            return ScriptRunResult(
                ok: false, error: 'Follow-up call returned empty for $label');
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
      if (result is Map<String, dynamic> &&
          (result['action'] as String?) == 'ui') {
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
      final String canisterId =
          (action['canister_id'] as String?)?.trim() ?? '';
      final String method = (action['method'] as String?)?.trim() ?? '';
      final int kind = (action['kind'] as num?)?.toInt() ?? 0;
      final String args = (action['args'] as String?) ?? '()';
      final String? host = (action['host'] as String?)?.trim().isEmpty == true
          ? null
          : action['host'] as String?;
      final String? key = (action['private_key_b64'] as String?)?.trim();
      final String? identityId = (action['identity_id'] as String?)?.trim();
      final bool isAnonymous = (action['is_anonymous'] as bool?) ?? false;

      if (canisterId.isEmpty || method.isEmpty) {
        return ScriptRunResult(
            ok: false, error: 'call action missing canister_id/method');
      }

      // Create a temporary CanisterCallSpec to reuse identity resolution logic
      final CanisterCallSpec tempSpec = CanisterCallSpec(
        label: 'action_call',
        canisterId: canisterId,
        method: method,
        kind: kind,
        argsJson: args,
        host: host,
        privateKeyB64: key,
        identityId: identityId,
        isAnonymous: isAnonymous,
      );

      final String? privateKey;
      try {
        privateKey = await _resolveIdentity(tempSpec);
      } catch (e) {
        return ScriptRunResult(
            ok: false, error: 'Failed to resolve identity for action call: $e');
      }

      String? callOut;
      if (privateKey == null || privateKey.isEmpty) {
        callOut = _bridge.callAnonymous(
            canisterId: canisterId,
            method: method,
            kind: kind,
            args: args,
            host: host);
      } else {
        callOut = _bridge.callAuthenticated(
          canisterId: canisterId,
          method: method,
          kind: kind,
          privateKeyB64: privateKey,
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
      final List<dynamic> calls =
          (action['calls'] as List<dynamic>? ?? const <dynamic>[]);
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
        final String canisterId =
            (item['canister_id'] as String?)?.trim() ?? '';
        final String method = (item['method'] as String?)?.trim() ?? '';
        final int kind = (item['kind'] as num?)?.toInt() ?? 0;
        final String args = (item['args'] as String?) ?? '()';
        final String? host = (item['host'] as String?)?.trim().isEmpty == true
            ? null
            : item['host'] as String?;
        final String? key = (item['private_key_b64'] as String?)?.trim();
        final String? identityId = (item['identity_id'] as String?)?.trim();
        final bool isAnonymous = (item['is_anonymous'] as bool?) ?? false;

        if (canisterId.isEmpty || method.isEmpty) {
          return ScriptRunResult(
              ok: false, error: 'batch call missing canister_id/method');
        }

        // Create a temporary CanisterCallSpec to reuse identity resolution logic
        final CanisterCallSpec tempSpec = CanisterCallSpec(
          label: label.isEmpty ? 'batch_call' : label,
          canisterId: canisterId,
          method: method,
          kind: kind,
          argsJson: args,
          host: host,
          privateKeyB64: key,
          identityId: identityId,
          isAnonymous: isAnonymous,
        );

        final String? privateKey;
        try {
          privateKey = await _resolveIdentity(tempSpec);
        } catch (e) {
          return ScriptRunResult(
              ok: false,
              error: 'Failed to resolve identity for batch call "$label": $e');
        }

        String? callOut;
        if (privateKey == null || privateKey.isEmpty) {
          callOut = _bridge.callAnonymous(
              canisterId: canisterId,
              method: method,
              kind: kind,
              args: args,
              host: host);
        } else {
          callOut = _bridge.callAuthenticated(
            canisterId: canisterId,
            method: method,
            kind: kind,
            privateKeyB64: privateKey,
            args: args,
            host: host,
          );
        }
        if (callOut == null || callOut.trim().isEmpty) {
          return ScriptRunResult(
              ok: false,
              error:
                  'Follow-up call returned empty for ${label.isEmpty ? method : label}');
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
    // Provide searchable helpers the script can call.
    final String helpers =
        'function icp_call(spec) spec = spec or {}; spec.action = "call"; return spec end\n'
        'function icp_batch(calls) calls = calls or {}; return { action = "batch", calls = calls } end\n'
        'function icp_message(text) return { action = "message", text = tostring(text or "") } end\n'
        'function icp_ui_list(spec) spec = spec or {}; local items = spec.items or {}; local buttons = spec.buttons or {}; return { action = "ui", ui = { type = "list", items = items, buttons = buttons } } end\n'
        'function icp_result_display(spec) spec = spec or {}; return { action = "ui", ui = { type = "result_display", props = spec } } end\n'
        'function icp_searchable_list(spec) spec = spec or {}; return { action = "ui", ui = { type = "list", props = { searchable = true, items = spec.items or {}, title = spec.title or "Results", searchable = spec.searchable ~= false } } } end\n'
        'function icp_section(title, content) return { type = "section", props = { title = title }, children = content and { content } or {} } end\n'
        'function icp_table(data) return { action = "ui", ui = { type = "result_display", props = { data = data, title = "Table Data" } } } end\n'
        'function icp_format_number(value, decimals) return tostring(tonumber(value) or 0) end\n'
        'function icp_format_icp(value, decimals) local v = tonumber(value) or 0; local d = decimals or 8; return tostring(v / math.pow(10, d)) end\n'
        'function icp_format_timestamp(value) local t = tonumber(value) or 0; return tostring(t) end\n'
        'function icp_format_bytes(value) local b = tonumber(value) or 0; return tostring(b) end\n'
        'function icp_truncate(text, maxLen) return tostring(text) end\n'
        'function icp_filter_items(items, field, value) local filtered = {}; for i, item in ipairs(items) do if string.find(tostring(item[field] or ""), tostring(value), 1, true) then table.insert(filtered, item) end end return filtered end\n'
        'function icp_sort_items(items, field, ascending) local sorted = {}; for i, item in ipairs(items) do sorted[i] = item end table.sort(sorted, function(a, b) local av = tostring(a[field] or ""); local bv = tostring(b[field] or ""); if ascending then return av < bv else return av > bv end end) return sorted end\n'
        'function icp_group_by(items, field) local groups = {}; for i, item in ipairs(items) do local key = tostring(item[field] or "unknown"); if not groups[key] then groups[key] = {} end table.insert(groups[key], item) end return groups end\n';
    return '$helpers$src';
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

/// Runtime host for TEA-style Lua app: init/view/update + effects execution.
class ScriptAppRuntime implements IScriptAppRuntime {
  ScriptAppRuntime(this._bridge);
  final ScriptBridge _bridge;

  @override
  Future<Map<String, dynamic>> init(
      {required String script,
      Map<String, dynamic>? initialArg,
      int budgetMs = 50}) async {
    final String? out = _bridge.luaAppInit(
        script: script,
        jsonArg: initialArg == null ? null : json.encode(initialArg),
        budgetMs: budgetMs);
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
  Future<Map<String, dynamic>> view(
      {required String script,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    final String? out = _bridge.luaAppView(
        script: script, stateJson: json.encode(state), budgetMs: budgetMs);
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
  Future<Map<String, dynamic>> update(
      {required String script,
      required Map<String, dynamic> msg,
      required Map<String, dynamic> state,
      int budgetMs = 50}) async {
    final String? out = _bridge.luaAppUpdate(
        script: script,
        msgJson: json.encode(msg),
        stateJson: json.encode(state),
        budgetMs: budgetMs);
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
