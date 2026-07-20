// E2E-D-RESUME-1 — ScriptAppHost must NOT call setState after the host is
// disposed. The boot/effect chain (`_boot` → `_executeEffects` → `_runEffect`
// → `_enqueueMsg` → `_dispatch`) keeps running async work after the parent
// remounts the host (DappRunnerScreen._applyConfig / _refreshDapp reassign the
// `GlobalKey`). When `_dispatch` enters via an unawaited `unawaited(...)` it
// can land on a defunct State; its first `setState` (currently unguarded)
// fires on the disposed State → production memory leak + e2e test red.
//
// The fix is the canonical `if (!mounted) return;` guard before setState
// (https://api.flutter.dev/flutter/widgets/State/mounted.html).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

/// Runtime whose `init` is gated by a [Completer] so the test can dispose the
/// host mid-boot, then release `init` to drive the rest of the boot chain
/// (`_executeEffects` → `_runEffect` → `_enqueueMsg` → `_dispatch`) against a
/// defunct State.
class _GatedInitRuntime implements IScriptAppRuntime {
  _GatedInitRuntime(this.initGate);

  final Completer<Map<String, dynamic>> initGate;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) {
    return initGate.future;
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'ui': <String, dynamic>{'type': 'column', 'children': <dynamic>[]},
    };
  }

  @override
  Future<Map<String, dynamic>> update({
    required String script,
    required Map<String, dynamic> msg,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'state': state};
  }
}

void main() {
  testWidgets(
      'E2E-D-RESUME-1: host disposed during boot does NOT call setState '
      'after dispose from the unawaited _dispatch chain', (tester) async {
    // Gate init so the host stays in `_busy` (boot pending) while we replace
    // the widget tree below it.
    final initGate = Completer<Map<String, dynamic>>();
    final runtime = _GatedInitRuntime(initGate);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundle */',
        ),
      ),
    ));
    // Run initState + the first post-frame callback so `_boot` reaches
    // `await widget.runtime.init(...)`.
    await tester.pump();

    // Remount path: replace the tree. The host State is disposed mid-boot
    // (init is still pending). This mirrors DappRunnerScreen._applyConfig /
    // _refreshDapp reassigning the GlobalKey in production.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump();

    // Release init with an unsupported effect — boot's `_executeEffects`
    // iterates this single effect, `_runEffect` falls through to the
    // catch-all branch that calls `_enqueueMsg`, which schedules an
    // unawaited `_dispatch`. `_dispatch`'s FIRST action is a `setState`
    // (currently unguarded) that fires on the disposed State.
    initGate.complete(<String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': <dynamic>[
        <String, dynamic>{'kind': 'unknown_effect', 'id': 'bogus'},
      ],
    });
    // Pump enough microtasks for the unawaited _dispatch to land.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    // Without the fix: a FlutterError("setState() called after dispose()")
    // is captured by the test binding. With the mounted guard: clean.
    expect(tester.takeException(), isNull);
  });
}
