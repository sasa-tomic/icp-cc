// R-3 WU-1 — QuickJS-on-Web execution primitive (dart:js_interop facade).
//
// Drives the vendored `quickjs-emscripten` singlefile-browser WASM build
// (`web/vendor/quickjs/quickjs_emscripten.bundle.js`, loaded via a
// `<script type="module">` in `web/index.html`) from Dart. This is the
// Web-side mirror of `crates/icp_core/src/js_engine/runtime.rs` — the native
// rquickjs engine. The API surface here is deliberately the minimal set WU-1
// needs to PROVE the primitive (load + eval + memory/interrupt limits); WU-2
// and WU-3 will layer `executeJsJson` / `jsAppInit` / `jsAppView` /
// `jsAppUpdate` on top, porting `runtime.rs:122-432` method-for-method.
//
// ## Why this is web-only
// Uses `dart:js_interop` + `dart:js_interop_unsafe` (browser globals). This
// file is imported ONLY by `native_bridge_web.dart`, which the conditional
// export in `native_bridge.dart` selects on `dart.library.html`. It never
// compiles for the VM / native targets.
//
// ## The interop contract established here (reused by WU-2+)
// 1. The vendored bundle exposes `globalThis.__quickjsEmscripten`:
//      { modulePromise: Promise<QuickJSWASMModule>,
//        shouldInterruptAfterDeadline: (ms) => () => bool,
//        version: string }
//    The WASM instantiate is KICKED OFF by the bundle script (async), so by
//    the time Dart awaits `modulePromise`, loading is already in flight.
// 2. All cross-boundary payloads are STRINGS (script text, JSON args/results)
//    — no shared `JSValue` lifetime across calls, matching `runtime.rs`
//    (which creates a fresh `Runtime`/`Context` per call).
// 3. Every `evalCode` result handle MUST be `.dispose()`d before the context
//    is disposed, else QuickJS's `list_empty(&rt->gc_obj_list)` assertion
//    fires at runtime free-time (the JS API uses reference-counted `Lifetime`
//    handles, unlike rquickjs's RAII). `evalAndDump` encodes this discipline.
// 4. Interrupted execution surfaces as a JS `InternalError` with message
//    `interrupted`; OOM as `InternalError: out of memory` — mirroring the
//    native engine's timeout/OOM behaviour (`runtime.rs:25,306-311`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'quickjs_probe_result.dart';
import 'js_app_engine_interface.dart';

export 'quickjs_probe_result.dart' show QuickJsLoadException, QuickJsProbeResult;

// ─────────────────────────────────────────────────────────────────────────────
// JS facade — `@JS()` extension types over the quickjs-emscripten module.
// Names match the runtime API at
// https://github.com/justjake/quickjs-emscripten (v0.32.0).
// ─────────────────────────────────────────────────────────────────────────────

/// `globalThis.__quickjsEmscripten` — the bridge object the vendored bundle
/// installs. See `web/vendor/quickjs/quickjs_entry.mjs`.
@JS('__quickjsEmscripten')
extension type _QuickJSGlobal._(JSObject _) implements JSObject {
  external JSPromise<QuickJSWASMModule> get modulePromise;
  external JSFunction get shouldInterruptAfterDeadline;
  external JSString get version;
}

/// Top-level QuickJS module — owns the loaded WASM instance. Has NO `dispose`
/// (cleaned up on page unload); per-call isolation is via fresh contexts.
@JS()
extension type QuickJSWASMModule._(JSObject _) implements JSObject {
  /// Create a fresh runtime + context (the runtime is disposed when the
  /// context is). Mirrors `runtime.rs::create_sandboxed_js` (fresh per call).
  external QuickJSContext newContext();
}

/// A QuickJS runtime — memory / stack / interrupt limits live here.
@JS()
extension type QuickJSRuntime._(JSObject _) implements JSObject {
  /// Set the JS heap memory limit in bytes (`runtime.rs:23` → 64 MiB).
  external void setMemoryLimit(JSNumber limitBytes);
  /// Set the max stack size in bytes (`runtime.rs:24` → 512 KiB).
  external void setMaxStackSize(JSNumber stackSizeBytes);
  /// Register a callback polled between bytecode ops. Returning `true`
  /// interrupts execution with `InternalError: interrupted`
  /// (`runtime.rs:25` → `Instant::now() > deadline`).
  external void setInterruptHandler(JSFunction handler);
  external void dispose();
}

