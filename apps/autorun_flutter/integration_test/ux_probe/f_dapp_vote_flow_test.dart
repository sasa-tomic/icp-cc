// ignore_for_file: lines_longer_than_80_chars

// Flow F — the headline teaching flow end-to-end (HUMAN_EXPECTATIONS §3):
//   open the bundled Poll dapp → see a real canister respond → trust → vote →
//   revoke. This is the project's reason for existing; until now every STEP was
//   verified in isolation but nothing drove the full chain through a real app
//   boot. This file is that crown-jewel regression guard.
//
// ─── Backend-data decision (the DECISION POINT in the plan) ───────────────────
// We use option (b): REAL-SHAPE CANNED canister responses, NOT a live `dfx`
// replica. Reasoning:
//   - The ux_probe env (Xvfb + mock keyring + real FFI via LD_LIBRARY_PATH)
//     deliberately runs WITHOUT a dfx replica — every other ux_probe test fakes
//     a "no connectivity" baseline. Spinning up `dfx start --clean && dfx deploy`
//     inside this test would add ~30-60s, make the canister id non-deterministic
//     (it changes every `--clean`), and introduce the exact CI flakiness the
//     task forbids ("GREEN and deterministic, no flakes"). `dfx` IS installed on
//     this box, but the test SUITE env does not include a running replica, and
//     the task mandates the same env as the other ux_probe tests.
//   - Option (b) exercises the FULL real pipeline — the REAL bundled poll app
//     executes in REAL QuickJS via the Rust FFI, the REAL ScriptAppHost effect
//     dispatcher runs, and the vote is signed with a REAL freshly-generated
//     Ed25519 keypair (FFI). The ONLY thing replaced is the network transport:
//     the canned bridge returns the exact JSON shapes a live dfx replica emits
//     (recorded in `lib/examples/06_icp_poll.js` header + proven by
//     `test/features/scripts/live_canister_auth_test.dart`). This is the
//     established `_RecordingBridge`/`_CannedBridge` pattern already used in
//     `dapp_trust_test.dart` and `dapp_runner_screen_test.dart`. NO crypto is
//     mocked.
//
// ─── Two-test structure (and the residual gap) ───────────────────────────────
// The flow is split across two tests because the real-app catalog→runner push
// path (`DappsScreen._DappCard._open`) accepts NO test-bridge seam — it always
// constructs `DappRunnerScreen(descriptor:)` with `testBridge: null`, so the
// host's canister calls hit the REAL FFI bridge (unreachable without a replica).
// Adding a seam to `DappsScreen` would violate the ux_probe contract
// (`git diff apps/autorun_flutter/lib` stays EMPTY — see r3_helpers.dart).
// Therefore:
//   F1 — drives the REAL app boot through the catalog (lib untouched): trust
//        gate, keyless CTA, and the revoke lifecycle. Proves the shell + the
//        UX-10 trust gate + the headline "open the dapp" path through live code.
//        Polls cannot render here (no replica) — that is the documented gap F2
//        closes.
//   F2 — pumps ScriptAppHost directly with the REAL bundle + REAL FFI runtime +
//        REAL Ed25519 keypair + canned canister responses, and drives the
//        currently-unverified vote→tally UI loop (audit gap #3).
// RECOMMENDED MINIMAL SEAM (to merge F1+F2 into one through-the-catalog test,
// deferred per the "no unprompted prod-code change" rule): give `DappsScreen` a
// `@visibleForTesting ScriptBridge? testBridge` forwarded to the pushed
// `DappRunnerScreen` (≈3 lines, mirrors the existing `DappRunnerScreen.testBridge`
// seam; production callers stay null). Then a single test could tap the catalog
// card and see canned polls render.
//
// ─── Run (same env as the other ux_probe tests) ───────────────────────────────
//   DISPLAY=:99 LD_LIBRARY_PATH=/code/icp-cc/target/release \
//     scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/f_dapp_vote_flow_test.dart
//
// Hard constraint honored: `git diff apps/autorun_flutter/lib` stays EMPTY.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

