// R-3b WU-0 — agent-js (IC HTTP agent) browser primitive (dart:js_interop facade).
//
// Drives the vendored `@dfinity/agent` browser bundle
// (`web/vendor/ic_agent/ic_agent.bundle.js`, loaded via a `<script type=module>`
// in `web/index.html`) from Dart. This is the Web-side IC-agent primitive that
// R-3b WU-2+ builds on (`fetchCandid`, `callAnonymous`, `callAuthenticated`).
//
// ## Why this is web-only
// Uses `dart:js_interop` + `dart:js_interop_unsafe` (browser globals). This
// file is imported ONLY by the probe entrypoint (`web_probe_agent_main.dart`)
// and, in WU-2+, by `ic_agent_engine_web_access.dart` (the conditional-import
// access module that keeps `native_bridge_web.dart` VM-compilable). It never
// compiles for the VM / native targets.
//
// ## The interop contract established here (reused by WU-2+)
// The vendored bundle installs `globalThis.__icpCcAgent`:
//   {
//     version: string,
//     createAnonymousAgent(proxyOrigin: string) => Promise<agent>,
//     query(agent, canisterId, methodName, argBase64) =>
//         Promise<{ok:true, replyBase64} | {ok:false, kind, error}>,
//     decodeText(replyBase64) => string
//   }
// `proxyOrigin` is the backend origin (e.g. http://127.0.0.1:58000). The agent
// THINKS it's talking to ic0.app (mainnet root key baked in) but a custom
// `fetch` rewrites every request to `${proxyOrigin}/api/v1/ic/...` (the CORS
// byte-relay proxy, WU-1). All cross-boundary payloads are STRINGS (canisterId,
// methodName, base64 args/reply) — no shared-JS-handle lifetime, matching the
// R-3a discipline.
//
// ## Args encoding (plan §7.5)
// This PoC supports the (γ) `base64:` raw-bytes path: `argBase64` is the
// pre-encoded candid args (base64). Empty string = empty args (encoded as
// `IDL.encode([],[])` inside the bundle). The JSON/textual-args path (which
// needs a did parser) is deferred to WU-3.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'ic_agent_types.dart';

export 'ic_agent_types.dart'
    show IcAgentQueryResult, IcAgentLoadException, IcAgentReadiness;

// ─────────────────────────────────────────────────────────────────────────────
// JS facade — `@ JS()` extension type over the vendored `__icpCcAgent` global.
// ─────────────────────────────────────────────────────────────────────────────
// JS facade — `@JS()` extension type over the vendored `__icpCcAgent` global.
// ─────────────────────────────────────────────────────────────────────────────

/// `globalThis.__icpCcAgent` — the bridge object the vendored bundle installs.
/// See `web/vendor/ic_agent/ic_agent_entry.mjs`.
@JS('__icpCcAgent')
extension type _IcAgentGlobal._(JSObject _) implements JSObject {
  external JSString get version;
  /// Create an anonymous HttpAgent routed through the CORS proxy. Returns the
  /// opaque agent handle (pass to [query]).
  external JSPromise<JSObject> createAnonymousAgent(JSString proxyOrigin);
  /// Anonymous query. `argBase64` = base64 of pre-encoded candid args ('' =
  /// empty args). Returns the result envelope object.
  external JSPromise<JSObject> query(
    JSObject agent,
    JSString canisterId,
    JSString methodName,
    JSString argBase64,
  );
  /// Decode a candid `text` reply (base64 → string).
  external JSString decodeText(JSString replyBase64);
}

// ─────────────────────────────────────────────────────────────────────────────
// WebIcAgent — loads the bundle global once, then exposes the primitive.
// ─────────────────────────────────────────────────────────────────────────────

/// Drives the vendored agent-js bundle from Dart. One instance owns one
/// anonymous `HttpAgent` (created with `host: ic0.app` + a custom `fetch`
/// rewriting to the proxy). WU-2+ will layer `fetchCandid` / `callAnonymous` /
/// `callAuthenticated` on top.
class WebIcAgent {
  WebIcAgent._(this._global, this._agent, this.version);

