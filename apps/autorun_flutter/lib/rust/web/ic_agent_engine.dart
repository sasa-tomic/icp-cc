// R-3b WU-0/WU-2 — agent-js (IC HTTP agent) browser primitive (dart:js_interop facade).
//
// Drives the vendored `@dfinity/agent` browser bundle
// (`web/vendor/ic_agent/ic_agent.bundle.js`, loaded via a `<script type=module>`
// in `web/index.html`) from Dart. This is the Web-side IC-agent primitive that
// R-3b WU-2 (`fetchCandid`) + WU-3+ (`callAnonymous`, `callAuthenticated`)
// builds on.
//
// ## Why this is web-only
// Uses `dart:js_interop` + `dart:js_interop_unsafe` (browser globals). This
// file is imported ONLY by the probe entrypoint (`web_probe_agent_main.dart`)
// and by `ic_agent_engine_web_access.dart` (the conditional-import access
// module that keeps `native_bridge_web.dart` VM-compilable). It never compiles
// for the VM / native targets.
//
// ## The interop contract established here (reused by WU-2+)
// The vendored bundle installs `globalThis.__icpCcAgent`:
//   {
//     version: string,
//     createAnonymousAgent(proxyOrigin: string) => Promise<agent>,
//     fetchCandid(agent, canisterId) => Promise<string | null>,   // WU-2
//     query(agent, canisterId, methodName, argBase64) =>
//         Promise<{ok:true, replyBase64} | {ok:false, kind, error}>,
//     decodeText(replyBase64) => string
//   }
// `proxyOrigin` is the backend origin (e.g. http://127.0.0.1:58000). The agent
// THINKS it's talking to ic0.app (mainnet root key baked in) but a custom
// `fetch` rewrites every request to `${proxyOrigin}/api/v1/ic/...` (the CORS
// byte-relay proxy, WU-1). All cross-boundary payloads are STRINGS (canisterId,
// methodName, base64 args/reply, did text) — no shared-JS-handle lifetime,
// matching the R-3a discipline.
//
// ## fetchCandid (WU-2)
// Delegates to agent-js's `fetchCandid(canisterId, agent)` (`fetch_candid.ts`):
// a certified `read_state` for the `candid:service` metadata + the
// `__get_candid_interface_tmp_hack` query fallback. Exact parity with native
// `read_state_canister_metadata(canister, "candid:service")`
// (`canister_client.rs:545`). Returns the did TEXT (string) or `null` if the
// canister exposes no candid interface.
//
// ## Args encoding (plan §7.5)
// The PoC supports the (γ) `base64:` raw-bytes path: `argBase64` is the
// pre-encoded candid args (base64). Empty string = empty args (encoded as
// `IDL.encode([],[])` inside the bundle). The JSON/textual-args path (which
// needs a did parser) is deferred to WU-3; `parseCandid` (WU-2) is a separate
// pure-Dart port (`candid_interface_parser.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'candid_interface_parser.dart';
import 'ic_agent_types.dart';

export 'ic_agent_types.dart'
    show IcAgentQueryResult, IcAgentLoadException, IcAgentReadiness;

// ─────────────────────────────────────────────────────────────────────────────
// JS facade — `@JS()` extension type over the vendored `__icpCcAgent` global.
// ─────────────────────────────────────────────────────────────────────────────

