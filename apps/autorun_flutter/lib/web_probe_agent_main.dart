// R-3b WU-0/WU-2 — Browser probe entrypoint for the agent-js IC-agent primitive.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the verification step:
//   flutter build web --target=lib/web_probe_agent_main.dart \
//       --dart-define=IC_AGENT_PROXY_HOST=http://127.0.0.1:<api-port>
//
// It is intentionally FLUTTER-FREE (no `WidgetsFlutterBinding` / `runApp`):
// the point is to prove the browser→proxy→IC-boundary-node path with REAL
// canister calls, not to render UI. Avoiding the binding also avoids
// auto-registering the app's web plugins (e.g. the `passkeys` Corbado SDK,
// which would throw without its bundle.js — unrelated to R-3b).
//
// The probe (WU-0 + WU-2):
//   1. Loads the vendored agent-js bundle + creates an anonymous HttpAgent
//      routed through the backend CORS proxy (`IC_AGENT_PROXY_HOST/api/v1/ic`).
//   2. (WU-2) `fetchCandid` — fetches the ICP ledger's `.did` interface through
//      the proxy (certified `read_state` for `candid:service`).
//   3. (WU-2) `parseCandid` — parses the `.did` (pure-Dart port) and asserts
//      the `symbol` method's return type matches the expected
//      `record { symbol : text }` (parity with native `parse_candid_interface`).
//   4. (WU-0) Performs ONE real anonymous query against the ledger `symbol`
//      method, then decodes the reply ("ICP") via the bundled IDL runtime
//      using the type `parseCandid` identified — the typed-decode evidence.
//   5. Publishes the result as JSON to `document.title` (polled by the
//      headless-Chromium harness) + a `<div id="agent-result">` summary.
//
// On any failure it sets `document.title` to `{"loaded":false,"error":...}` so
// the harness reports the failure loudly rather than hanging.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'rust/web/candid_interface_parser.dart';
import 'rust/web/ic_agent_engine_web_access.dart';

/// The proxy origin (backend), e.g. `http://127.0.0.1:58000`. Supplied via
/// `--dart-define=IC_AGENT_PROXY_HOST=...` by the `just verify-ic-agent-web`
/// recipe (which starts `just api-dev-up` first and reads the port).
const String _proxyHost = String.fromEnvironment(
  'IC_AGENT_PROXY_HOST',
  defaultValue: 'http://127.0.0.1:58000',
);

/// The well-known canister + method the probe exercises. The ICP ledger
/// `symbol` query returns `record { symbol : text }` (verified against the live
/// canister's fetched `.did`) — a stable, read-only, anonymous mainnet call.
const String _ledgerCanister = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _ledgerMethod = 'symbol';

Future<void> main() async {
  AgentProbeResult result;
  try {
    // 1. Load the bundle + create the anonymous agent (routed via the proxy).
    final readiness = await probeIcAgentReadiness(proxyOrigin: _proxyHost);
    if (readiness is! IcAgentReady) {
      // IcAgentUnavailable — the bundle failed to load or the proxy is
      // unreachable. Cast: IcAgentReadiness is sealed (Ready | Unavailable).
      final unavail = readiness as IcAgentUnavailable;
      result = AgentProbeResult(
        loaded: false,
        version: '',
        proxyHost: _proxyHost,
        queryOk: false,
        symbol: null,
        replyBase64: null,
        candidFetched: false,
        candidParsed: false,
        symbolRetType: null,
        error: '${unavail.reason}: ${unavail.detail ?? ''}',
      );
      _publishResult(jsonEncode(result.toJson()), result);
      return;
    }

    // 2. (WU-2) fetchCandid — the ledger's `.did` through the proxy.
    final did = await webFetchCandid(canisterId: _ledgerCanister);
    if (did == null || did.trim().isEmpty) {
      result = AgentProbeResult(
        loaded: true,
        version: readiness.version,
        proxyHost: _proxyHost,
        queryOk: false,
        symbol: null,
        replyBase64: null,
        candidFetched: false,
        candidParsed: false,
        symbolRetType: null,
        error: 'fetchCandid returned no candid interface for $_ledgerCanister',
      );
      _publishResult(jsonEncode(result.toJson()), result);
      return;
    }

    // 3. (WU-2) parseCandid — pure-Dart port. Assert the `symbol` method's
    //    return type matches the expected shape (parity with native on REAL
    //    canister metadata, not just synthetic golden vectors).
    final parsedJson = parseCandidInterface(did);
    String? symbolRetType;
    bool candidParsed = false;
    if (parsedJson != null) {
      final parsed = jsonDecode(parsedJson) as Map<String, dynamic>;
      final methods = (parsed['methods'] as List<dynamic>? ?? const <dynamic>[]);
      for (final m in methods) {
        if (m is Map<String, dynamic> && m['name'] == _ledgerMethod) {
          final rets = (m['rets'] as List<dynamic>? ?? const <dynamic>[]);
          symbolRetType = rets.isEmpty ? null : rets[0]?.toString();
          break;
        }
      }
      candidParsed = symbolRetType != null;
    }

    // 4. (WU-0) ONE real anonymous query against the ledger `symbol` method.
    final query = await webQueryAnonymous(
      canisterId: _ledgerCanister,
      method: _ledgerMethod,
    );
    if (!query.ok) {
      result = AgentProbeResult(
        loaded: true,
        version: readiness.version,
        proxyHost: _proxyHost,
        queryOk: false,
        symbol: null,
        replyBase64: null,
        candidFetched: true,
        candidParsed: candidParsed,
        symbolRetType: symbolRetType,
        error: 'query failed (${query.kind}): ${query.error}',
      );
      _publishResult(jsonEncode(result.toJson()), result);
      return;
    }

    // Decode the reply via the bundled IDL runtime. `decodeText`'s primary
    // path is `record { symbol : text }` — EXACTLY the type `parseCandid`
    // reported in step 3. So this is a typed decode driven by the parsed
    // interface: the parsed `symbolRetType` identifies the reply shape, and the
    // decode confirms it yields "ICP". (The full AST→IDL converter for
    // arbitrary methods is WU-3's §7.5 concern; for `symbol` the literal ret
    // type needs no Var resolution.)
    final symbol = webDecodeText(query.replyBase64!);
    result = AgentProbeResult(
      loaded: true,
      version: readiness.version,
      proxyHost: _proxyHost,
      queryOk: true,
      symbol: symbol,
      replyBase64: query.replyBase64,
      candidFetched: true,
      candidParsed: candidParsed,
      symbolRetType: symbolRetType,
      error: null,
    );
  } catch (e) {
    result = AgentProbeResult(
      loaded: false,
      version: '',
      proxyHost: _proxyHost,
      queryOk: false,
      symbol: null,
      replyBase64: null,
      candidFetched: false,
      candidParsed: false,
      symbolRetType: null,
      error: e.toString(),
    );
  }

  _publishResult(jsonEncode(result.toJson()), result);
}