/// An owned QuickJS value handle. MUST be `dispose()`d — see file header.
@JS()
extension type QuickJSHandle._(JSObject _) implements JSObject {
  external void dispose();
  external bool get alive;
}

/// A QuickJS context — the `evalCode` / globals / value-conversion surface.
@JS()
extension type QuickJSContext._(JSObject _) implements JSObject {
  external QuickJSRuntime get runtime;
  external QuickJSHandle get global;

  /// Eval `code`; returns a result object `{value: handle}` (success) or
  /// `{error: handle}` (failure). Use [unwrapResult] to extract.
  external JSObject evalCode(JSString code, [JSString? filename, JSNumber? options]);

  /// On success: returns the value handle (owned — dispose it). On failure:
  /// converts the error to a native object and THROWS (a JS `InternalError`
  /// for interrupt / OOM). Disposes the result container either way.
  external QuickJSHandle unwrapResult(JSObject result);

  /// Best-effort convert a handle to a native JS value (JSON-serializable).
  /// This is the `getJson` analogue — `runtime.rs:104-115` does
  /// `JSON.stringify(__icp_res__)` in JS; here we let the host dump, then
  /// `JSON.stringify` from Dart when we need a string.
  external JSAny? dump(QuickJSHandle handle);

  // Primitive extractors / constructors (used by WU-2+ for arg injection).
  external double getNumber(QuickJSHandle handle);
  external JSString getString(QuickJSHandle handle);
  external QuickJSHandle newString(JSString value);
  external QuickJSHandle newNumber(JSNumber value);
  external QuickJSHandle newObject([QuickJSHandle? prototype]);
  external QuickJSHandle newArray();

  /// `context.getProp(handle, key)` — global access (`runtime.rs:182-185`).
  external QuickJSHandle getProp(QuickJSHandle handle, JSAny key);
  external void setProp(QuickJSHandle handle, JSAny key, QuickJSHandle value);

  external void dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// Native-parity constants + host globals — verbatim port of
// `crates/icp_core/src/js_engine/runtime.rs:7-9, 64-90`.
//
// These MUST stay byte-for-byte identical to the Rust reference so that a
// bundle produces the SAME `{state, effects}` / `{result, messages}` on Web as
// on native. The host helpers only BUILD descriptor objects (no JS→Dart
// callback channel — see plan §1.3); the Dart host resolves effects outside
// QuickJS (`script_runner.dart`).
// ─────────────────────────────────────────────────────────────────────────────

/// `runtime.rs:7` — JS heap memory limit (64 MiB).
const int _memLimit = 64 * 1024 * 1024;

/// `runtime.rs:8` — max stack size (512 KiB).
const int _stackLimit = 512 * 1024;

/// `runtime.rs:9` — default execution budget when the caller passes 0/omits.
const int _defaultBudgetMs = 100;

/// `runtime.rs:64-85` — host bootstrap globals injected before every bundle.
/// Defines `__icp_messages`, `icp_log`, `get_arg`, and the `icp_*` descriptor
/// builders / formatters. Identical JS to the Rust constant.
const String _hostBootstrapJs = r'''
var __icp_messages = [];
function icp_log(msg){ __icp_messages.push(String(msg)); }
function get_arg(){ return arg; }

function icp_call(spec){ spec = spec || {}; spec.action = "call"; return spec; }
function icp_batch(calls){ return { action: "batch", calls: calls || [] }; }
function icp_message(spec){ spec = spec || {}; return { action: "message", text: String((spec && spec.text != null) ? spec.text : ""), type: String((spec && spec.type != null) ? spec.type : "info") }; }
function icp_ui_list(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", items: (spec && spec.items) || [], buttons: (spec && spec.buttons) || [] } }; }
function icp_result_display(spec){ return { action: "ui", ui: { type: "result_display", props: spec } }; }
function icp_searchable_list(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", props: { searchable: !spec || spec.searchable !== false, items: (spec && spec.items) || [], title: (spec && spec.title) || "Results" } } }; }
function icp_section(spec){ spec = spec || {}; return { action: "ui", ui: { type: "section", props: { title: (spec && spec.title) || "", content: (spec && spec.content) || "" } } }; }
function icp_table(data){ return { action: "ui", ui: { type: "table", props: data } }; }
function icp_format_number(value, decimals){ return String(Number(value) || 0); }
function icp_format_icp(value, decimals){ var d = (decimals == null) ? 8 : decimals; return String((Number(value) || 0) / Math.pow(10, d)); }
function icp_format_timestamp(value){ return String(Number(value) || 0); }
function icp_format_bytes(value){ return String(Number(value) || 0); }
function icp_truncate(text, maxLen){ return String(text); }
function icp_filter_items(items, field, value){ return (items || []).filter(function(it){ return String((it && it[field] != null) ? it[field] : "").indexOf(String(value)) !== -1; }); }
function icp_sort_items(items, field, ascending){ return (items || []).slice().sort(function(a, b){ var av = String((a && a[field] != null) ? a[field] : ""); var bv = String((b && b[field] != null) ? b[field] : ""); if (ascending) { return av < bv ? -1 : (av > bv ? 1 : 0); } return av > bv ? -1 : (av < bv ? 1 : 0); }); }
function icp_group_by(items, field){ return (items || []).reduce(function(g, it){ var k = String((it && it[field] != null) ? it[field] : "unknown"); if (!g[k]) { g[k] = []; } g[k].push(it); return g; }, {}); }
''';

/// `runtime.rs:87-90` — defence-in-depth: neutralise `eval` + `Function`
/// constructor inside the sandbox.
const String _neutralizeEvalJs = r'''
globalThis.eval = function(){ throw new Error('eval is disabled in sandbox'); };
globalThis.Function = function(){ throw new Error('Function constructor is disabled in sandbox'); };
''';

/// The result of [WebQuickJsEngine.runProbe] — the WU-1 end-to-end proof.
/// (Type + `QuickJsLoadException` live in `quickjs_probe_result.dart` so the
/// contract is VM-testable without importing `dart:js_interop`.)

// ─────────────────────────────────────────────────────────────────────────────
// WebQuickJsEngine — loads the module once, then exposes the primitive.
// ─────────────────────────────────────────────────────────────────────────────

/// Drives the vendored `quickjs-emscripten` WASM from Dart. One instance owns
/// one loaded [QuickJSWASMModule]; per-call isolation is achieved by creating
/// a fresh context (matching `runtime.rs`'s fresh `Runtime`/`Context` per
/// call). WU-2+ extends this with `executeJsJson` / `jsApp*`.
class WebQuickJsEngine implements JsAppEngine {
  WebQuickJsEngine._(this._module, this.version);

