// R-3 WU-4 — VM stub for the conditional import in `native_bridge_web.dart`.
//
// Selected when `dart.library.io` is available (i.e. compiling for the VM /
// native), where `quickjs_engine_web_access.dart` (browser-only,
// `dart:js_interop`) cannot be compiled. Mirrors the access module's function
// signatures so `native_bridge_web.dart` is VM-pure and the R-2/R-4 web-crypto
// tests (which import `native_bridge_web.dart` directly) keep working.
//
// The exec functions are never reached on the VM in practice: the production
// VM path uses `native_bridge_io.dart` (the real FFI), and the web-crypto tests
// only exercise the pure-Dart crypto helpers. They throw loudly (never silently
// no-op) if somehow invoked.
library;

import '../native_bridge.dart';

/// On the VM there is no WASM load — the native FFI (`native_bridge_io.dart`) is
/// the production path. Return [QuickJsReady] so any incidental probe resolves.
Future<QuickJsReadiness> probeWebQuickJsReadiness() async =>
    const QuickJsReady();

String execWebJs(String script, {String? jsonArg}) =>
    throw UnsupportedError(
        'QuickJS jsExec requires the Web runtime; the VM uses native_bridge_io');

String webJsAppInit(String script, {String? jsonArg, int budgetMs = 50}) =>
    throw UnsupportedError(
        'QuickJS jsAppInit requires the Web runtime; the VM uses native_bridge_io');

String webJsAppView(String script,
        {required String stateJson, int budgetMs = 50}) =>
    throw UnsupportedError(
        'QuickJS jsAppView requires the Web runtime; the VM uses native_bridge_io');

String webJsAppUpdate(String script,
        {required String msgJson,
        required String stateJson,
        int budgetMs = 50}) =>
    throw UnsupportedError(
        'QuickJS jsAppUpdate requires the Web runtime; the VM uses native_bridge_io');

/// WU-5 validate-runtime-stage — VM stub. The static (pure-Dart) stages run on
/// the VM, but the runtime syntax/exports check needs the browser engine.
List<String> webJsValidateRuntimeStage(String script) =>
    throw UnsupportedError(
        'QuickJS validateRuntimeStage requires the Web runtime; the VM uses '
        'native_bridge_io');
