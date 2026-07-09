// R-3b WU-0 — Browser probe entrypoint for the agent-js IC-agent primitive.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the WU-0 verification step:
//   flutter build web --target=lib/web_probe_agent_main.dart \
//       --dart-define=IC_AGENT_PROXY_HOST=http://127.0.0.1:<api-port>
//
// It is intentionally FLUTTER-FREE (no `WidgetsFlutterBinding` / `runApp`):
// the point of WU-0 is to prove the browser→proxy→IC-boundary-node path with
// ONE real anonymous canister query, not to render UI. Avoiding the binding
// also avoids auto-registering the app's web plugins (e.g. the `passkeys`
// Corbado SDK, which would throw without its bundle.js — unrelated to R-3b).
//
// The probe:
//   1. Loads the vendored agent-js bundle + creates an anonymous HttpAgent
//      routed through the backend CORS proxy (`IC_AGENT_PROXY_HOST/api/v1/ic`).
//   2. Performs ONE real anonymous query against the ICP ledger canister
//      (`ryjl3-tyaaa-aaaaa-aaaba-cai`) `symbol` method.
//   3. Decodes the candid `text` reply ("ICP") via the bundled IDL runtime.
//   4. Publishes the result as JSON to `document.title` (polled by the
//      headless-Chromium harness) + a `<div id="agent-result">` summary.
//
// On any failure it sets `document.title` to `{"loaded":false,"error":...}` so
// the harness reports the failure loudly rather than hanging.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'rust/web/ic_agent_engine_web_access.dart';

/// The proxy origin (backend), e.g. `http://127.0.0.1:58000`. Supplied via
/// `--dart-define=IC_AGENT_PROXY_HOST=...` by the `just verify-ic-agent-web`
/// recipe (which starts `just api-dev-up` first and reads the port).
const String _proxyHost = String.fromEnvironment(
  'IC_AGENT_PROXY_HOST',
  defaultValue: 'http://127.0.0.1:58000',
);

/// The well-known canister + method the PoC queries. The ICP ledger `symbol`
/// query returns `text` ("ICP") — a stable, read-only, anonymous mainnet call.
const String _ledgerCanister = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _ledgerMethod = 'symbol';

Future<void> main() async {
  AgentProbeResult result;
  try {
    // 1. Load the bundle + create the anonymous agent (routed via the proxy).
    final readiness = await probeIcAgentReadiness(proxyOrigin: _proxyHost);
    if (readiness is IcAgentReady) {
      // 2. ONE real anonymous query against the ICP ledger `symbol` method.
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
          error: 'query failed (${query.kind}): ${query.error}',
        );
      } else {
        // 3. Decode the candid `text` reply via the bundled IDL runtime.
        final symbol = webDecodeText(query.replyBase64!);
        result = AgentProbeResult(
          loaded: true,
          version: readiness.version,
          proxyHost: _proxyHost,
          queryOk: true,
          symbol: symbol,
          replyBase64: query.replyBase64,
          error: null,
        );
      }
    } else {
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
        error: '${unavail.reason}: ${unavail.detail ?? ''}',
      );
    }
  } catch (e) {
    result = AgentProbeResult(
      loaded: false,
      version: '',
      proxyHost: _proxyHost,
      queryOk: false,
      symbol: null,
      replyBase64: null,
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
    ..writeln('IC-agent-on-Web probe (R-3b WU-0)')
    ..writeln('loaded: ${r.loaded}  version: ${r.version}')
    ..writeln('proxy: ${r.proxyHost}/api/v1/ic')
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
    required this.error,
  });

  final bool loaded;
  final String version;
  final String proxyHost;
  final bool queryOk;
  final String? symbol;
  final String? replyBase64;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'loaded': loaded,
        'version': version,
        'proxyHost': proxyHost,
        'queryOk': queryOk,
        'symbol': symbol,
        if (replyBase64 != null) 'replyBase64': replyBase64,
        'error': error,
      };
}