import 'r3_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The shipped poll dapp's stable id (single source of truth:
  // exampleDapps.first.id). Keyed everywhere trust/config persist.
  final String dappId = exampleDapps.first.id;

  // ===========================================================================
  // F1 — REAL APP BOOT through the catalog: trust gate, keyless CTA, revoke.
  // Launches the real app (lib/main.dart), dismisses the first-run wizard to
  // land keyless on the main shell, then drives the catalog → runner → trust →
  // revoke lifecycle. No backend is reachable in this env, so the listPolls
  // call fails after the trust grant; we assert the deterministic trust +
  // keyless + revoke behaviours (which are independent of the network) and do
  // NOT assert polls rendered (that is F2's job).
  // ===========================================================================
  testWidgets(
      'F1: real boot → Dapps → On-chain Polls → trust → keyless CTA → revoke',
      (tester) async {
    await clearProfileStateR3();
    // Belt-and-suspenders: the r3 helper wipes the data dir, but the persisted
    // trust grant lives in SharedPreferences (which may store outside that dir).
    // We clear it in the in-process singleton the app will share, so this run
    // starts from the first-run keyless state and the trust dialog is NOT
    // suppressed by a stale grant from a previous run.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dapp.$dappId.trusted');
    await prefs.remove('dapp.$dappId.backend_id');
    await prefs.remove('dapp.$dappId.host');

    await launchAppR3(tester);
    // Dismiss (do NOT complete) the first-run wizard: the keyless state is part
    // of this flow — step 5 asserts the keyless "Create a profile to vote" CTA.
    await dismissWizardR3(tester);

    // --- Step 2: tap the Dapps nav item → the On-chain Polls card ----------
    final dappsNav = find.text('Dapps');
    expect(presentR3(dappsNav, tester), isTrue,
        reason: 'The Dapps nav item must be present on the main shell.');
    await tester.tap(dappsNav.first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final pollCard = find.text(exampleDapps.first.title); // 'On-chain Polls'
    expect(presentR3(pollCard, tester), isTrue,
        reason: 'The "On-chain Polls" example dapp card must be in the catalog.');
    await tester.ensureVisible(pollCard);
    await tester.tap(pollCard);
    await tester.pump(const Duration(seconds: 1));

    // --- Step 3: assert the "Trust this dapp?" dialog appears (UX-10) -------
    // The dialog only fires after: the runner mounted, the host booted, the
    // REAL bundle executed in QuickJS via FFI (init), and emitted the listPolls
    // canister effect — which is what triggers the trust gate. So this single
    // assertion proves the whole catalog→runner→host→bundle boot chain works.
    bool trustDialogShown = false;
    for (int i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (presentR3(find.text('Trust this dapp?'), tester)) {
        trustDialogShown = true;
        break;
      }
    }
    expect(trustDialogShown, isTrue,
        reason: 'UX-10: the first canister effect must surface the per-dapp '
            '"Trust this dapp?" dialog. If this fails the runner/host/bundle '
            'boot is broken — check FFI load (LD_LIBRARY_PATH) and the bundle '
            'asset path.');
    // The trust gate REPLACES the strict per-method dialog — it must not appear.
    expect(presentR3(find.text('Allow canister call?'), tester), isFalse);

    await tester.tap(find.text('Trust this dapp'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // --- Step 4: the broad grant → "Trusted" chip visible (UX-10 visibility)
    expect(presentR3(find.text('Trusted'), tester), isTrue,
        reason: 'UX-10 visibility: surfacing the grant as a "Trusted" chip so '
            'the user never wonders "did I trust this?".');

    // --- Step 5: keyless CTA visible (HUMAN_EXPECTATIONS §3 dual-path teaching)
    expect(
        presentR3(find.byKey(const Key('dappCreateProfileToVoteCta')), tester),
        isTrue,
        reason: 'A keyless user must see a one-tap "Create a profile to vote" '
            'CTA inline — the pedagogical bridge from "I can see polls" to "I '
            'can vote".');
    expect(presentR3(find.text('Create a profile to vote'), tester), isTrue);
    expect(presentR3(find.textContaining('viewing only'), tester), isTrue,
        reason: 'The keyless status chip must state view-only mode.');
    // (Step 6 — creating a profile via the wizard under the mock keyring — is
    // already proven end-to-end by r3_addendum_test.dart Addendum-A. We do not
    // duplicate it here; the CTA deep-link into the wizard is proven by
    // dapp_runner_screen_test.dart's "tapping the CTA deep-links..." test.)

    // NOTE: polls do NOT render in F1 — the ux_probe env runs no dfx replica, so
    // the real listPolls call against the bundled default canister id is
    // unreachable and the bundle surfaces an error. The vote→tally loop (which
    // needs reachable canister data) is proven in F2 with real-shape canned
    // responses.

    // --- Step 8: Manage trust → Revoke → confirm → "Trusted" chip disappears -
    await tester.tap(find.byTooltip('Manage trust'));
    await tester.pump(const Duration(seconds: 1));
    expect(presentR3(find.text('Manage dapp trust'), tester), isTrue,
        reason: 'The shield toolbar button must open the Manage-trust dialog.');

    // First "Revoke trust" (in the manage dialog) opens the explicit yes/no
    // confirmation — a single accidental tap on the red button must not silently
    // undo the broad grant.
    await tester.tap(find.text('Revoke trust'));
    await tester.pump(const Duration(seconds: 1));
    expect(presentR3(find.text('Revoke trust?'), tester), isTrue,
        reason: 'Revocation of the broad grant must require confirmation.');

    // Second "Revoke trust" (in the confirm dialog) performs the revoke.
    await tester.tap(find.text('Revoke trust'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(presentR3(find.text('Trusted'), tester), isFalse,
        reason: 'UX-10 completeness: after revocation the "Trusted" chip must '
            'disappear (the broad grant is rolled back, the next canister call '
            're-prompts).');
    // The persisted grant is gone too — not just the in-memory flag.
    expect(await DappTrustStore.isTrusted(dappId), isFalse,
        reason: 'Revocation must clear the persisted trust grant.');
    // (Restart-zero-prompts — the inverse of this revoke — is already covered
    // by dapp_trust_test.dart (b): a persisted grant yields ZERO prompts on a
    // fresh host. Not duplicated here.)
  });

  // ===========================================================================
  // F2 — vote → tally update loop (audit gap #3).
  // Pumps ScriptAppHost with the REAL bundled poll app + REAL FFI QuickJS
  // runtime + REAL Ed25519 keypair, and a canned canister bridge (the only
  // seam — see the backend-data decision at the top of this file). Drives the
  // full auto-load chain (UX-11), taps a vote option, and asserts the tally
  // updates in the UI — the headline "see a real canister respond" loop.
  // ===========================================================================
  testWidgets('F2: tap a vote option → tally updates in the UI (gap #3)',
      (tester) async {
    // --- FFI probe: fail LOUD if libicp_core.so didn't load. Every assertion
    // below is meaningless without the real FFI (the bundle wouldn't execute). -
    const loader = RustBridgeLoader();
    final String? ffiProbe = loader.jsExec(script: '1', jsonArg: null);
    expect(ffiProbe, isNotNull,
        reason: 'libicp_core.so must load — set '
            'LD_LIBRARY_PATH=/code/icp-cc/target/release.');

    // --- Read the REAL bundled poll dapp source from disk. ---
    // `flutter test` runs from the package root, so this relative path resolves
    // to apps/autorun_flutter/lib/examples/06_icp_poll.js.
    final bundleFile = File('lib/examples/06_icp_poll.js');
    if (!bundleFile.existsSync()) {
      throw StateError('Poll bundle not found at ${bundleFile.path} '
          '(CWD=${Directory.current.path}).');
    }
    final String pollBundle = await bundleFile.readAsString();
    expect(pollBundle.trim(), isNotEmpty,
        reason: 'The shipped poll bundle must be non-empty (a packaging bug '
            'would ship a blank asset).');

    // --- Generate a REAL Ed25519 keypair via FFI (NO crypto mocking). ---
    // alg 0 = Ed25519. Returns the real principal derived from the real key.
    final RustKeypairResult? kp = loader.generateKeypair(alg: 0);
    expect(kp, isNotNull, reason: 'FFI keypair generation must succeed.');
    final keypair = ProfileKeypair(
      id: 'f2-voter',
      label: 'F2 Voter',
      algorithm: KeyAlgorithm.ed25519,
      publicKey: kp!.publicKeyB64,
      privateKey: kp.privateKeyB64,
      mnemonic: '', // not used by the host's signing path
      createdAt: DateTime.now().toUtc(),
      principal: kp.principalText,
    );

    // --- Canned canister bridge (the ONLY seam). Stateful: the FIRST getTally
    // (auto-load, before any vote) returns the seeded tally; AFTER an
    // authenticated vote lands, getTally reflects it (Rust +1). ---
    final bridge = _PollCannedBridge(voterPrincipal: kp.principalText);

    // --- Pre-seed trust so the auto-load effects run without the trust dialog
    // (the trust gate is proven in F1; here we isolate the vote→tally loop). ---
    await DappTrustStore.setTrusted(dappId);
    final ValueNotifier<bool> trustState = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            // REAL FFI runtime: the bundle executes in REAL QuickJS via the
            // Rust FFI (init/view/update). This is NOT a fake runtime.
            runtime: ScriptAppRuntime(RustScriptBridge(loader)),
            script: pollBundle,
            initialArg: <String, dynamic>{
              'backend_id': kLocalPollBackendCanisterId,
              'host': kLocalPollHost,
            },
            dappTrustId: dappId,
            dappTrustState: trustState,
            // The only mock: canned canister responses (real-shape JSON).
            testBridge: bridge,
            // REAL Ed25519 keypair — authenticated effects sign as this identity.
            authenticatedKeypair: keypair,
          ),
        ),
      ),
    );

    // --- Step 4: auto-load (UX-11) → init emits effects → listPolls → getTally
    // → real polls render. pumpAndSettle drains the whole chained dispatch. ---
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(trustState.value, isTrue,
        reason: 'The pre-seeded trust grant must be published to the notifier '
            'on load (so a parent chip would render).');
    expect(find.text('Rust or Motoko?'), findsOneWidget,
        reason: 'UX-11 auto-load: the poll question must render without a '
            'manual Refresh (init → listPolls → getTally).');
    // The bundled poll has two options rendered as FilledButtons.
    expect(find.widgetWithText(FilledButton, 'Rust'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Motoko'), findsOneWidget);
    // Initial tally for Rust is "1" (the canned seeded tally).
    expect(_optionTallyText(tester, 'Rust'), '1',
        reason: 'Initial Rust tally must render as "1".');

    // --- Step 7: tap "Rust" → the tally must update to "2" (gap #3) ----------
    await tester.tap(find.widgetWithText(FilledButton, 'Rust'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(_optionTallyText(tester, 'Rust'), '2',
        reason: 'vote→tally loop: after voting for Rust, the tally must update '
            'from "1" to "2" in the UI. This is the headline pedagogical loop '
            '(HUMAN_EXPECTATIONS §3 — see a real canister respond to your vote).');
    // The vote really was an authenticated UPDATE through the real keypair.
    expect(bridge.authenticatedVoteCalls, greaterThanOrEqualTo(1),
        reason: 'The vote must be an authenticated UPDATE canister call signed '
            'by the real Ed25519 keypair (the bundle sets authenticated:true on '
            'vote effects; the host resolves the key — raw keys never enter the '
            'sandbox).');
  });
}

// ---------------------------------------------------------------------------
// Test helpers.
// ---------------------------------------------------------------------------

/// Reads the tally count text rendered next to a poll vote [option] (e.g.
/// "Rust"). The bundled poll renders each option as a Row containing a
/// FilledButton (the option label) and a Text (the tally count). This finds
/// that Row and returns the numeric tally string, or null if the poll hasn't
/// rendered yet / the option isn't present.
String? _optionTallyText(WidgetTester tester, String option) {
  final Finder button = find.widgetWithText(FilledButton, option);
  if (!tester.any(button)) return null;
  final Finder row =
      find.ancestor(of: button, matching: find.byType(Row)).first;
  final Iterable<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)));
  for (final Text t in texts) {
    final String d = t.data ?? '';
    // The tally is the numeric text that is NOT the button label.
    if (d != option && int.tryParse(d) != null) return d;
  }
  return null;
}

/// Canned canister bridge for the bundled poll dapp (F2).
///
/// Returns the EXACT JSON shapes a live dfx replica emits (recorded in
/// `lib/examples/06_icp_poll.js` header and proven by
/// `live_canister_auth_test.dart`):
///   listPolls → {"ok":true,"result":[{"id","question","options","creator"}]}
///   getTally  → {"ok":true,"result":["rustCount","motokoCount"]} (vec nat)
///   whoami    → {"ok":true,"result":"principal-STRING"}
///   vote      → {"ok":true,"result":[]}
///
/// Stateful: before any authenticated `vote` lands, getTally returns the seeded
/// tally (Rust=1); after a vote lands, getTally reflects it (Rust=2). This
/// models the canister state change a real vote causes, so the bundle's
/// vote→refresh→getTally chain produces a visible tally delta in the UI.
///
/// The `jsApp*` lifecycle methods are unused: the host never invokes them on
/// `testBridge` — the REAL `ScriptAppRuntime` owns bundle execution via its own
/// `RustScriptBridge`. They return null only to satisfy the interface.
class _PollCannedBridge implements ScriptBridge {
  _PollCannedBridge({required this.voterPrincipal});

  /// Returned by `whoami` — the ACTUAL principal of the real signing keypair
  /// (so the dapp displays the voter's real identity, not a placeholder).
  final String voterPrincipal;

  /// Count of authenticated `vote` UPDATE calls observed (asserted in F2).
  int authenticatedVoteCalls = 0;

  /// Flipped to true when an authenticated `vote` lands; subsequent getTally
  /// responses reflect the vote.
  bool _voted = false;

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) {
    switch (method) {
      case 'listPolls':
        return json.encode(<String, dynamic>{
          'ok': true,
          'result': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': '3',
              'question': 'Rust or Motoko?',
              'options': <String>['Rust', 'Motoko'],
              // The anonymous principal — a real canister returns the creator's
              // principal as a STRING (principal serialization).
              'creator': '2vxsx-faaaa-aaaak-qblaq-cai',
            },
          ],
        });
      case 'getTally':
        // vec nat serializes as an array of numeric strings. After a vote lands
        // the Rust option increments; before, the seeded tally is returned.
        final int rust = _voted ? 2 : 1;
        return json.encode(<String, dynamic>{
          'ok': true,
          'result': <String>['$rust', '0'],
        });
    }
    return json.encode(<String, dynamic>{
      'ok': true,
      'result': <String>[],
    });
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
    switch (method) {
      case 'whoami':
        // Returns the real principal of the signing keypair (query, auth).
        return json.encode(<String, dynamic>{
          'ok': true,
          'result': voterPrincipal,
        });
      case 'vote':
        // Authenticated UPDATE. Flip _voted so the refresh's getTally reflects
        // this vote — exactly how a real canister's tally would change.
        authenticatedVoteCalls++;
        _voted = true;
        return json.encode(<String, dynamic>{
          'ok': true,
          'result': <String>[],
        });
    }
    return json.encode(<String, dynamic>{
      'ok': true,
      'result': <String>[],
    });
  }

  // Unused: the REAL ScriptAppRuntime (with its own RustScriptBridge) owns
  // bundle execution; the host never calls these on testBridge.
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
