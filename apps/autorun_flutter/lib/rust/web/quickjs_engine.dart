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
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'quickjs_probe_result.dart';

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
// WebQuickJsEngine — loads the module once, then exposes the primitive.
// ─────────────────────────────────────────────────────────────────────────────

/// The result of [WebQuickJsEngine.runProbe] — the WU-1 end-to-end proof.
/// (Type + `QuickJsLoadException` live in `quickjs_probe_result.dart` so the
/// contract is VM-testable without importing `dart:js_interop`.)

/// Drives the vendored `quickjs-emscripten` WASM from Dart. One instance owns
/// one loaded [QuickJSWASMModule]; per-call isolation is achieved by creating
/// a fresh context (matching `runtime.rs`'s fresh `Runtime`/`Context` per
/// call). WU-2+ extends this with `executeJsJson` / `jsApp*`.
class WebQuickJsEngine {
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
    int memoryLimitBytes = 64 * 1024 * 1024, // MEM_LIMIT (runtime.rs:7)
    int stackLimitBytes = 512 * 1024, // STACK_LIMIT (runtime.rs:8)
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
    final global =
        globalContext.getProperty<_QuickJSGlobal>('__quickjsEmscripten'.toJS);
    final fn = global.shouldInterruptAfterDeadline
        .callAsFunction(null, deadlineMs.toJS);
    return fn as JSFunction;
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
