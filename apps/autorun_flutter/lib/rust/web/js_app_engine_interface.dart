// R-3 WU-3 — pure-Dart interface for the jsApp lifecycle engine methods.
//
// Exists ONLY to break the `dart:js_interop` dependency chain: the golden-vector
// catalogue (`js_app_golden_vectors.dart`) needs to CALL these methods but must
// stay importable in the Dart VM (where the contract test runs). [WebQuickJsEngine]
// (browser-only) implements this interface; the catalogue's `run` closures type
// the engine as [JsAppEngine], so the catalogue compiles on both VM and Web.
//
// The method contracts mirror `crates/icp_core/src/js_engine/runtime.rs:269-432`
// (return the native FFI envelope strings). See `quickjs_engine.dart` for the
// real implementation.
library;

/// The three exported-app lifecycle entry points, returning the JSON envelope
/// string the native FFI (`icp_js_app_init/view/update`) emits.
abstract interface class JsAppEngine {
  String jsAppInit(String script, {String? jsonArg, int budgetMs});

  String jsAppView(String script,
      {required String stateJson, int budgetMs});

  String jsAppUpdate(String script,
      {required String msgJson, required String stateJson, int budgetMs});
}
