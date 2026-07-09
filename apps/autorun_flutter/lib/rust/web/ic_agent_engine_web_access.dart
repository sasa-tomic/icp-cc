// R-3b WU-0 — Web-only IC-agent access (the singleton + query wrappers).
//
// This file is the WEB side of a conditional import that WU-2+ will wire into
// `native_bridge_web.dart` (so that file stays pure-Dart / VM-compilable, like
// the `quickjs_engine_web_access.dart` / `_vm_stub.dart` split). It imports the
// browser-only [WebIcAgent] (`dart:js_interop`), so it MUST NOT be compiled on
// the VM — the matching `ic_agent_engine_vm_stub.dart` is selected there (via
// `if (dart.library.io)`).
//
// The probe entrypoint (`web_probe_agent_main.dart`) also uses this module so
// the access path is exercised end-to-end (not just the raw engine).
library;

import 'ic_agent_engine.dart';
import 'ic_agent_types.dart';

export 'ic_agent_types.dart';

WebIcAgent? _webAgent;
Future<WebIcAgent>? _webAgentFuture;
String? _lastProxyOrigin;

/// Lazily create + cache the singleton anonymous agent for [proxyOrigin].
/// Concurrent callers share the same load future (idempotent). A failed load
/// stays failed (re-awaiting rethrows) so the readiness gate reports it loudly.
Future<WebIcAgent> _sharedAgent({required String proxyOrigin}) {
  final cached = _webAgent;
  if (cached != null) return Future.value(cached);
  // If a load is in flight for a DIFFERENT origin, drop it (the proxy origin
  // is app-lifetime-constant in practice; this guard just keeps the cache
  // honest if a test/probe changes it).
  if (_webAgentFuture != null && _lastProxyOrigin != proxyOrigin) {
    _webAgentFuture = null;
  }
  _lastProxyOrigin = proxyOrigin;
  return _webAgentFuture ??= WebIcAgent.bootstrap(proxyOrigin: proxyOrigin).then(
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

/// Web readiness probe: loads (or returns the cached) singleton agent for
/// [proxyOrigin]. [IcAgentReady] once created; [IcAgentUnavailable] (friendly
/// reason) if the bundle failed to load — the host renders a panel rather than
/// throwing.
Future<IcAgentReadiness> probeIcAgentReadiness({
  required String proxyOrigin,
}) async {
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