/// `globalThis.__icpCcAgent` — the bridge object the vendored bundle installs.
/// See `web/vendor/ic_agent/ic_agent_entry.mjs`.
@JS('__icpCcAgent')
extension type _IcAgentGlobal._(JSObject _) implements JSObject {
  external JSString get version;
  /// Validate a canister ID (principal text) — true if agent-js can parse it.
  /// Parity with native `Principal::from_text` (`canister_client.rs:578`).
  external JSBoolean validateCanisterId(JSString canisterId);
  /// Create an anonymous HttpAgent routed through the CORS proxy. Returns the
  /// opaque agent handle (pass to [query] / [update] / [fetchCandid]).
  external JSPromise<JSObject> createAnonymousAgent(JSString proxyOrigin);
  /// R-3b WU-4 — create an authenticated HttpAgent with an Ed25519 identity
  /// from the 32-byte seed (`Ed25519KeyIdentity.fromSecretKey`). Byte-parity
  /// with native `BasicIdentity::from_raw_key` (`canister_client.rs:674`).
  external JSPromise<JSObject> createAuthenticatedAgent(
    JSString proxyOrigin,
    JSString privateKeyB64,
  );
  /// Fetch a canister's `.did` interface (agent-js `fetchCandid`). Returns the
  /// did TEXT, or `null` if the canister exposes no candid interface. Routed
  /// through the proxy (certified `read_state` + `__get_candid_interface_tmp`
  /// fallback).
  external JSPromise<JSString?> fetchCandid(JSObject agent, JSString canisterId);
  /// Anonymous query. `argBase64` = base64 of pre-encoded candid args ('' =
  /// empty args). Returns the result envelope object.
  external JSPromise<JSObject> query(
    JSObject agent,
    JSString canisterId,
    JSString methodName,
    JSString argBase64,
  );
  /// R-3b WU-3 — update call (mode 1). Submits the signed call + polls
  /// read_state for the certified reply. Same envelope shape as [query].
  external JSPromise<JSObject> update(
    JSObject agent,
    JSString canisterId,
    JSString methodName,
    JSString argBase64,
  );
  /// R-3b WU-3 — encode JSON args to candid bytes using type descriptors from
  /// the pure-Dart candid parser. `build_args_from_json` parity. Returns base64.
  external JSString encodeArgsWithTypes(
    JSString argDescsJson,
    JSString jsonArgsStr,
  );
  /// R-3b WU-3 — decode a candid reply to JSON using type descriptors.
  /// `try_decode_with_types` parity. Returns a JSON string.
  external JSString decodeReplyWithTypes(
    JSString retDescsJson,
    JSString replyBase64,
  );
  /// Decode a candid `text` reply (base64 → string).
  external JSString decodeText(JSString replyBase64);
}

// ─────────────────────────────────────────────────────────────────────────────
// WebIcAgent — loads the bundle global once, then exposes the primitive.
// ─────────────────────────────────────────────────────────────────────────────

/// Drives the vendored agent-js bundle from Dart. One instance owns one
/// anonymous `HttpAgent` (created with `host: ic0.app` + a custom `fetch`
/// rewriting to the proxy). WU-2 layers `fetchCandid` on top; WU-3/4 layer
/// `callAnonymous` / `callAuthenticated`.
class WebIcAgent {
  WebIcAgent._(this._global, this._agent, this._proxyOrigin, this.version);

  final _IcAgentGlobal _global;
  final JSObject _agent;
  final String _proxyOrigin;
  final String version;

  /// Cache: canisterId → did text (null = canister has no candid). Avoids
  /// re-fetching the `.did` on every call (native fetches per-call; the Web
  /// proxy adds latency, so caching is a pragmatic improvement that does NOT
  /// change the contract — the did is immutable for a given canister version).
  final Map<String, String?> _candidCache = <String, String?>{};

  /// Authenticated agent cache: privateKeyB64 → agent handle. One per identity
  /// (re-creating per call would re-derive the keypair + re-fetch the root key
  /// every time). The key is the base64 seed string (stable for a given keypair).
  JSObject? _authAgent;
  String? _authKey;

  /// Wait for the vendored bundle to install `globalThis.__icpCcAgent`, then
  /// create an anonymous HttpAgent routed through the backend CORS proxy at
  /// [proxyOrigin] (e.g. `http://127.0.0.1:58000`).
  ///
  /// Throws loudly on any failure (never silently no-ops) — the readiness gate
  /// (WU-5) surfaces this as an `IcAgentUnavailable` panel.
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
    return WebIcAgent._(global, agent, proxyOrigin, version);
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

