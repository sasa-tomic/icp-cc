// R-3 WU-4 — QuickJS-on-Web readiness CONTRACT test (VM).
//
// The engine load is browser-only, but the readiness API (QuickJsReadiness
// types + probeQuickJsReadiness) is pure-Dart and ships to every target. This
// test pins the contract the UI relies on:
//   - the sealed hierarchy + `isReady` accessors,
//   - on IO/native the probe is immediately [QuickJsReady] (no WASM to await).
//
// The Web load path is verified by:  just verify-quickjs-web-app

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

void main() {
  group('QuickJsReadiness contract (WU-4)', () {
    test('QuickJsReady.isReady is true', () {
      expect(const QuickJsReady().isReady, isTrue);
    });

    test('QuickJsUnavailable.isReady is false and carries reason/detail', () {
      const r = QuickJsUnavailable(
        reason: 'Script engine unavailable',
        detail: 'WASM failed to load',
      );
      expect(r.isReady, isFalse);
      expect(r.reason, 'Script engine unavailable');
      expect(r.detail, 'WASM failed to load');
    });

    test('probeQuickJsReadiness is immediately ready on the VM (no WASM load)',
        () async {
      // On IO/native there is no async WASM instantiate — the in-process FFI is
      // always available, so the probe resolves to QuickJsReady at once.
      final readiness = await probeQuickJsReadiness();
      expect(readiness, isA<QuickJsReady>());
      expect(readiness.isReady, isTrue);
    });

    test('a sealed switch over the result exhaustively covers both states', () {
      // Callers render the panel via a switch; assert the sealed hierarchy
      // forces handling of BOTH branches (no silent fall-through).
      String render(QuickJsReadiness r) => switch (r) {
            QuickJsReady() => 'ready',
            QuickJsUnavailable(:final reason) => 'unavailable: $reason',
          };
      expect(render(const QuickJsReady()), 'ready');
      expect(
        render(const QuickJsUnavailable(reason: 'down', detail: null)),
        'unavailable: down',
      );
    });
  });
}
