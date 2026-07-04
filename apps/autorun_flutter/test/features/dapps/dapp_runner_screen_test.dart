// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/services/secure_storage_readiness.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

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

  // ─────────────── Keyless-user CTA (HUMAN_EXPECTATIONS §3) ───────────────
  // A keyless user can view the dapp but can't vote. They get a one-tap
  // "Create a profile to vote" CTA inline (no hunting the profile menu), which
  // deep-links into the same wizard used at first run. The CTA disappears once
  // a profile exists (no slop for profiled users).
  testWidgets(
      'keyless user sees an obvious Create-profile-to-vote CTA '
      '(dual-path teaching)', (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // The CTA is present with a stable key + honest copy. This is the
    // pedagogical bridge from "I can see polls" → "I can vote".
    final cta = find.byKey(const Key('dappCreateProfileToVoteCta'));
    expect(cta, findsOneWidget,
        reason: 'A keyless user must see an obvious create-profile CTA inline, '
            'not a passive hint buried in a chip.');
    expect(find.text('Create a profile to vote'), findsOneWidget);

    // The hint teaches the dual-path model: view anonymously, act with identity.
    expect(find.textContaining('read polls anonymously'),
        findsOneWidget);
    expect(find.textContaining('Creating a profile lets you vote'),
        findsOneWidget);
  });

  testWidgets(
      'tapping the CTA deep-links into the real profile-creation wizard',
      (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunner(
      tester,
      descriptor,
      runtime: runtime,
      // Inject a fixed-ready probe so the test is hermetic (the real probe
      // would shell out to gnome-keyring-daemon on a Linux host). The wizard's
      // readiness behavior itself is covered by its own tests.
      secureStorageReadiness: _FixedReadiness(const StorageReady()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dappCreateProfileToVoteCta')));
    await tester.pumpAndSettle();

    // ONE tap → the real wizard (not a stub/dead-end). It's the same widget the
    // first-run gate uses, so the user lands on the guided form they know.
    expect(find.byType(UnifiedSetupWizard), findsOneWidget);
    expect(find.text('Create Your Profile'), findsOneWidget,
        reason: 'The wizard\'s form heading must be visible after deep-link.');
  });

  testWidgets('profiled user sees NO create-profile CTA (no slop)',
      (tester) async {
    final runtime = _RecordingRuntime();
    await _pumpRunnerWithProfile(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // Slop guard: the CTA is for keyless users only. A profiled user must not
    // see a useless "create a profile" button.
    expect(find.byKey(const Key('dappCreateProfileToVoteCta')), findsNothing);
    expect(find.text('Create a profile to vote'), findsNothing);

    // The success chip replaces the warning chip — the user sees they're signed.
    expect(find.textContaining('No active profile'), findsNothing);
    expect(find.textContaining('Signed'), findsOneWidget);
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

  // ===========================================================================
  // UX-10 completeness: trust-state visibility + revoke affordance.
  // The host-level primitive (ScriptAppHostState.revokeTrust) is covered in
  // dapp_trust_test.dart; these are the end-to-end UI flows that exercise the
  // DappRunnerScreen wiring: the Trusted status chip, the manage-trust dialog
  // (per-state copy), the confirmation step (cancel = no change), and the
  // success path (grant cleared + snackbar + chip disappears).
  // ===========================================================================

  testWidgets(
      'UX-10 visibility: a Trusted status chip renders when the dapp is '
      'trusted, and is hidden when not', (tester) async {
    // (1) NOT trusted: chip must be absent.
    final runtimeA = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtimeA);
    await tester.pumpAndSettle();
    expect(find.text('Trusted'), findsNothing,
        reason: 'Untrusted dapp must not show the Trusted chip');
    // The manage-trust toolbar entry is always present, though.
    expect(find.byTooltip('Manage trust'), findsOneWidget);

    // (2) Trusted: chip must appear. Pump a fresh app so the previous
    // widget tree is gone, then prime the persisted grant.
    await tester.pumpWidget(Container()); // tear down the previous tree.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dapp.${descriptor.id}.trusted': true,
    });
    final runtimeB = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtimeB);
    await tester.pumpAndSettle();

    expect(find.text('Trusted'), findsOneWidget,
        reason: 'Trusted dapp must surface a visible Trusted chip');
  });

  testWidgets(
      'UX-10 manage dialog: shows the trusted body + Revoke button when '
      'trusted, and the not-trusted body (no Revoke) when not', (tester) async {
    // (1) Not trusted → dialog copy reflects it and offers no revoke.
    final runtimeA = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtimeA);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage trust'));
    await tester.pumpAndSettle();

    expect(find.text('Manage dapp trust'), findsOneWidget);
    expect(find.textContaining('not trusted'), findsOneWidget);
    expect(find.text('Revoke trust'), findsNothing,
        reason: 'Revoke must be unavailable when there is no grant');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // (2) Trusted → dialog copy reflects it and offers revoke.
    await tester.pumpWidget(Container());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dapp.${descriptor.id}.trusted': true,
    });
    final runtimeB = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtimeB);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage trust'));
    await tester.pumpAndSettle();

    expect(find.text('Manage dapp trust'), findsOneWidget);
    expect(find.textContaining('trusted'), findsOneWidget);
    expect(find.text('Revoke trust'), findsOneWidget,
        reason: 'Revoke must be available when the dapp is trusted');
  });

  testWidgets(
      'UX-10 revoke POSITIVE: Manage → Revoke → confirm clears the grant, '
      'shows the snackbar, and hides the Trusted chip', (tester) async {
    // Prime persisted trust so the chip is visible at boot.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dapp.${descriptor.id}.trusted': true,
    });
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    // Sanity: the chip is present and the grant is in storage.
    expect(find.text('Trusted'), findsOneWidget);
    expect(await DappTrustStore.isTrusted(descriptor.id), isTrue);

    // Open Manage trust → tap Revoke trust → confirmation appears.
    await tester.tap(find.byTooltip('Manage trust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke trust'));
    await tester.pumpAndSettle();

    // Confirmation dialog is on screen.
    expect(find.text('Revoke trust?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Confirm. The manage dialog has been popped, so the only "Revoke trust"
    // button left is the confirmation dialog's.
    expect(find.text('Revoke trust'), findsOneWidget,
        reason: 'confirm dialog must render exactly one Revoke trust button');
    await tester.tap(find.text('Revoke trust'));
    await tester.pumpAndSettle();

    // The grant is gone from storage.
    expect(await DappTrustStore.isTrusted(descriptor.id), isFalse);
    // The snackbar surfaces honest feedback.
    expect(
        find.textContaining("Trust revoked — you'll be asked again"),
        findsOneWidget);
    // The Trusted chip disappears (state flipped).
    expect(find.text('Trusted'), findsNothing);
  });

  testWidgets(
      'UX-10 revoke NEGATIVE: cancelling the confirmation leaves the grant '
      'intact (no snackbar, chip stays)', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dapp.${descriptor.id}.trusted': true,
    });
    final runtime = _RecordingRuntime();
    await _pumpRunner(tester, descriptor, runtime: runtime);
    await tester.pumpAndSettle();

    expect(find.text('Trusted'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage trust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke trust'));
    await tester.pumpAndSettle();

    // Confirmation is showing — bail out with Cancel.
    expect(find.text('Revoke trust?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Nothing changed: grant intact, no snackbar, chip still visible.
    expect(await DappTrustStore.isTrusted(descriptor.id), isTrue);
    expect(find.textContaining("Trust revoked"), findsNothing);
    expect(find.text('Trusted'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // UX-12(b): reactive Connection-panel auto-expand on canister-unreachable.
  // The flagged real-user stumble: a stale canister id (e.g. after
  // `dfx start --clean`) leaves the panel COLLAPSED, hiding the recovery hint.
  // These tests codify that the FIRST reachability failure auto-expands the
  // panel + surfaces a concise hint, while the happy path and non-reachability
  // failures (permission denial, Candid decode) leave it collapsed.
  // ─────────────────────────────────────────────────────────────────────────
  group('UX-12(b) Connection panel auto-expand', () {
    final DappDescriptor dapp = exampleDapps.first;

    // The Connection panel is collapsed iff its editable fields are NOT in the
    // tree (the ExpansionTile lazy-builds its children only when expanded).
    Finder backendIdField() => find.byKey(const Key('dappBackendIdField'));

    testWidgets(
        'FIRST reachability failure (net) auto-expands the panel + shows the hint',
        (tester) async {
      // Bridge returns a typed `net` reachability failure — mirrors what the
      // Rust FFI emits (`canister_err_ptr`) when the replica/canister is
      // unreachable (connection refused, timeout, stale id on the replica).
      final bridge = _CannedBridge(
        anonymous: '{"ok":false,"kind":"net",'
            '"error":"network error: connection refused"}',
      );
      await _pumpRunnerWithBridge(
        tester,
        dapp,
        runtime: _EffectInitRuntime(_anonListPollsEffect()),
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      // The per-dapp trust gate prompts before the first call reaches the
      // bridge. Grant trust so the call proceeds and the bridge failure fires.
      expect(find.text('Trust this dapp?'), findsOneWidget);
      await tester.tap(find.text('Trust this dapp'));
      await tester.pumpAndSettle();

      // REACTIVE: panel auto-expanded (fields now visible) ...
      expect(backendIdField(), findsOneWidget,
          reason: 'A reachability failure must auto-expand the Connection '
              'panel so the recovery fields are visible');
      // ... and the honest, non-alarmist hint points the user at them.
      expect(find.text('Canister unreachable'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('dappUnreachableHint')),
          findsOneWidget);
      // The bridge really was invoked (the failure is real, not a guard).
      expect(bridge.anonymousCalls, 1);
    });

    testWidgets('happy path (reachable canister) keeps the panel collapsed',
        (tester) async {
      // A successful call: no failure → no auto-expand. UX-12(a) goal #3
      // preserved: a working connection demands no attention.
      final bridge = _CannedBridge(anonymous: '{"ok":true,"result":[]}');
      await _pumpRunnerWithBridge(
        tester,
        dapp,
        runtime: _EffectInitRuntime(_anonListPollsEffect()),
        bridge: bridge,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust this dapp'));
      await tester.pumpAndSettle();

      expect(backendIdField(), findsNothing,
          reason: 'A working connection must NOT auto-expand the panel');
      expect(find.text('Canister unreachable'), findsNothing);
      expect(bridge.anonymousCalls, 1);
    });

    testWidgets(
        'a Candid decode failure does NOT auto-expand (NOT a reachability '
        'failure — the call reached the canister)', (tester) async {
      // The call succeeded at the network layer; only the response decode
      // failed. That is NOT "canister unreachable" — the connection is fine,
      // so the panel must NOT demand attention.
      final bridge = _CannedBridge(
        anonymous: '{"ok":false,"kind":"candid",'
            '"error":"candid parse error: decode failed"}',
      );
      await _pumpRunnerWithBridge(
        tester,
        dapp,
        runtime: _EffectInitRuntime(_anonListPollsEffect()),
        bridge: bridge,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust this dapp'));
      await tester.pumpAndSettle();

      expect(backendIdField(), findsNothing,
          reason: 'A Candid decode error is not a reachability failure — '
              'panel must stay collapsed');
      expect(find.text('Canister unreachable'), findsNothing);
      expect(bridge.anonymousCalls, 1);
    });

    testWidgets(
        'a permission denial does NOT auto-expand (host-side gate, never '
        'reaches the bridge)', (tester) async {
      // Deny the per-dapp trust prompt: the effect short-circuits with
      // "permission denied" before any bridge call. This is the explicit
      // negative path called out in the task.
      final bridge = _CannedBridge(anonymous: '{"ok":true,"result":[]}');
      await _pumpRunnerWithBridge(
        tester,
        dapp,
        runtime: _EffectInitRuntime(_anonListPollsEffect()),
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      expect(find.text('Trust this dapp?'), findsOneWidget);
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      expect(backendIdField(), findsNothing,
          reason: 'A permission denial must NOT auto-expand the panel');
      expect(find.text('Canister unreachable'), findsNothing);
      // The bridge was never called: denial is host-side.
      expect(bridge.anonymousCalls, 0);
    });
  });
}

Future<void> _pumpRunner(
  WidgetTester tester,
  DappDescriptor descriptor, {
  required _RecordingRuntime runtime,
  SecureStorageReadiness? secureStorageReadiness,
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
          testSecureStorageReadiness: secureStorageReadiness,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Pumps the runner with an ACTIVE profile (a real keypair from
/// [TestKeypairFactory] held in an in-memory [FakeProfileRepository]) so the
/// runner sees `activeKeypair != null` without touching secure storage / a
/// keyring. Used by the "no slop for profiled users" test.
Future<ProfileController> _pumpRunnerWithProfile(
  WidgetTester tester,
  DappDescriptor descriptor, {
  required _RecordingRuntime runtime,
}) async {
  final keypair = await TestKeypairFactory.getEd25519Keypair();
  final now = DateTime.now().toUtc();
  final profile = Profile(
    id: 'profile_test_active',
    name: 'Alice',
    keypairs: [keypair],
    username: null,
    createdAt: now,
    updatedAt: now,
  );
  final fakeRepo = FakeProfileRepository([profile]);
  final prefs = await SharedPreferences.getInstance();
  final profileController = ProfileController(
    profileRepository: fakeRepo,
    preferences: prefs,
    marketplaceService: MarketplaceOpenApiService(),
  );
  await profileController.ensureLoaded();
  await profileController.setActiveProfile(profile.id);

  await tester.pumpWidget(
    ProfileScope(
      controller: profileController,
      child: MaterialApp(
        home: DappRunnerScreen(
          descriptor: descriptor,
          testRuntime: runtime,
          testBundle: '/* test bundle */',
        ),
      ),
    ),
  );
  await tester.pump();
  return profileController;
}

/// A [SecureStorageReadiness] that returns a fixed result, so the deep-link
/// navigation test is hermetic (the real probe would shell out to
/// gnome-keyring-daemon on a Linux host). Readiness is platform availability,
/// not cryptography — the legit test seam, mirroring the wizard's own tests.
class _FixedReadiness extends SecureStorageReadiness {
  _FixedReadiness(this.result);
  final StorageReadiness result;

  @override
  Future<StorageReadiness> check() async => result;
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

/// A runtime that emits ONE effect from `init` (then none from update/view),
/// so UX-12(b) tests can drive the host's effect-dispatch path — including the
/// per-dapp trust gate and the canister bridge call — without executing a real
/// TS bundle. Mirrors the `_EffectRuntime` pattern in
/// `script_app_host_auth_test.dart`.
class _EffectInitRuntime implements IScriptAppRuntime {
  _EffectInitRuntime(this.initEffect);

  final Map<String, dynamic> initEffect;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': <Map<String, dynamic>>[initEffect],
    };
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
    return <String, dynamic>{
      'ok': true,
      'state': state,
      'effects': <dynamic>[],
    };
  }
}

/// A [ScriptBridge] whose canister-call responses are fully controlled by the
/// test. `anonymous` is the canned JSON returned by every `callAnonymous`
/// (the value the Rust FFI would return — success `{"ok":true,"result":...}`
/// or a typed error `{"ok":false,"kind":...,"error":...}`). Records call counts
/// so tests assert the bridge really was (or was not) invoked. NO crypto is
/// mocked — these tests exercise classification/wiring, not signing.
class _CannedBridge implements ScriptBridge {
  _CannedBridge({this.anonymous = '{"ok":true,"result":[]}'});
  final String anonymous;
  int anonymousCalls = 0;
  int authenticatedCalls = 0;

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) {
    anonymousCalls++;
    return anonymous;
  }

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
    authenticatedCalls++;
    return anonymous;
  }

  // Lifecycle helpers are unused here but required by the interface.
  @override
  String? jsExec({required String script, String? jsonArg}) => null;
  @override
  String? jsLint({required String script}) => null;
  @override
  String? jsAppInit({required String script, String? jsonArg, int budgetMs = 50}) =>
      null;
  @override
  String? jsAppView(
          {required String script,
          required String stateJson,
          int budgetMs = 50}) =>
      null;
  @override
  String? jsAppUpdate(
          {required String script,
          required String msgJson,
          required String stateJson,
          int budgetMs = 50}) =>
      null;
}

/// An anonymous `icp_call` effect (the shape `listPolls` would emit on boot) —
/// no auth requested, so a view-only (no profile) runner still drives the
/// bridge via `callAnonymous`.
Map<String, dynamic> _anonListPollsEffect() => <String, dynamic>{
      'kind': 'icp_call',
      'id': 'listPolls',
      'mode': 0,
      'canister_id': 'uxrrr-q7777-77774-qaaaq-cai',
      'method': 'listPolls',
      'args': '()',
      'authenticated': false,
    };

/// Pumps the runner with BOTH an injected runtime (emitting effects) and a
/// canister bridge, so UX-12(b) tests can simulate a reachability failure
/// without the network or the real FFI. Mirrors [_pumpRunner] otherwise.
Future<void> _pumpRunnerWithBridge(
  WidgetTester tester,
  DappDescriptor descriptor, {
  required _EffectInitRuntime runtime,
  required _CannedBridge bridge,
}) async {
  final profileController = ProfileController(
    marketplaceService: MarketplaceOpenApiService(),
  );
  await tester.pumpWidget(
    ProfileScope(
      controller: profileController,
      child: MaterialApp(
        home: DappRunnerScreen(
          descriptor: descriptor,
          testRuntime: runtime,
          testBundle: '/* test bundle */',
          testBridge: bridge,
        ),
      ),
    ),
  );
  await tester.pump();
}