  /// R-3b WU-2 — fetch a canister's Candid `.did` interface. Delegates to
  /// agent-js's `fetchCandid` (certified `read_state` for `candid:service` +
  /// the `__get_candid_interface_tmp_hack` fallback) — exact parity with native
  /// `fetch_candid` (`canister_client.rs:529`).
  ///
  /// Returns the raw did TEXT, or `null` if the canister exposes no candid
  /// interface (some canisters have neither `candid:service` metadata nor the
  /// tmp hack). Network errors throw (the access module maps them to `null`).
  Future<String?> fetchCandid(String canisterId) async {
    final JSString? did;
    try {
      did = await _global.fetchCandid(_agent, canisterId.toJS).toDart;
    } catch (e) {
      throw IcAgentLoadException('agent-js fetchCandid failed: ${_jsErrString(e)}');
    }
    return did?.toDart;
  }

  /// Fetch + cache candid for [canisterId]. Used by [callAnonymous] /
  /// [callAuthenticated] to avoid re-fetching the `.did` for both args
  /// encoding and reply decoding.
  Future<String?> _fetchCandidCached(String canisterId) async {
    if (_candidCache.containsKey(canisterId)) {
      return _candidCache[canisterId];
    }
    final did = await fetchCandid(canisterId);
    _candidCache[canisterId] = did;
    return did;
  }

  /// Perform an anonymous query against [canisterId].[method] with pre-encoded
  /// candid args ([argBase64]; empty = no args — the (γ) base64 raw-bytes path,
  /// plan §7.5). Returns the [IcAgentQueryResult] envelope (never throws —
  /// errors surface as `{ok:false, kind:"net", error}`).
  Future<IcAgentQueryResult> queryAnonymous({
    required String canisterId,
    required String method,
    String argBase64 = '',
  }) =>
      _queryWith(_agent, canisterId, method, argBase64);

  /// R-3b WU-3 — perform an update call (mode 1) against [canisterId].[method]
  /// with pre-encoded candid args. Returns the same envelope as
  /// [queryAnonymous] (never throws).
  Future<IcAgentQueryResult> updateWith({
    required String canisterId,
    required String method,
    String argBase64 = '',
  }) =>
      _updateWith(_agent, canisterId, method, argBase64);

  Future<IcAgentQueryResult> _queryWith(
      JSObject agent, String canisterId, String method, String argBase64) async {
    final JSObject res;
    try {
      res = await _global
          .query(agent, canisterId.toJS, method.toJS, argBase64.toJS)
          .toDart;
    } catch (e) {
      return IcAgentQueryResult(
          ok: false, kind: 'net', error: _jsErrString(e));
    }
    return _parseQueryResult(res);
  }

  Future<IcAgentQueryResult> _updateWith(
      JSObject agent, String canisterId, String method, String argBase64) async {
    final JSObject res;
    try {
      res = await _global
          .update(agent, canisterId.toJS, method.toJS, argBase64.toJS)
          .toDart;
    } catch (e) {
      return IcAgentQueryResult(
          ok: false, kind: 'net', error: _jsErrString(e));
    }
    return _parseQueryResult(res);
  }