void _publishResult(String json, AgentProbeResult r) {
  // 1. document.title = JSON (the harness polls this).
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  doc.setProperty('title'.toJS, json.toJS);
  // 2. Append a <div id="agent-result"> with a human-readable summary.
  final div = doc.callMethod<JSObject>('createElement'.toJS, 'div'.toJS)
    ..setProperty('id'.toJS, 'agent-result'.toJS);
  final summary = StringBuffer()
    ..writeln('IC-agent-on-Web probe (R-3b WU-0 + WU-2)')
    ..writeln('loaded: ${r.loaded}  version: ${r.version}')
    ..writeln('proxy: ${r.proxyHost}/api/v1/ic')
    ..writeln('fetchCandid: ${r.candidFetched}  parseCandid: ${r.candidParsed}')
    ..writeln('symbol ret type (parsed): ${r.symbolRetType ?? "<not found>"}')
    ..writeln('query: $_ledgerCanister.$_ledgerMethod()')
    ..writeln('queryOk: ${r.queryOk}  symbol: ${r.symbol}');
  if (r.replyBase64 != null) summary.writeln('reply (base64): ${r.replyBase64}');
  if (r.error != null) summary.writeln('ERROR: ${r.error}');
  div.setProperty('innerText'.toJS, summary.toString().toJS);
  doc.getProperty<JSObject>('body'.toJS).callMethod('appendChild'.toJS, div);
}

/// Pure-Dart result type (asserted by the harness via document.title JSON).
class AgentProbeResult {
  AgentProbeResult({
    required this.loaded,
    required this.version,
    required this.proxyHost,
    required this.queryOk,
    required this.symbol,
    required this.replyBase64,
    required this.candidFetched,
    required this.candidParsed,
    required this.symbolRetType,
    required this.error,
  });

  final bool loaded;
  final String version;
  final String proxyHost;
  final bool queryOk;
  final String? symbol;
  final String? replyBase64;
  /// (WU-2) `fetchCandid` succeeded and returned non-empty `.did` text.
  final bool candidFetched;
  /// (WU-2) `parseCandid` succeeded and located the `symbol` method.
  final bool candidParsed;
  /// (WU-2) the `symbol` return type string `parseCandid` reported — asserted
  /// by the harness to equal `record { symbol : text }` (native parity on real
  /// metadata). Drives the typed decode of the reply.
  final String? symbolRetType;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'loaded': loaded,
        'version': version,
        'proxyHost': proxyHost,
        'queryOk': queryOk,
        'symbol': symbol,
        if (replyBase64 != null) 'replyBase64': replyBase64,
        'candidFetched': candidFetched,
        'candidParsed': candidParsed,
        'symbolRetType': symbolRetType,
        'error': error,
      };
}