  final QuickJSWASMModule _module;
  final String version;

  /// Load the QuickJS module. Polls for the vendored bundle's global (the
  /// `<script type="module">` is deferred and may execute after Dart `main`),
  /// then awaits the WASM-instantiate promise. Throws [QuickJsLoadException]
  /// loudly on any failure (never silently no-ops).
  static Future<WebQuickJsEngine> bootstrap({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final global = await _waitForGlobal(timeout);
    final version = global.version.toDart;
    final QuickJSWASMModule module;
    try {
      // modulePromise is already in flight (kicked off by the bundle script).
      module = await global.modulePromise.toDart;
    } catch (e) {
      throw QuickJsLoadException(
        'quickjs-emscripten WASM module failed to instantiate: ${_jsErrString(e)}',
      );
    }
    return WebQuickJsEngine._(module, version);
  }

  /// Poll `globalThis.__quickjsEmscripten` until the bundle installs it.
  static Future<_QuickJSGlobal> _waitForGlobal(Duration timeout) async {
    final key = '__quickjsEmscripten'.toJS;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (globalContext.hasProperty(key).toDart) {
        return globalContext.getProperty<_QuickJSGlobal>(key);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw QuickJsLoadException(
      'globalThis.__quickjsEmscripten not found within ${timeout.inSeconds}s — '
      'did the vendored bundle (web/vendor/quickjs/quickjs_emscripten.bundle.js) '
      'load? Check the <script type="module"> in web/index.html.',
    );
  }

  /// Create a fresh context with the sandbox limits from `runtime.rs:7-8`
  /// applied. Caller MUST [QuickJSContext.dispose] it (prefer
  /// [evalAndDump] / a `try/finally`).
  QuickJSContext newContext({
    int memoryLimitBytes = _memLimit,
    int stackLimitBytes = _stackLimit,
    JSFunction? interruptHandler,
  }) {
    final ctx = _module.newContext();
    ctx.runtime.setMemoryLimit(memoryLimitBytes.toJS);
    ctx.runtime.setMaxStackSize(stackLimitBytes.toJS);
    if (interruptHandler != null) {
      ctx.runtime.setInterruptHandler(interruptHandler);
    }
    return ctx;
  }

  /// Eval `code` and return the dumped native value, disposing all handles.
  /// Throws the JS error (e.g. `InternalError: interrupted`) on failure —
  /// callers catch and map to envelope error strings (WU-2/3).
  Object? evalAndDump(QuickJSContext ctx, String code) {
    final result = ctx.evalCode(code.toJS);
    final handle = ctx.unwrapResult(result); // throws on error; disposes result
    try {
      return _jsAnyToDart(ctx.dump(handle));
    } finally {
      handle.dispose();
    }
  }

  /// Build a deadline-based interrupt handler via the vendored
  /// `shouldInterruptAfterDeadline(deadline)` factory — the direct analogue of
  /// `runtime.rs:25,30-37` (`Instant::now() > deadline` where
  /// `deadline = now + budget`). NOTE: the factory takes a wall-clock
  /// TIMESTAMP (ms since epoch), NOT a duration — passing a bare duration
  /// would be read as a date near epoch (always past) and interrupt instantly.
  JSFunction deadlineInterrupt(Duration budget) {
    final deadlineMs =
        DateTime.now().millisecondsSinceEpoch + budget.inMilliseconds;
    return _interruptAt(deadlineMs);
  }

  /// Build an interrupt handler bound to an ABSOLUTE wall-clock deadline
  /// (ms since epoch). Used by the app-lifecycle methods so the SAME deadline
  /// drives both the interrupt (`runtime.rs:25`) and the post-error timeout
  /// classification (`runtime.rs:306-311,356-361,423-429`).
  JSFunction _interruptAt(int deadlineMs) {
    final global =
        globalContext.getProperty<_QuickJSGlobal>('__quickjsEmscripten'.toJS);
    final fn = global.shouldInterruptAfterDeadline
        .callAsFunction(null, deadlineMs.toJS);
    return fn as JSFunction;
  }

  /// `runtime.rs:30-37` (`deadline_from_budget`): 0 → DEFAULT_BUDGET_MS.
  int _effectiveBudget(int budgetMs) =>
      budgetMs == 0 ? _defaultBudgetMs : budgetMs;

  // ===========================================================================
  // WU-2 — `jsExec` parity (port of `runtime.rs::execute_js_json`, lines
  // 122-167, plus the helpers `set_arg_global`/`install_host_globals`/
  // `js_value_to_json_string`/`messages_to_json`).
  //
  // Returns the SAME JSON envelope the native FFI (`icp_js_exec`) emits:
  //   success: {"ok":true,"result":<value>,"messages":[...]}
  //   failure: {"ok":false,"error":"js error: <detail>"}
  //            {"ok":false,"error":"json error: <detail>"}  (bad jsonArg)
  // so [RustBridgeLoader.jsExec] on Web is a drop-in for the native path.
  //
  // Documented behavioural difference: the native engine reports a JS
  // exception as the generic "JavaScript exception" (rquickjs's
  // `Error::Exception` Display); quickjs-emscripten surfaces the actual
  // QuickJS message (e.g. "SyntaxError: ..."). The envelope SHAPE is identical
  // (`ok:false` + `error` string with the same `js error: `/`json error: `
  // prefix); the detail is strictly MORE informative on Web.
  // ===========================================================================

  /// Port of `runtime.rs:122-167` (`execute_js_json`).
  ///
  /// [script] is evaluated verbatim (no transpiler — see plan §1.1); the
  /// completion value is JSON-marshalled. [jsonArg], when provided, is parsed
  /// and exposed as `globalThis.arg` (the `get_arg()` host helper returns it).
  /// Returns the JSON envelope string (success or failure).
  String executeJsJson(String script, {String? jsonArg}) {
    // runtime.rs:126-132 — validate jsonArg up front (Json error variant).
    String? argStr;
    if (jsonArg != null) {
      try {
        jsonDecode(jsonArg);
      } on FormatException catch (e) {
        return _errEnvelope('json error: ${e.message}');
      }
      argStr = jsonArg;
    }

    // runtime.rs:134-137 — fresh sandboxed runtime, DEFAULT_BUDGET_MS deadline.
    final ctx = newContext(
      interruptHandler:
          deadlineInterrupt(const Duration(milliseconds: _defaultBudgetMs)),
    );
    var evalThrew = false;
    try {
      _installHostGlobals(ctx, argStr);
      // runtime.rs:142-144 — eval the user script; capture completion handle.
      final resultContainer = ctx.evalCode(script.toJS);
      final resultHandle = ctx.unwrapResult(resultContainer); // throws on error
      String resultJson;
      try {
        resultJson = _stringifyAsGlobal(ctx, resultHandle);
      } finally {
        resultHandle.dispose();
      }
      // runtime.rs:147-148 — collect icp_log messages.
      final messagesJson =
          evalAndDump(ctx, 'JSON.stringify(__icp_messages)') as String;
      // runtime.rs:157-166 — parse both, build the success envelope.
      final dynamic resultValue = jsonDecode(resultJson);
      final List<dynamic> messages =
          jsonDecode(messagesJson) as List<dynamic>;
      return jsonEncode(<String, dynamic>{
        'ok': true,
        'result': resultValue,
        'messages': messages,
      });
    } on Object catch (e) {
      // Map every JS/eval failure to the `Js` error envelope (matches FFI
      // `err_ptr(JsExecError::Js(...))` → "js error: ...").
      evalThrew = true;
      return _errEnvelope('js error: ${_jsErrString(e)}');
    } finally {
      _disposeContext(ctx, evalThrew: evalThrew);
    }
  }

  /// Port of `runtime.rs:39-62, 92-102` (`set_arg_global` +
  /// `install_host_globals`). Exposes `globalThis.arg`, then injects the host
  /// bootstrap + eval/Function neutralisation.
  void _installHostGlobals(QuickJSContext ctx, String? argStr) {
    if (argStr == null) {
      evalAndDump(ctx, 'globalThis.arg = null;');
    } else {
      // Embed the (already-validated) JSON as a JS string literal, then parse
      // it inside QuickJS — equivalent to the native raw-global two-step
      // (`__icp_arg_raw__` = s; JSON.parse(...)) but needs no handle juggling.
      evalAndDump(ctx, 'globalThis.arg = JSON.parse(${jsonEncode(argStr)});');
    }
    evalAndDump(ctx, _hostBootstrapJs);
    evalAndDump(ctx, _neutralizeEvalJs);
  }

  /// Port of `runtime.rs:104-115` (`js_value_to_json_string`). Assigns [handle]
  /// to `globalThis.__icp_res__`, stringifies it IN QuickJS (the canonical
  // serialiser — `JSON.stringify` matches native rquickjs byte-for-byte for
  // every value our bundles produce), with the `undefined`/`null` → `'null'`
  // guard. Returns the JSON string.
  String _stringifyAsGlobal(QuickJSContext ctx, QuickJSHandle handle) {
    // `ctx.global` is cached by the bundle (a long-lived handle freed with the
    // context) — safe to reuse without per-call disposal.
    ctx.setProp(ctx.global, '__icp_res__'.toJS, handle);
    final container = ctx.evalCode(
      "(typeof __icp_res__ === 'undefined' || __icp_res__ === null) ? 'null' : JSON.stringify(__icp_res__)"
          .toJS,
    );
    final strHandle = ctx.unwrapResult(container);
    try {
      return ctx.getString(strHandle).toDart;
    } finally {
      strHandle.dispose();
    }
  }

  /// Dispose a per-call context. After an OOM / interrupt abort the GC-list
  /// assertion in this assertions-enabled QuickJS build can fire on dispose —
  /// the eval itself already threw the correct error (`out of memory` /
  /// `interrupted`), which is the proof that holds. We LOUDLY log the
  /// secondary dispose failure (never silently swallow) and let the primary
  /// error — already returned to the caller — stand. This is the documented
  /// WU-1 decision formalised for the production paths.
  void _disposeContext(QuickJSContext ctx, {required bool evalThrew}) {
    if (!evalThrew) {
      ctx.dispose();
      return;
    }
    try {
      ctx.dispose();
    } catch (e) {
      // Not a silent swallow: the primary eval error was already surfaced to
      // the caller as the `{"ok":false,...}` envelope; this is a contained,
      // loudly-logged secondary effect on a context being discarded.
      // ignore: avoid_print
      print('[WebQuickJsEngine] secondary context-dispose failure after an '
          'eval abort (contained — primary error already returned): $e');
    }
  }

  /// Build a `{"ok":false,"error":...}` envelope string (matches FFI `err_ptr`).
  static String _errEnvelope(String error) =>
      jsonEncode(<String, dynamic>{'ok': false, 'error': error});

  /// serde-equivalent field access: like `JsonValue::get(key).cloned().
  /// unwrap_or(default)` — returns the value when [v] is a Map containing
  /// [key] (even if the value is null), else [dflt]. Mirrors
  /// `runtime.rs:291-295,410-414`.
  static Object? _fieldOr(dynamic v, String key, Object? dflt) =>
      v is Map && v.containsKey(key) ? v[key] : dflt;

  // ===========================================================================
  // WU-3 — init/view/update parity (port of `runtime.rs:269-432`).
  //
  // Each method creates a FRESH sandboxed context with a deadline interrupt,
  // installs the host globals, evals the bundle, calls the exported function
  // by name, and returns the SAME envelope the native FFI emits:
  //   init:   {"ok":true,"state":...,"effects":[...]} | {"ok":false,"error":...}
  //   view:   {"ok":true,"ui":...}                     | {"ok":false,"error":...}
  //   update: {"ok":true,"state":...,"effects":[...]} | {"ok":false,"error":...}
  // Effects are descriptors only — the Dart host resolves them OUTSIDE QuickJS
  // (plan §1.3). The `execution timeout` classification mirrors
  // `runtime.rs:306-311,356-361,423-429` exactly.
  // ===========================================================================

  /// Port of `runtime.rs:269-314` (`js_app_init`).
  @override
  String jsAppInit(String script, {String? jsonArg, int budgetMs = 50}) {
    final deadlineMs =
        DateTime.now().millisecondsSinceEpoch + _effectiveBudget(budgetMs);
    final ctx = newContext(interruptHandler: _interruptAt(deadlineMs));
    var evalThrew = false;
    try {
      _installHostGlobals(ctx, jsonArg);
      evalAndDump(ctx, script);
      if (_globalFnMissing(ctx, 'init')) {
        return _errEnvelope("Required function 'init' not found");
      }
      final rj = _callAndStringify(ctx, 'init(globalThis.arg)');
      final v = jsonDecode(rj);
      return jsonEncode(<String, dynamic>{
        'ok': true,
        'state': _fieldOr(v, 'state', null),
        'effects': _fieldOr(v, 'effects', <dynamic>[]),
      });
    } on Object catch (e) {
      evalThrew = true;
      return _errEnvelope(_timeoutOr(deadlineMs, e));
    } finally {
      _disposeContext(ctx, evalThrew: evalThrew);
    }
  }

  /// Port of `runtime.rs:316-364` (`js_app_view`).
  @override
  String jsAppView(String script,
      {required String stateJson, int budgetMs = 50}) {
    // runtime.rs:327-328 — validate state JSON BEFORE eval (the bundle never
    // runs if the state is malformed).
    if (!_isValidJson(stateJson)) {
      return _errEnvelope('invalid state JSON: ${_jsonErr(stateJson)}');
    }
    final deadlineMs =
        DateTime.now().millisecondsSinceEpoch + _effectiveBudget(budgetMs);
    final ctx = newContext(interruptHandler: _interruptAt(deadlineMs));
    var evalThrew = false;
    try {
      _installHostGlobals(ctx, null);
      // runtime.rs:329-336 — expose __icp_state__ (parsed inside QuickJS).
      evalAndDump(
          ctx, 'globalThis.__icp_state__ = JSON.parse(${jsonEncode(stateJson)});');
      evalAndDump(ctx, script);
      if (_globalFnMissing(ctx, 'view')) {
        return _errEnvelope("Required function 'view' not found");
      }
      final rj = _callAndStringify(ctx, 'view(globalThis.__icp_state__)');
      final v = jsonDecode(rj);
      return jsonEncode(<String, dynamic>{'ok': true, 'ui': v});
    } on Object catch (e) {
      evalThrew = true;
      return _errEnvelope(_timeoutOr(deadlineMs, e));
    } finally {
      _disposeContext(ctx, evalThrew: evalThrew);
    }
  }

  /// Port of `runtime.rs:366-432` (`js_app_update`).
  @override
  String jsAppUpdate(String script,
      {required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    // runtime.rs:377-380 — validate msg FIRST, then state.
    if (!_isValidJson(msgJson)) {
      return _errEnvelope('invalid msg JSON: ${_jsonErr(msgJson)}');
    }
    if (!_isValidJson(stateJson)) {
      return _errEnvelope('invalid state JSON: ${_jsonErr(stateJson)}');
    }
    final deadlineMs =
        DateTime.now().millisecondsSinceEpoch + _effectiveBudget(budgetMs);
    final ctx = newContext(interruptHandler: _interruptAt(deadlineMs));
    var evalThrew = false;
    try {
      _installHostGlobals(ctx, null);
      // runtime.rs:381-396 — expose __icp_msg__ + __icp_state__.
      evalAndDump(
        ctx,
        'globalThis.__icp_msg__ = JSON.parse(${jsonEncode(msgJson)}); '
        'globalThis.__icp_state__ = JSON.parse(${jsonEncode(stateJson)});',
      );
      evalAndDump(ctx, script);
      if (_globalFnMissing(ctx, 'update')) {
        return _errEnvelope("Required function 'update' not found");
      }
      final rj = _callAndStringify(
          ctx, 'update(globalThis.__icp_msg__, globalThis.__icp_state__)');
      final v = jsonDecode(rj);
      return jsonEncode(<String, dynamic>{
        'ok': true,
        'state': _fieldOr(v, 'state', null),
        'effects': _fieldOr(v, 'effects', <dynamic>[]),
      });
    } on Object catch (e) {
      evalThrew = true;
      return _errEnvelope(_timeoutOr(deadlineMs, e));
    } finally {
      _disposeContext(ctx, evalThrew: evalThrew);
    }
  }

  /// Returns true when global `name` is NOT a function — mirrors native's
  /// `globals.get(name)` Function-downcast failure (→ "Required function …").
  bool _globalFnMissing(QuickJSContext ctx, String name) =>
      evalAndDump(ctx, "typeof $name === 'function'") != true;

  /// Eval `call` (e.g. `init(globalThis.arg)`), stringify the return value IN
  /// QuickJS, and return the JSON string. Throws the JS error on failure
  /// (caller maps it via [_timeoutOr]).
  String _callAndStringify(QuickJSContext ctx, String call) {
    final callHandle = ctx.unwrapResult(ctx.evalCode(call.toJS));
    try {
      return _stringifyAsGlobal(ctx, callHandle);
    } finally {
      callHandle.dispose();
    }
  }

  /// `runtime.rs:306-311` — if the wall-clock deadline has elapsed by the time
  /// the error surfaced, classify it as `execution timeout` (the interrupt
  /// fired); otherwise surface the underlying error string.
  String _timeoutOr(int deadlineMs, Object e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > deadlineMs ? 'execution timeout' : _jsErrString(e);
  }

  /// Validate [s] parses as JSON (mirrors `serde_json::from_str::<JsonValue>`).
  bool _isValidJson(String s) {
    try {
      jsonDecode(s);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// The parse-error detail for a malformed JSON string (best-effort message;
  /// the host only substring-matches the `invalid … JSON:` prefix).
  String _jsonErr(String s) {
    try {
      jsonDecode(s);
    } on FormatException catch (e) {
      return e.message;
    }
    return '';
  }

  /// The WU-1 end-to-end probe: proves eval + memory-limit + interrupt-handler
  /// all work through the Dart interop layer. Returns a structured result.
  Future<QuickJsProbeResult> runProbe() async {
    String? error;
    Object? evalResult;
    Object? argRoundtrip;
    bool memHalted = false;
    String? memErr;
    bool intHalted = false;
    String? intErr;
    int intElapsed = -1;
    bool dartClosureFired = false;

    try {
      // 1. evalCode a constant.
      {
        final ctx = newContext();
        try {
          evalResult = evalAndDump(ctx, '1 + 2');
        } finally {
          ctx.dispose();
        }
      }

      // 2. arg roundtrip + JSON.stringify (runtime.rs:39-62,104-115 pattern).
      {
        final ctx = newContext();
        try {
          evalAndDump(ctx, 'globalThis.arg = JSON.parse(\'{"n":42}\')');
          argRoundtrip = evalAndDump(ctx, 'arg.n * 2');
        } finally {
          ctx.dispose();
        }
      }

      // 3. Memory limit: tight alloc must be aborted (InternalError: out of memory).
      {
        final ctx = newContext(
          memoryLimitBytes: 2 * 1024 * 1024,
          stackLimitBytes: 256 * 1024,
        );
        try {
          evalAndDump(
            ctx,
            'var a=[]; for(var i=0;i<1000000;i++){a.push(Array(1024).fill("x"))} 1',
          );
          memErr = 'no error thrown on OOM alloc';
        } catch (e) {
          memHalted = true;
          memErr = _jsErrString(e);
        } finally {
          // Dispose may itself throw after an OOM abort (non-empty GC list in
          // this assertions-enabled build); that is a known, contained
          // secondary effect — the proof is that eval threw.
          try {
            ctx.dispose();
          } catch (_) {
            // Not a silent swallow: the OOM was already captured in [memHalted].
            // The context is being discarded regardless.
          }
        }
      }

      // 4. Interrupt handler (deadline factory): while(true){} MUST halt.
      {
        final ctx = newContext(interruptHandler: deadlineInterrupt(
          const Duration(milliseconds: 100),
        ));
        final sw = Stopwatch()..start();
        try {
          evalAndDump(ctx, 'while(true){}');
          intErr = 'no error thrown on infinite loop';
        } catch (e) {
          intHalted = true;
          intErr = _jsErrString(e);
        } finally {
          intElapsed = sw.elapsedMilliseconds;
          ctx.dispose();
        }
      }

      // 5. Dart-closure interrupt handler: proves the general Dart→JS callback
      //    channel (a Dart function converted with `.toJS` returning true).
      {
        var count = 0;
        final JSFunction handler = (() {
          count++;
          return (count > 50).toJS;
        }).toJS;
        final ctx = newContext(interruptHandler: handler);
        try {
          evalAndDump(ctx, 'while(true){}');
        } catch (_) {
          // expected
        } finally {
          dartClosureFired = count > 50;
          ctx.dispose();
        }
      }
    } catch (e) {
      error = _jsErrString(e);
    }

    return QuickJsProbeResult(
      loaded: true,
      version: version,
      evalResult: evalResult,
      argRoundtrip: argRoundtrip,
      memoryLimitHalted: memHalted,
      memoryLimitError: memErr,
      interruptHalted: intHalted,
      interruptError: intErr,
      interruptElapsedMs: intElapsed,
      dartClosureInterruptFired: dartClosureFired,
      error: error,
    );
  }

  /// No-op. The loaded [QuickJSWASMModule] has no public `dispose` (it is a
  /// long-lived WASM instance, cleaned up on page unload — matching the native
  /// engine, where rquickjs is loaded once into the process). Per-call
  /// isolation is achieved by creating+disposing a fresh [QuickJSContext]
  /// (`runtime.rs` creates a fresh `Runtime`/`Context` per call).
  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Marshalling helpers.
// ─────────────────────────────────────────────────────────────────────────────

/// Convert a `JSAny?` (from `context.dump`) to a plain Dart value for the
/// probe. Numbers/strings/bools/null round-trip directly; objects/arrays are
/// JSON-stringified (WU-2 will marshal via `JSON.stringify` envelopes).
Object? _jsAnyToDart(JSAny? v) {
  if (v == null) return null;
  if (v.typeofEquals('number')) return (v as JSNumber).toDartDouble;
  if (v.typeofEquals('string')) return (v as JSString).toDart;
  if (v.typeofEquals('boolean')) return (v as JSBoolean).toDart;
  if (v.typeofEquals('undefined')) return null;
  if (v.typeofEquals('object')) {
    return _jsonStringify(v as JSObject) ?? '<js-object>';
  }
  return v.toString();
}

String? _jsonStringify(JSObject o) {
  try {
    final json = globalContext.getProperty<JSObject>('JSON'.toJS);
    final fn = json.getProperty<JSFunction>('stringify'.toJS);
    final s = fn.callAsFunction(null, o) as JSString;
    return s.toDart;
  } catch (_) {
    // Not a silent swallow: _jsonStringify is a best-effort renderer for the
    // diagnostic probe. The caller falls back to a placeholder.
    return null;
  }
}

/// Render a thrown JS error (from [QuickJSContext.unwrapResult]) to a string.
/// Interrupted eval throws a JS `InternalError` with `message: "interrupted"`;
/// OOM throws `InternalError: out of memory`.
String _jsErrString(Object e) {
  // `unwrapResult` throws a native JS Error; cast (not `is`-check) to read its
  // name/message, falling back to toString() for non-JS values.
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
