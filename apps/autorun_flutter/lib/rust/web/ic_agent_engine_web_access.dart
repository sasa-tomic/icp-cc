// R-3b WU-0/WU-2 — Web-only IC-agent access (the singleton + query wrappers).
//
// This file is the WEB side of a conditional import that WU-2 wires into
// `native_bridge_web.dart` (so that file stays pure-Dart / VM-compilable, like
// the `quickjs_engine_web_access.dart` / `_vm_stub.dart` split). It imports the
// browser-only [WebIcAgent] (`dart:js_interop`), so it MUST NOT be compiled on
// the VM — the matching `ic_agent_engine_vm_stub.dart` is selected there (via
// `if (dart.library.io)`).
//
// The probe entrypoint (`web_probe_agent_main.dart`) also uses this module so
// the access path is exercised end-to-end (not just the raw engine).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'ic_agent_engine.dart';
import 'ic_agent_types.dart';

export 'ic_agent_types.dart';

WebIcAgent? _webAgent;
Future<WebIcAgent>? _webAgentFuture;
String? _lastProxyOrigin;

/// Resolve the backend CORS-proxy origin (the agent routes every IC request
/// through `${proxyOrigin}/api/v1/ic/...`, plan §7.3.1).
///
/// Single source of truth on Web, mirroring the PoC pattern (the
/// `IC_AGENT_PROXY_HOST` dart-define, used by `just verify-ic-agent-web`):
///   1. `IC_AGENT_PROXY_HOST` dart-define (explicit override — used by the
///      probe + dev `flutter run web` against a local backend).
///   2. Fallback: the page's own origin (`window.location.origin`). In
///      production the backend proxy is reverse-proxied at the SAME origin as
///      the frontend (`${origin}/api/v1/ic`), so this is correct without any
///      configuration.
///
/// Resolved lazily (never at top-level `const` evaluation — `window` is only
/// available at runtime). Pure web: no `dart:io` / `Platform.environment`
/// (which is unavailable / empty on Web), so this does NOT consult
/// `AppConfig.apiEndpoint` (that path is VM-only).
String _resolveProxyOrigin() {
  const override = String.fromEnvironment('IC_AGENT_PROXY_HOST');
  if (override.isNotEmpty) return override;
  final loc = globalContext.getProperty<JSObject>('location'.toJS);
  return loc.getProperty<JSString>('origin'.toJS).toDart;
}

/// Lazily create + cache the singleton anonymous agent for [proxyOrigin].
/// Concurrent callers share the same load future (idempotent). A failed load
/// stays failed (re-awaiting rethrows) so the readiness gate reports it loudly.
Future<WebIcAgent> _sharedAgent({String? proxyOrigin}) {
  final origin = proxyOrigin ?? _resolveProxyOrigin();
  final cached = _webAgent;
  if (cached != null) return Future.value(cached);
  // If a load is in flight for a DIFFERENT origin, drop it (the proxy origin
  // is app-lifetime-constant in practice; this guard just keeps the cache
  // honest if a test/probe changes it).
  if (_webAgentFuture != null && _lastProxyOrigin != origin) {
    _webAgentFuture = null;
  }
  _lastProxyOrigin = origin;
  return _webAgentFuture ??= WebIcAgent.bootstrap(proxyOrigin: origin).then(
    (a) {
      _webAgent = a;
      return a;
    },
  );
}

/// The loaded agent, or a loud [StateError] if the readiness gate has not been
/// awaited first. Mirrors `quickjs_engine_web_access.dart`'s `_requireEngine`.
WebIcAgent _requireAgent() {
  final agent = _webAgent;
  if (agent == null) {
    throw StateError(
        'IC agent not loaded on Web — probeIcAgentReadiness() must be awaited '
        '(via the readiness gate) before invoking canister calls.');
  }
  return agent;
}

