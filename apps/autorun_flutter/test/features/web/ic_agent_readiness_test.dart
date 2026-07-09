// R-3b WU-5 — IC-agent-on-Web readiness CONTRACT test (VM).
//
// The agent-js bundle load is browser-only, but the readiness API
// (IcAgentReadiness types + probeIcAgentReadiness) is pure-Dart and ships to
// every target. This test pins the contract the boot sites (ScriptAppHost._boot
// + ScriptRunner.run) rely on:
//   - the sealed hierarchy + reason/detail fields,
//   - on IO/native the probe is immediately [IcAgentReady] (no bundle to load),
//   - a sealed switch over the result exhaustively covers both states.
//
// It imports `native_bridge_web.dart` DIRECTLY (the R-2/R-4 web-crypto pattern)
// to PROVE that file stays VM-compilable: the conditional import must resolve
// to the VM stub (`ic_agent_engine_vm_stub.dart`) which returns IcAgentReady.
// A regression that pulls `dart:js_interop` into native_bridge_web.dart, or
// breaks the VM-stub / web-access signature parity, fails this test at compile
// time. The REAL browser load path is verified by:  just verify-ic-agent-web

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
// DIRECT import — proves native_bridge_web.dart (and its conditional import of
// the IC-agent access module) still compiles on the VM. The probe below is
// exercised through the facade's conditional export (→ native_bridge_io on the
// VM), and the web-stub path is covered by the smoke check at the bottom.
import 'package:icp_autorun/rust/native_bridge_web.dart' as web;

void main() {
  group('IcAgentReadiness contract (WU-5)', () {
    test('IcAgentReady carries the agent-js bundle version', () {
      const r = IcAgentReady(version: '3.4.3');
      expect(r.version, '3.4.3');
    });

    test('IcAgentUnavailable carries reason/detail', () {
      const r = IcAgentUnavailable(
        reason: 'IC agent unavailable',
        detail: 'bundle failed to load',
      );
      expect(r.reason, 'IC agent unavailable');
      expect(r.detail, 'bundle failed to load');
    });

    test('probeIcAgentReadiness is immediately ready on the VM (no bundle load)',
        () async {
      // On IO/native there is no agent-js bundle — the in-process Rust FFI is
      // the production path (agent-js is Web-only), so the probe resolves to
      // IcAgentReady at once.
      final readiness = await probeIcAgentReadiness();
      expect(readiness, isA<IcAgentReady>());
      expect((readiness as IcAgentReady).version, isNotEmpty);
    });

    test('a sealed switch over the result exhaustively covers both states', () {
      // Boot sites render / branch on the result; assert the sealed hierarchy
      // forces handling of BOTH branches (no silent fall-through).
      String render(IcAgentReadiness r) => switch (r) {
            IcAgentReady(:final version) => 'ready: $version',
            IcAgentUnavailable(:final reason) => 'unavailable: $reason',
          };
      expect(render(const IcAgentReady(version: 'native-ffi')),
          'ready: native-ffi');
      expect(
        render(const IcAgentUnavailable(reason: 'down', detail: null)),
        'unavailable: down',
      );
    });
  });

  // Smoke: native_bridge_web.dart imports the IC-agent access module via a
  // conditional import. Compiling this file on the VM proves the VM stub is
  // selected and its probe signature matches the Web access module's. Calling
  // the stub's probe here would re-enter the same conditional resolution; the
  // compile-time guarantee (no dart:js_interop leak into native_bridge_web.dart)
  // is the point of this group.
  group('native_bridge_web.dart VM-compilability (WU-5)', () {
    test('the web module is importable on the VM without dart:js_interop', () {
      // Reaching this assertion means `native_bridge_web.dart` (and its
      // conditional import of the IC-agent access module) compiled under the VM
      // target. The probe's public surface is delegated; we reference the
      // function symbol to keep it live (dead-code elimination would otherwise
      // hide a signature drift between the access module and the VM stub).
      expect(web.probeIcAgentReadiness, isA<Function>());
    });
  });
}
