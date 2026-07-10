// R-3b WU-0 — pure-Dart types for the IC-agent Web bridge.
//
// These types are shared between the Web engine (`ic_agent_engine.dart`,
// browser-only) and the VM stub (`ic_agent_engine_vm_stub.dart`), so they MUST
// stay pure-Dart (no `dart:js_interp`) — exactly like
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

// ─────────────────────────────────────────────────────────────────────────────
// W6-1 — IC-agent proxy-origin resolution + friendly error mapping.
//
// Both helpers are PURE functions split from browser I/O (reading dart-define
// + `window.location`) so the DECISION logic is unit-testable on the VM —
// exactly the seam pattern `ConnectivityService` uses (typedef probe injected
// into a pure-Dart facade). The browser wrapper in
// `ic_agent_engine_web_access.dart` reads the real values and calls these.
// ─────────────────────────────────────────────────────────────────────────────

/// Default API endpoint when no `PUBLIC_API_ENDPOINT` dart-define is set.
/// Mirrors `AppConfig._apiEndpoint`'s default so the proxy resolves to the
/// production backend without extra wiring (single dart-define key — both read
/// `PUBLIC_API_ENDPOINT`, so a build-time `--dart-define` overrides both
/// identically; this constant only matters when no define is passed).
const String kIcAgentDefaultApiEndpoint = 'https://icp-mp.kalaj.org';

/// The friendly message shown when an IC canister call can't reach its target
/// (network failure, dead proxy, wrong proxy origin). W6-1 Bug 2: raw
/// `IcAgentLoadException` dumps (HTTP status lines + server banners + HTML
/// bodies) must never be the primary user-facing text.
const String kIcReachabilityMessage =
    "Couldn't reach the canister. Check your connection and try again.";

/// Pure resolution of the IC-agent CORS-proxy origin (W6-1 Bug 1).
///
/// Priority:
///   1. [override] — `IC_AGENT_PROXY_HOST` dart-define (explicit override, used
///      by the probe + dev `flutter run web`).
///   2. [apiEndpoint] — the backend that hosts `/api/v1/ic/relay`
///      (`PUBLIC_API_ENDPOINT`). CORRECT for split-origin deploys (frontend and
///      backend on different origins). The previous fallback to
///      [locationOrigin] silently POSTed `fetchCandid` to the static file
///      server → HTTP 501 → raw exception dumped at the user.
///   3. [locationOrigin] — the page's own origin. Only correct for same-origin
///      reverse-proxy production deploys (last resort).
String resolveProxyOrigin({
  required String override,
  required String apiEndpoint,
  required String locationOrigin,
}) {
  if (override.isNotEmpty) return override;
  if (apiEndpoint.isNotEmpty) return apiEndpoint;
  return locationOrigin;
}

/// Maps a raw IC error string to a user-friendly message (W6-1 Bug 2).
///
/// Raw `IcAgentLoadException` dumps (carrying HTTP status lines, server banners
/// like `SimpleHTTP/0.6 Python/3.13.5`, and HTML `<!DOCTYPE>` bodies from a
/// misconfigured / dead proxy) are replaced with [kIcReachabilityMessage].
/// Already-friendly / typed error messages (Candid decode, invalid canister id)
/// pass through UNCHANGED — only genuinely raw transport dumps are clobbered.
String friendlyIcErrorMessage(String raw) {
  // IcAgentLoadException always carries raw transport/proxy text — never
  // surface it verbatim (W6-2: it leaks server banners + HTML bodies).
  if (raw.contains('IcAgentLoadException')) {
    return kIcReachabilityMessage;
  }
  // Detect raw HTTP-response artefacts that leaked into an error string (e.g.
  // a 'net' _CallError whose message captured a 501 HTML body via _jsErrString,
  // or a fetch() rejection carrying the response). HTML tags + HTTP headers
  // never appear in a legitimate, friendly Candid/canister-id message.
  final lower = raw.toLowerCase();
  if (lower.contains('<!doctype') ||
      lower.contains('<html') ||
      lower.contains('content-type:') ||
      lower.contains('server: simplehttp') ||
      lower.contains('connection refused') ||
      lower.contains('failed to fetch')) {
    return kIcReachabilityMessage;
  }
  return raw;
}
