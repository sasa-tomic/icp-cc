// R-3b WU-0 — pure-Dart types for the IC-agent Web bridge.
//
// These types are shared between the Web engine (`ic_agent_engine.dart`,
// browser-only) and the VM stub (`ic_agent_engine_vm_stub.dart`), so they MUST
// stay pure-Dart (no `dart:js_interop`) — exactly like
// `quickjs_probe_result.dart` is the pure-Dart contract shared by the quickjs
// engine and its VM stub. This keeps `native_bridge_web.dart` VM-compilable
// when WU-2+ wires the conditional import.
library;

/// The result of an anonymous/authenticated canister query — the Web mirror of
/// the native `{ok,result}` / `{ok,kind,error}` envelope (`ffi.rs:78-87`).
class IcAgentQueryResult {
  IcAgentQueryResult({required this.ok, this.replyBase64, this.kind, this.error});

  final bool ok;
  /// Base64 of the raw candid reply bytes (present when `ok` is true).
  final String? replyBase64;
  /// Error discriminator on failure (`net`, etc.) — parity with
  /// `ffi.rs:68-74`.
  final String? kind;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        if (ok) 'replyBase64': replyBase64 else 'kind': kind,
        if (!ok) 'error': error,
      };
}

/// Thrown when the agent-js bundle fails to load or the HttpAgent can't be
/// created. Typed so the readiness gate (WU-5) can render a friendly panel
/// rather than a raw error.
class IcAgentLoadException implements Exception {
  IcAgentLoadException(this.message);
  final String message;
  @override
  String toString() => 'IcAgentLoadException: $message';
}

/// Readiness type for the IC-agent gate (WU-5 renders the panel). Mirrors the
/// `QuickJsReadiness` shape from `native_bridge.dart`.
sealed class IcAgentReadiness {
  const IcAgentReadiness();
}

final class IcAgentReady extends IcAgentReadiness {
  const IcAgentReady({required this.version});
  final String version;
}

final class IcAgentUnavailable extends IcAgentReadiness {
  const IcAgentUnavailable({required this.reason, this.detail});
  final String reason;
  final String? detail;
}
