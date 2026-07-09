// R-3 WU-4 — Web-only QuickJS engine access (the singleton + exec wrappers).
//
// This file is the WEB side of a conditional import used by
// `native_bridge_web.dart`. It imports the browser-only [WebQuickJsEngine]
// (`dart:js_interop`), so it MUST NOT be compiled on the VM — the matching
// `quickjs_engine_vm_stub.dart` is selected there (via `if (dart.library.io)`).
//
// Keeping this in a separate, conditionally-imported module lets
// `native_bridge_web.dart` stay pure-Dart and VM-compilable (the R-2/R-4 web
// crypto tests import it directly under `flutter test`).
library;

import '../native_bridge.dart';
import 'quickjs_engine.dart';

WebQuickJsEngine? _webQuickJsEngine;
Future<WebQuickJsEngine>? _webQuickJsEngineFuture;

/// Lazily create + cache the singleton engine. Concurrent callers share the
/// same load future (idempotent). A failed load stays failed (re-awaiting
/// rethrows) so the readiness gate reports it loudly rather than retrying under
/// every script screen.
Future<WebQuickJsEngine> _sharedWebEngine() {
  final cached = _webQuickJsEngine;
  if (cached != null) return Future.value(cached);
  return _webQuickJsEngineFuture ??= WebQuickJsEngine.bootstrap().then((e) {
    _webQuickJsEngine = e;
    return e;
  });
}

/// The loaded engine, or a loud [StateError] if the readiness gate has not been
/// awaited to completion first. The host (ScriptAppHost._boot / ScriptRunner.run)
/// guarantees the engine is loaded before any sync eval call; reaching this
/// throw is a programming error, not a recoverable runtime state.
WebQuickJsEngine _requireEngine() {
  final engine = _webQuickJsEngine;
  if (engine == null) {
    throw StateError(
        'QuickJS engine not loaded on Web — probeQuickJsReadiness() must be '
        'awaited (via the readiness gate) before invoking script execution. '
        'If the load failed, the host surfaces a QuickJsUnavailable panel.');
  }
  return engine;
}

/// Web readiness probe: loads (or returns the cached) singleton engine.
/// [QuickJsReady] once instantiated; [QuickJsUnavailable] (friendly reason) if
/// the WASM fails to load — the host renders the panel rather than throwing.
Future<QuickJsReadiness> probeWebQuickJsReadiness() async {
  try {
    await _sharedWebEngine();
    return const QuickJsReady();
  } catch (e) {
    return QuickJsUnavailable(
      reason: 'Script engine unavailable',
      detail: 'The in-browser QuickJS engine failed to load, so scripts cannot '
          'run in this tab. Reload the page to try again.\n$e',
    );
  }
}

/// jsExec parity — delegates to [WebQuickJsEngine.executeJsJson].
String execWebJs(String script, {String? jsonArg}) =>
    _requireEngine().executeJsJson(script, jsonArg: jsonArg);

/// jsAppInit parity — delegates to [WebQuickJsEngine.jsAppInit].
String webJsAppInit(String script, {String? jsonArg, int budgetMs = 50}) =>
    _requireEngine().jsAppInit(script, jsonArg: jsonArg, budgetMs: budgetMs);

/// jsAppView parity — delegates to [WebQuickJsEngine.jsAppView].
String webJsAppView(String script,
        {required String stateJson, int budgetMs = 50}) =>
    _requireEngine()
        .jsAppView(script, stateJson: stateJson, budgetMs: budgetMs);

/// jsAppUpdate parity — delegates to [WebQuickJsEngine.jsAppUpdate].
String webJsAppUpdate(String script,
        {required String msgJson,
        required String stateJson,
        int budgetMs = 50}) =>
    _requireEngine().jsAppUpdate(script,
        msgJson: msgJson, stateJson: stateJson, budgetMs: budgetMs);

/// validate-runtime-stage parity (WU-5) — delegates to
/// [WebQuickJsEngine.validateRuntimeStage]. Returns the list of syntax_errors
/// the native runtime stage would push (empty = valid). Only invoked when the
/// pure-Dart static stages (in `js_static_analysis.dart`) already passed.
List<String> webJsValidateRuntimeStage(String script) =>
    _requireEngine().validateRuntimeStage(script);
