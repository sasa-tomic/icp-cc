// R-3 WU-1 — QuickJS-on-Web execution primitive: smoke contract.
//
// The QuickJS engine (`lib/rust/web/quickjs_engine.dart`) is BROWSER-ONLY — it
// drives a WASM artifact via `dart:js_interop`, so it cannot run in the Dart VM
// (mirrors the passkey testing posture in `docs/BROWSER_SUPPORT.md`). This VM
// test therefore codifies the *contract* that the browser harness verifies:
// the [QuickJsProbeResult] JSON shape + the expected passing values. It also
// pins the pure-Dart `QuickJsProbeResult.toJson` mapping.
//
// The REAL end-to-end proof (load vendored WASM → eval → memory/interrupt
// limits) is run by the Playwright harness:
//
//   just verify-quickjs-web
//
// which builds `flutter build web --target=lib/web_probe_main.dart`, serves it,
// loads it in headless Chromium, and asserts on `document.title` (the probe's
// JSON output). The vector below is the exact JSON that harness asserts.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/quickjs_probe_result.dart';

void main() {
  group('QuickJsProbeResult contract (WU-1 browser-harness vector)', () {
    test('toJson() produces the exact shape the browser harness asserts', () {
      // The passing vector captured from the Playwright run
      // (apps/autorun_flutter built with --target=lib/web_probe_main.dart).
      final result = QuickJsProbeResult(
        loaded: true,
        version: '0.32.0',
        evalResult: 3, // evalCode("1 + 2")
        argRoundtrip: 84, // arg.n * 2 after JSON.parse('{"n":42}')
        memoryLimitHalted: true,
        memoryLimitError: 'InternalError: out of memory',
        interruptHalted: true,
        interruptError: 'InternalError: interrupted',
        interruptElapsedMs: 100, // == the 100ms budget (deadline model)
        dartClosureInterruptFired: true,
        error: null,
      );

      final json = jsonDecode(jsonEncode(result.toJson()));

      // The vendored build version (pinned for diagnostics).
      expect(json['version'], '0.32.0');
      // The three primitive proofs.
      expect(json['loaded'], isTrue);
      expect(json['evalResult'], 3);
      expect(json['argRoundtrip'], 84);
      // Memory-limit proof: setMemoryLimit aborts an unbounded alloc.
      expect(json['memoryLimitHalted'], isTrue);
      expect(json['memoryLimitError'], contains('out of memory'));
      // Interrupt proof: setInterruptHandler halts while(true){} at the
      // wall-clock deadline (mirrors runtime.rs:25,30-37).
      expect(json['interruptHalted'], isTrue);
      expect(json['interruptError'], contains('interrupted'));
      expect(json['interruptElapsedMs'], lessThan(5000));
      // Dart-closure interrupt: a Dart fn converted with `.toJS` returning
      // true interrupts — proves the general Dart→JS callback channel.
      expect(json['dartClosureInterruptFired'], isTrue);
      // No top-level error on the passing path.
      expect(json.containsKey('error'), isFalse);
    });

    test('failure vector: a load/eval crash is surfaced loudly, not silent', () {
      // AGENTS.md: no silent failures on Web. A crash must populate `error`
      // (and leave the proof booleans false) so the readiness/UI path can
      // render a clear message rather than degrading to a no-op.
      final result = QuickJsProbeResult(
        loaded: false,
        version: '',
        evalResult: null,
        argRoundtrip: null,
        memoryLimitHalted: false,
        memoryLimitError: null,
        interruptHalted: false,
        interruptError: null,
        interruptElapsedMs: -1,
        dartClosureInterruptFired: false,
        error: 'QuickJsLoadException: WASM module failed to instantiate',
      );

      final json = jsonDecode(jsonEncode(result.toJson()));

      expect(json['loaded'], isFalse);
      expect(json['error'], contains('QuickJsLoadException'));
      expect(json['evalResult'], isNull);
    });

    test('QuickJsLoadException message is rendered (not swallowed)', () {
      final exc = QuickJsLoadException(
        'globalThis.__quickjsEmscripten not found within 15s — '
        'did web/vendor/quickjs/quickjs_emscripten.bundle.js load?',
      );
      expect(exc.toString(), contains('QuickJsLoadException'));
      expect(exc.toString(), contains('__quickjsEmscripten'));
      expect(exc.message, contains('bundle.js'));
    });
  });
}
