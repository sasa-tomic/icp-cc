// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Method channel url_launcher talks to. Mocked per-test to force the
/// "platform could not open the URL" branch (`launchUrl` returns false).
const MethodChannel _kUrlLauncherChannel =
    MethodChannel('plugins.flutter.io/url_launcher');

/// Widget coverage for the dapp runner (Path B: backend direct).
///
/// NO crypto is mocked here — the runner only plumbs the descriptor's
/// connection values into [ScriptAppHost]'s `initialArg`. A recording fake
/// runtime captures that `initialArg` so the test asserts the plumbing
/// directly, without executing the bundle or touching the network.
void main() {
  final DappDescriptor descriptor = exampleDapps.first;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('with no active profile, shows the view-only status', (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No active profile'),
      findsOneWidget,
      reason: 'Without a profile the runner must clearly state view-only mode',
    );
    // And never expose any principal string as if signed in.
    expect(find.textContaining('Signed as:'), findsNothing);
  });

  testWidgets('mounts ScriptAppHost with the descriptor initialArg', (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // The host re-booted with the effective (default) connection values.
    expect(runtime.lastInitialArg, isNotNull);
    expect(runtime.lastInitialArg!['backend_id'], descriptor.backendCanisterId);
    expect(runtime.lastInitialArg!['host'], descriptor.host);
    // The bundled source is the one wired in by the runner.
    expect(runtime.lastScript, '/* test bundle */');
  });

  testWidgets('Apply persists the edited connection and remounts the host',
      (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // Defaults are live.
    expect(runtime.lastInitialArg!['backend_id'], descriptor.backendCanisterId);

    // Open the Connection panel (ExpansionTile is collapsed by default).
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    // Edit both fields to point at a different replica/canister.
    await tester.enterText(
        find.byKey(const Key('dappBackendIdField')), 'my-custom-canister-id');
    await tester.enterText(
        find.byKey(const Key('dappHostField')), 'http://10.0.0.9:8000');
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Persisted: a fresh load now returns the overridden values.
    final persisted = await DappRuntimeConfig.load(descriptor);
    expect(persisted.backendCanisterId, 'my-custom-canister-id');
    expect(persisted.host, 'http://10.0.0.9:8000');

    // Remounted: the host re-booted with the NEW initialArg.
    expect(runtime.lastInitialArg!['backend_id'], 'my-custom-canister-id');
    expect(runtime.lastInitialArg!['host'], 'http://10.0.0.9:8000');
  });

  testWidgets('Apply with an empty canister id is rejected (no persistence)',
      (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    // Blank the canister id — validation must block Apply.
    await tester.enterText(
        find.byKey(const Key('dappBackendIdField')), '');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Canister id is required'), findsOneWidget);
    // Nothing persisted: still the default.
    final persisted = await DappRuntimeConfig.load(descriptor);
    expect(persisted.backendCanisterId, descriptor.backendCanisterId);
  });

  testWidgets(
      'Connection panel is collapsed by default and surfaces a recovery hint '
      'when expanded', (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // Goal 1: collapsed by default — the editable fields are NOT visible until
    // the user expands. (Common case = a working connection = no attention
    // demanded.)
    expect(find.byKey(const Key('dappBackendIdField')), findsNothing,
        reason: 'Connection panel must be collapsed by default');

    // Goal 2: the configured (default) connection shows in the subtitle so the
    // user can see the effective id at a glance without expanding.
    expect(find.textContaining(descriptor.backendCanisterId), findsOneWidget);

    // Goal 3: expanding reveals the OBVIOUS recovery path — the hint names the
    // exact command (`dfx start --clean`) that regenerates ids and the action
    // (`dfx deploy`) that yields the new id. No silent "edit somewhere" copy.
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('dfx start --clean'), findsOneWidget,
        reason: 'The recovery hint must name the command that invalidates ids');
    expect(find.textContaining('dfx deploy'), findsOneWidget,
        reason: 'The recovery hint must name where the new id comes from');
  });

  testWidgets(
      'Open-frontend-in-browser shows a LOUD error when the platform can\'t launch',
      (tester) async {
    // Force url_launcher's launchUrl to report failure (returns false) so the
    // runner exercises its loud-failure branch — it must surface a visible error
    // naming the URL it could not open, never silently no-op.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _kUrlLauncherChannel, (MethodCall call) async => false);

    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open frontend in browser'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the browser'), findsOneWidget,
        reason: 'A failed launch must be surfaced loudly, not swallowed');
    // The error must name the URL it tried so the user can recover manually.
    expect(find.textContaining(descriptor.frontendUrl), findsOneWidget);

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_kUrlLauncherChannel, null);
  });

  // ───────────────────────── UX-9 keyboard shortcuts ─────────────────────────
  // `defaultTargetPlatform` is android in `flutter_test`, which would leave
  // ScreenShortcuts as a no-op pass-through. Force a desktop platform for
  // these tests and restore it before the binding's invariant assertions run.
  testWidgets('R remounts the host and shows a Refresh tooltip (UX-9)',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final runtime = _RecordingRuntime();
      await _pumpRunner(tester, descriptor, runtime: runtime);
      await tester.pumpAndSettle();
      expect(runtime.initCount, 1, reason: 'initial mount runs init once');

      // The Refresh button's tooltip surfaces the binding so it's discoverable.
      expect(find.byTooltip('Refresh dapp (R)'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();

      expect(runtime.initCount, 2,
          reason: 'R must remount the host → init fires again');
      expect(find.textContaining('Dapp refreshed'), findsOneWidget,
          reason: 'A visible confirmation closes the loop for the user');
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('R does NOT fire while editing the canister-id field (UX-9)',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final runtime = _RecordingRuntime();
      await _pumpRunner(tester, descriptor, runtime: runtime);
      await tester.pumpAndSettle();
      expect(runtime.initCount, 1);

      // Open the Connection panel and focus the canister-id field.
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('dappBackendIdField')), 'r');
      await tester.pump();

      // Typing more 'r' characters into the field must NOT trigger a refresh.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();

      expect(runtime.initCount, 1,
          reason: 'Plain R must stay inert while the user is editing text.');
      expect(find.widgetWithText(TextField, 'r'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('Esc pops the dapp runner back to the catalog (UX-9)',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final runtime = _RecordingRuntime();
      // Pump a ROOT route that pushes the runner on tap, so Navigator.pop has
      // somewhere to pop back to (the runner can't be the home route).
      await tester.pumpWidget(
        ProfileScope(
          controller: ProfileController(
            marketplaceService: MarketplaceOpenApiService(),
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DappRunnerScreen(
                          descriptor: descriptor,
                          testRuntime: runtime,
                          testBundle: '/* test bundle */',
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(DappRunnerScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(DappRunnerScreen), findsNothing,
          reason: 'Esc must pop the runner back to the catalog');
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

Future<void> _pumpRunner(
  WidgetTester tester,
  DappDescriptor descriptor, {
  required _RecordingRuntime runtime,
}) async {
  // Real ProfileController, no profiles → activeKeypair is null (view-only).
  final profileController = ProfileController(
    marketplaceService: MarketplaceOpenApiService(),
  );
  await tester.pumpWidget(
    ProfileScope(
      controller: profileController,
      child: MaterialApp(
        home: DappRunnerScreen(
          descriptor: descriptor,
          // Inject so the test never executes the bundle or hits the network.
          testRuntime: runtime,
          testBundle: '/* test bundle */',
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Records the `script` + `initialArg` passed to init and returns a trivial
/// empty-column UI with no effects, so [ScriptAppHost] renders without making
/// any canister calls. Mirrors the fake-runtime pattern in
/// script_app_host_auth_test.dart (no crypto is mocked — none is needed here).
class _RecordingRuntime implements IScriptAppRuntime {
  Map<String, dynamic>? lastInitialArg;
  String? lastScript;
  /// Count of `init` invocations — each remount of [ScriptAppHost] (driven by
  /// `_hostGeneration` in the runner) calls `init` once. UX-9 refresh tests
  /// assert against this to detect a remount.
  int initCount = 0;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    lastScript = script;
    lastInitialArg = initialArg;
    initCount++;
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'ui': _emptyColumn(),
    };
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'ui': _emptyColumn()};
  }

  @override
  Future<Map<String, dynamic>> update({
    required String script,
    required Map<String, dynamic> msg,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': state,
      'effects': <dynamic>[],
    };
  }

  Map<String, dynamic> _emptyColumn() => <String, dynamic>{
        'type': 'column',
        'children': <dynamic>[],
      };
}