/// Web readiness probe: loads (or returns the cached) singleton agent. With no
/// [proxyOrigin], resolves it via [_resolveProxyOrigin]. [IcAgentReady] once
/// created; [IcAgentUnavailable] (friendly reason) if the bundle failed to load
/// — the host renders a panel rather than throwing.
Future<IcAgentReadiness> probeIcAgentReadiness({String? proxyOrigin}) async {
  try {
    final agent = await _sharedAgent(proxyOrigin: proxyOrigin);
    return IcAgentReady(version: agent.version);
  } catch (e) {
    return IcAgentUnavailable(
      reason: 'IC agent unavailable',
      detail: 'The in-browser agent-js bundle failed to load or the backend '
          'CORS proxy is unreachable, so canister calls cannot run in this '
          'tab. Reload the page to try again.\n$e',
    );
  }
}

/// `fetchCandid` (WU-2) — fetch a canister's `.did` via agent-js's
/// `fetchCandid` (certified `read_state` for `candid:service` + the
/// `__get_candid_interface_tmp_hack` fallback). Routes through the singleton
/// agent (and thus the CORS proxy). Lazily loads the agent on first use
/// (mirrors the "lazy-load only when a call is emitted" design, §7.8.1).
///
/// Returns the raw candid TEXT or `null` on any failure (network / no candid
/// metadata) — parity with native `null_c_string` on `Err`. NEVER throws
/// (errors surface as `null`, which the caller maps to a friendly message).
Future<String?> webFetchCandid({required String canisterId}) async {
  try {
    final agent = await _sharedAgent(proxyOrigin: null);
    return agent.fetchCandid(canisterId);
  } catch (e) {
    // Loud-but-caught: the contract is `null` on failure (parity with native),
    // and the readiness gate / caller surfaces the failure to the user. We do
    // NOT swallow silently — the singleton load failure is already surfaced by
    // `probeIcAgentReadiness` (which the UI calls before reaching here); a
    // fetchCandid failure (e.g. canister has no candid metadata) is an
    // expected, user-visible "could not load interface" outcome, not a bug.
    return null;
  }
}

/// callAnonymous parity (WU-3) — anonymous canister call via the singleton
/// agent. Returns the native `{ok,result}` / `{ok,kind,error}` envelope string
/// (never throws — errors surface as the typed `kind` envelope, parity with
/// native's `canister_err_ptr`, `ffi.rs:78-87`).
///
/// [args] supports:
/// - `()` / empty → empty args
/// - `base64:` prefix → raw bytes passthrough (plan §7.5 (γ))
/// - JSON → `build_args_from_json` parity (fetch candid → type descriptors →
///   agent-js IDL.encode)
/// - Textual candid `(42, "hi")` → honest deviation (typed `candid` error)
Future<String> webCallAnonymous({
  required String canisterId,
  required String method,
  required int mode,
  String args = '()',
}) async {
  final agent = await _sharedAgent(proxyOrigin: null);
  return agent.callAnonymous(
    canisterId: canisterId,
    method: method,
    mode: mode,
    args: args,
  );
}

/// callAuthenticated parity (WU-4) — authenticated canister call with an
/// Ed25519 identity. [privateKeyB64] is the base64 32-byte seed. Same envelope
/// as [webCallAnonymous]. The agent is created + cached per key (byte-parity
/// with native `BasicIdentity::from_raw_key`).
Future<String> webCallAuthenticated({
  required String canisterId,
  required String method,
  required int mode,
  required String privateKeyB64,
  String args = '()',
}) async {
  final agent = await _sharedAgent(proxyOrigin: null);
  return agent.callAuthenticated(
    canisterId: canisterId,
    method: method,
    mode: mode,
    privateKeyB64: privateKeyB64,
    args: args,
  );
}

/// callAnonymous parity (WU-3 will wire the envelope) — anonymous query via the
/// singleton agent. [argBase64] = pre-encoded candid args (empty = no args).
Future<IcAgentQueryResult> webQueryAnonymous({
  required String canisterId,
  required String method,
  String argBase64 = '',
}) =>
    _requireAgent().queryAnonymous(
      canisterId: canisterId,
      method: method,
      argBase64: argBase64,
    );

/// Decode a candid `text` reply via the singleton agent's IDL runtime.
String webDecodeText(String replyBase64) =>
    _requireAgent().decodeText(replyBase64);
