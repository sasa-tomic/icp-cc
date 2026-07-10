// W6-1 Bug 2 — ScriptAppHost error rendering: raw IC exception stacks must
// NOT be dumped verbatim. When boot (or a dispatch) fails with a raw error
// carrying HTTP headers / HTML bodies (e.g. an IcAgentLoadException from a
// misconfigured proxy, or a 501 from the static file server), the host must
// show a short friendly message, keep the raw text in a collapsible "Details"
// section, and offer a Retry.
//
// These tests pump [ScriptAppHost] with a runtime whose `init` throws a raw
// exception (simulating the boot-failure path) and assert the friendly UX.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

/// A runtime whose `init` throws [error], so the host's boot catch sets `_error`
/// — exercising the error-rendering path without the network / FFI.
class _ThrowingRuntime implements IScriptAppRuntime {
  _ThrowingRuntime(this.error);
  final Object error;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    throw error;
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'ui': <String, dynamic>{}};
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

const String _rawIcHtmlError =
    'IcAgentLoadException: agent-js fetchCandid failed: '
    'Server: SimpleHTTP/0.6 Python/3.13.5\r\n'
    '<!DOCTYPE HTML><html><body>Error response</body></html>';

void main() {
  testWidgets(
      'boot failure with a raw IcAgentLoadException dump shows a friendly '
      'message, NOT the raw HTML / server banner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: _ThrowingRuntime(StateError(_rawIcHtmlError)),
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // The friendly message surfaces ...
    expect(find.textContaining('canister'), findsWidgets);
    // ... and the raw internals are NOT the primary text.
    expect(find.textContaining('IcAgentLoadException'), findsNothing);
    expect(find.textContaining('SimpleHTTP'), findsNothing);
    expect(find.textContaining('<!DOCTYPE'), findsNothing);
  });

  testWidgets('the raw error text is available in a collapsible Details section',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: _ThrowingRuntime(StateError(_rawIcHtmlError)),
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // Initially the raw internals are hidden behind a Details affordance.
    expect(find.textContaining('details'), findsOneWidget);
    expect(find.textContaining('SimpleHTTP'), findsNothing,
        reason: 'raw text must be hidden until Details is expanded');

    // Expand Details — the raw text becomes visible for advanced users.
    await tester.tap(find.textContaining('details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SimpleHTTP'), findsOneWidget);
  });

  testWidgets('a Retry affordance is present (re-attempts the failed boot)',
      (tester) async {
    var initCalls = 0;
    final runtime = _CountingRuntime(_rawIcHtmlError, () => initCalls++);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: runtime,
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(initCalls, 1, reason: 'initial boot runs init once');

    expect(find.textContaining('Retry'), findsOneWidget);
    await tester.tap(find.textContaining('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(initCalls, 2, reason: 'Retry must re-attempt the boot → init again');
  });
}

/// A runtime that throws on init but records how many times init was invoked,
/// so the Retry test can assert the boot actually re-ran (not just a no-op).
class _CountingRuntime implements IScriptAppRuntime {
  _CountingRuntime(this._error, this.onInit);
  final String _error;
  final void Function() onInit;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    onInit();
    throw StateError(_error);
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'ui': <String, dynamic>{}};
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