  final _IcAgentGlobal _global;
  final JSObject _agent;
  final String version;

  /// Wait for the vendored bundle to install `globalThis.__icpCcAgent`, then
  /// create an anonymous HttpAgent routed through the backend CORS proxy at
  /// [proxyOrigin] (e.g. `http://127.0.0.1:58000`).
  ///
  /// Throws loudly on any failure (never silently no-ops) — the readiness gate
  /// (WU-2+) surfaces this as an `IcAgentUnavailable` panel.
  static Future<WebIcAgent> bootstrap({
    required String proxyOrigin,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final global = await _waitForGlobal(timeout);
    final version = global.version.toDart;
    final JSObject agent;
    try {
      agent = await global.createAnonymousAgent(proxyOrigin.toJS).toDart;
    } catch (e) {
      throw IcAgentLoadException(
        'agent-js HttpAgent.create failed: ${_jsErrString(e)}',
      );
    }
    return WebIcAgent._(global, agent, version);
  }

  /// Poll `globalThis.__icpCcAgent` until the bundle installs it.
  static Future<_IcAgentGlobal> _waitForGlobal(Duration timeout) async {
    final key = '__icpCcAgent'.toJS;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (globalContext.hasProperty(key).toDart) {
        return globalContext.getProperty<_IcAgentGlobal>(key);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw IcAgentLoadException(
      'globalThis.__icpCcAgent not found within ${timeout.inSeconds}s — '
      'did the vendored bundle (web/vendor/ic_agent/ic_agent.bundle.js) load? '
      'Check the <script type="module"> in web/index.html.',
    );
  }

  /// Perform an anonymous query against [canisterId].[method] with pre-encoded
  /// candid args ([argBase64]; empty = no args — the (γ) base64 raw-bytes path,
  /// plan §7.5). Returns the [IcAgentQueryResult] envelope (never throws —
  /// errors surface as `{ok:false, kind:"net", error}`).
  Future<IcAgentQueryResult> queryAnonymous({
    required String canisterId,
    required String method,
    String argBase64 = '',
  }) async {
    final JSObject res;
    try {
      res = await _global
          .query(_agent, canisterId.toJS, method.toJS, argBase64.toJS)
          .toDart;
    } catch (e) {
      return IcAgentQueryResult(
          ok: false, kind: 'net', error: _jsErrString(e));
    }
    final ok = (res.getProperty<JSBoolean>('ok'.toJS)).toDart;
    if (ok) {
      final reply =
          res.getProperty<JSString>('replyBase64'.toJS).toDart;
      return IcAgentQueryResult(ok: true, replyBase64: reply);
    }
    final kind =
        res.getProperty<JSString?>('kind'.toJS)?.toDart ?? 'net';
    final error =
        res.getProperty<JSString?>('error'.toJS)?.toDart ?? 'unknown error';
    return IcAgentQueryResult(ok: false, kind: kind, error: error);
  }

  /// Decode a candid `text` reply (base64 of the reply bytes → the string).
  /// Used by the PoC to decode the ICP ledger `symbol` reply ("ICP"). WU-2+
  /// will add typed decode helpers over the same IDL runtime.
  String decodeText(String replyBase64) =>
      _global.decodeText(replyBase64.toJS).toDart;
}

// ─────────────────────────────────────────────────────────────────────────────
// Marshalling helpers.
// ─────────────────────────────────────────────────────────────────────────────

/// Render a thrown JS error to a string (name + message, like the quickjs
/// helper). agent-js errors carry a `message` (and sometimes `name`).
String _jsErrString(Object e) {
  try {
    final obj = e as JSObject;
    if (obj.typeofEquals('object')) {
      final name = obj.getProperty<JSString?>('name'.toJS)?.toDart;
      final msg = obj.getProperty<JSString?>('message'.toJS)?.toDart;
      if (name != null || msg != null) {
        return [name, msg].whereType<String>().join(': ');
      }
    }
  } catch (_) {
    // e was not a JSObject — fall through.
  }
  return e.toString();
}
