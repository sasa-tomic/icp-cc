// R-3b WU-0 — VM stub for the conditional import (WU-2+ will wire it into
// `native_bridge_web.dart`).
//
// Selected when `dart.library.io` is available (i.e. compiling for the VM /
// native), where `ic_agent_engine_web_access.dart` (browser-only,
// `dart:js_interop`) cannot be compiled. Mirrors the access module's function
// signatures so the importing file is VM-pure and the R-2/R-4 web-crypto tests
// (which import `native_bridge_web.dart` directly) keep working.
//
// The functions are never reached on the VM in practice: the production VM
// path uses `native_bridge_io.dart` (the real FFI). They throw loudly (never
// silently no-op) if somehow invoked.
library;

// Pure-Dart types ONLY — this stub must NOT pull in `dart:js_interop`, so it
// imports `ic_agent_types.dart` (the shared pure-Dart contract), NOT
// `ic_agent_engine.dart` (browser-only).
import 'ic_agent_types.dart';

export 'ic_agent_types.dart';

Future<IcAgentReadiness> probeIcAgentReadiness({
  required String proxyOrigin,
}) async =>
    throw UnsupportedError(
        'IC agent probe requires the Web runtime; the VM uses native_bridge_io');

Future<IcAgentQueryResult> webQueryAnonymous({
  required String canisterId,
  required String method,
  String argBase64 = '',
}) =>
    throw UnsupportedError(
        'IC agent query requires the Web runtime; the VM uses native_bridge_io');

/// `fetchCandid` — Web-only (agent-js network I/O via the CORS proxy). The VM
/// production path uses `native_bridge_io.dart`'s FFI; this stub is never
/// reached in practice. Mirrors [webQueryAnonymous]'s contract.
Future<String?> webFetchCandid({required String canisterId}) =>
    throw UnsupportedError(
        'IC agent fetchCandid requires the Web runtime; the VM uses '
        'native_bridge_io');

String webDecodeText(String replyBase64) => throw UnsupportedError(
    'IC agent decode requires the Web runtime; the VM uses native_bridge_io');