  static IcAgentQueryResult _parseQueryResult(JSObject res) {
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

  // ───────────────────────────────────────────────────────────────────────
  // R-3b WU-3/WU-4 — callAnonymous / callAuthenticated (full native parity).
  //
  // These orchestrate: validate canister ID → fetch candid → encode args →
  // query/update → decode reply → build the native `{ok,result}` /
  // `{ok,kind,error}` envelope. The args encoding handles `base64:` passthrough,
  // `()` empty, and JSON (`build_args_from_json` parity via the pure-Dart
  // candid parser → type descriptors → agent-js IDL.encode). Textual candid
  // arg expressions are an honest deviation (documented, not silent).
  // ───────────────────────────────────────────────────────────────────────

  /// R-3b WU-3 — anonymous canister call. Mirrors native `call_anonymous`
  /// (`canister_client.rs:569-651`) + the FFI envelope (`ffi.rs:78-87`).
  ///
  /// Returns the JSON envelope string:
  /// - `{"ok":true,"result":<json>}` on success
  /// - `{"ok":false,"kind":"invalid_canister_id"|"net"|"candid","error":"..."}`
  ///   on failure
  ///
  /// Never throws — errors surface as the typed `kind` envelope (parity with
  /// native's `canister_err_ptr`).
  Future<String> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
  }) =>
      _callWith(_agent, canisterId, method, mode, args);

  /// R-3b WU-4 — authenticated canister call with an Ed25519 identity.
  /// Mirrors native `call_authenticated` (`canister_client.rs:653-746`).
  /// [privateKeyB64] is the base64-encoded 32-byte Ed25519 seed (the SAME
  /// bytes R-2 derives — `Ed25519KeyIdentity.fromSecretKey` ≡ native
  /// `BasicIdentity::from_raw_key`). Same envelope as [callAnonymous].
  Future<String> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
  }) async {
    final agent = await _getOrCreateAuthAgent(privateKeyB64);
    return _callWith(agent, canisterId, method, mode, args);
  }

  /// Get-or-create the authenticated agent for [privateKeyB64]. Cached per key
  /// (re-creating would re-derive the keypair + re-fetch the root key every
  /// call). The agent uses the SAME proxy as the anonymous agent.
  Future<JSObject> _getOrCreateAuthAgent(String privateKeyB64) async {
    final cached = _authAgent;
    if (cached != null && _authKey == privateKeyB64) return cached;
    final JSObject agent;
    try {
      agent = await _global
          .createAuthenticatedAgent(_proxyOrigin.toJS, privateKeyB64.toJS)
          .toDart;
    } catch (e) {
      throw _CallError('net',
          'failed to create authenticated agent: ${_jsErrString(e)}');
    }
    _authAgent = agent;
    _authKey = privateKeyB64;
    return agent;
  }

  /// The shared call flow for both anonymous + authenticated calls.
  Future<String> _callWith(
    JSObject agent,
    String canisterId,
    String method,
    int mode,
    String args,
  ) async {
    try {
      // 1. Validate canister ID (parity: native Principal::from_text first).
      if (!_global.validateCanisterId(canisterId.toJS).toDart) {
        return _errEnvelope('invalid_canister_id',
            'invalid canister id: $canisterId');
      }

      // 2. Fetch candid (cached — needed for both args encoding + reply decode).
      final did = await _fetchCandidCached(canisterId);

      // 3. Encode args.
      final argBase64 = _encodeArgs(method, args, did);

      // 4. Query (mode 0/2) or update (mode 1).
      final result = mode == 1
          ? await _updateWith(agent, canisterId, method, argBase64)
          : await _queryWith(agent, canisterId, method, argBase64);
      if (!result.ok) {
        return _errEnvelope(result.kind ?? 'net', result.error ?? 'unknown');
      }

      // 5. Decode reply (typed decode via fetched candid).
      final dynamic jsonResult =
          _decodeReply(method, result.replyBase64!, did);
      return jsonEncode(<String, dynamic>{'ok': true, 'result': jsonResult});
    } on _CallError catch (e) {
      return _errEnvelope(e.kind, e.message);
    } catch (e) {
      // Unexpected — surface loudly (never silent).
      return _errEnvelope('net', e.toString());
    }
  }

  /// Encode args to base64. Handles:
  /// - `()` / empty → empty args (IDL.encode([],[]))
  /// - `base64:` prefix → passthrough (raw bytes, plan §7.5 (γ))
  /// - JSON → `build_args_from_json` parity (fetch candid → type descriptors →
  ///   agent-js IDL.encode)
  /// - Textual candid `(42, "hi")` → honest deviation (error)
  String _encodeArgs(String method, String args, String? did) {
    final s = args.trim();
    if (s.isEmpty || s == '()') return ''; // empty args
    if (s.startsWith('base64:')) return s.substring(7); // passthrough
    if (_looksLikeJson(s)) {
      if (did == null) {
        throw _CallError('candid',
            'could not fetch candid interface for args encoding (canister may have no candid metadata)');
      }
      final descs = methodTypeDescriptors(did, method);
      if (descs == null) {
        throw _CallError('candid',
            'could not parse candid interface for method "$method"');
      }
      try {
        return _global.encodeArgsWithTypes(descs.toJS, s.toJS).toDart;
      } catch (e) {
        throw _CallError('candid',
            'args encoding failed: ${_jsErrString(e)}');
      }
    }
    // Textual candid arg expressions (e.g. `(42, "hi")`) — agent-js has no
    // `parse_idl_args` equivalent. Honest deviation (documented, not silent):
    // callers use JSON or base64: args.
    throw _CallError('candid',
        'textual candid args are not yet supported on Web '
        '(agent-js has no .did arg-expression parser); '
        'use JSON args or base64:-prefixed raw bytes');
  }

  /// Decode a candid reply to a Dart JSON value using the fetched candid's
  /// return type descriptors. Mirrors native `try_decode_with_types`
  /// (`canister_client.rs:135-159`). If candid is unavailable or the method
  /// isn't found, throws a `candid` error (honest deviation from native's
  /// typeless `IDLArgs::from_bytes` fallback, which agent-js can't do).
  dynamic _decodeReply(String method, String replyBase64, String? did) {
    if (did == null) {
      throw _CallError('candid',
          'could not fetch candid for reply decode (canister may have no candid metadata)');
    }
    final descs = methodTypeDescriptors(did, method);
    if (descs == null) {
      throw _CallError('candid',
          'could not parse candid for reply decode (method "$method" not found)');
    }
    try {
      final jsonStr =
          _global.decodeReplyWithTypes(descs.toJS, replyBase64.toJS).toDart;
      return jsonDecode(jsonStr);
    } catch (e) {
      throw _CallError('candid',
          'reply decode failed: ${_jsErrString(e)}');
    }
  }

  /// Build the error envelope `{"ok":false,"kind":"...","error":"..."}`.
  static String _errEnvelope(String kind, String error) =>
      jsonEncode(<String, dynamic>{
        'ok': false,
        'kind': kind,
        'error': error,
      });

  /// Decode a candid `text` reply (base64 of the reply bytes → the string).
  /// Used by the PoC to decode the ICP ledger `symbol` reply ("ICP"). WU-2+
  /// adds typed decode helpers over the same IDL runtime.
  String decodeText(String replyBase64) =>
      _global.decodeText(replyBase64.toJS).toDart;
}

/// Typed call error — maps to the native `CanisterClientError` variants
/// (`invalid_canister_id`, `net`, `candid`) so the envelope `kind` field
/// matches native's `canister_error_kind` (`ffi.rs:68-74`).
class _CallError implements Exception {
  _CallError(this.kind, this.message);
  final String kind; // "invalid_canister_id" | "net" | "candid"
  final String message;
  @override
  String toString() => '_CallError($kind): $message';
}

/// Detect whether [s] looks like a JSON value (vs textual candid). Mirrors
/// native `call_anonymous`'s detection (`canister_client.rs:586-598`):
/// `[`, `{`, `n`(null), `"`(string), `t`(rue), `f`(alse), digit, `-` → JSON.
bool _looksLikeJson(String s) {
  final trimmed = s.trimLeft();
  if (trimmed.isEmpty) return false;
  final c = trimmed.codeUnitAt(0);
  // `[` (91), `{` (123), `n` (110), `"` (34), `t` (116), `f` (102)
  if (c == 91 || c == 123 || c == 110 || c == 34 || c == 116 || c == 102) {
    return true;
  }
  // digit (48-57) or `-` (45)
  return (c >= 48 && c <= 57) || c == 45;
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
