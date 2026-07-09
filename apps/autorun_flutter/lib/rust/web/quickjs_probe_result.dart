// R-3 WU-1 — Pure-Dart value types for the QuickJS-on-Web probe.
//
// Split out of `quickjs_engine.dart` (which uses `dart:js_interop` and is thus
// browser-only / un-importable in `flutter test` VM — see plan §2.3) so the
// probe-result contract can be unit-tested in the VM and asserted by the
// browser harness. This file has NO web-only imports.
library;

/// Thrown when the vendored QuickJS bundle fails to load or the WASM module
/// fails to instantiate. Loud by design (AGENTS.md: no silent failures on Web).
class QuickJsLoadException implements Exception {
  QuickJsLoadException(this.message);
  final String message;
  @override
  String toString() => 'QuickJsLoadException: $message';
}

/// The result of `WebQuickJsEngine.runProbe` — the WU-1 end-to-end proof.
///
/// Serialised to JSON by the probe entrypoint (`lib/web_probe_main.dart`) and
/// asserted by the Playwright harness (`scripts/quickjs_web_probe/verify.js`).
/// The passing vector is codified in
/// `test/features/web/quickjs_smoke_test.dart`.
class QuickJsProbeResult {
  QuickJsProbeResult({
    required this.loaded,
    required this.version,
    required this.evalResult,
    required this.argRoundtrip,
    required this.memoryLimitHalted,
    required this.memoryLimitError,
    required this.interruptHalted,
    required this.interruptError,
    required this.interruptElapsedMs,
    required this.dartClosureInterruptFired,
    required this.error,
  });

  /// `true` once the vendored WASM module instantiated.
  final bool loaded;

  /// Vendored quickjs-emscripten build version (diagnostics).
  final String version;

  /// `evalCode("1 + 2")` → `3` (proves Dart→JS eval + value round-trip).
  final Object? evalResult;

  /// `arg.n * 2` → `84` after `JSON.parse('{"n":42}')` (runtime.rs:39-62,104-115).
  final Object? argRoundtrip;

  /// `setMemoryLimit` aborted an unbounded alloc.
  final bool memoryLimitHalted;
  final String? memoryLimitError;

  /// `setInterruptHandler` halted `while(true){}` at the wall-clock deadline.
  final bool interruptHalted;
  final String? interruptError;

  /// Wall-clock ms until the interrupt fired (≈ the budget — proves the
  /// deadline model mirrors `runtime.rs:25,30-37`).
  final int interruptElapsedMs;

  /// A Dart closure converted with `.toJS` returning `true` interrupted —
  /// proves the general Dart→JS callback channel.
  final bool dartClosureInterruptFired;

  /// Top-level error if the probe itself crashed (load/eval failure). Must be
  /// `null` on the passing path; populated loudly on failure.
  final String? error;

  Map<String, Object?> toJson() => {
        'loaded': loaded,
        'version': version,
        'evalResult': evalResult,
        'argRoundtrip': argRoundtrip,
        'memoryLimitHalted': memoryLimitHalted,
        'memoryLimitError': memoryLimitError,
        'interruptHalted': interruptHalted,
        'interruptError': interruptError,
        'interruptElapsedMs': interruptElapsedMs,
        'dartClosureInterruptFired': dartClosureInterruptFired,
        if (error != null) 'error': error,
      };
}
