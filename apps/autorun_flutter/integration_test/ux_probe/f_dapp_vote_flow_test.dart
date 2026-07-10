// ignore_for_file: lines_longer_than_80_chars

// Flow F — the headline teaching flow end-to-end (HUMAN_EXPECTATIONS §3):
//   open the bundled Poll dapp → see a real canister respond → trust → vote →
//   revoke, all driven through ONE real app boot via the catalog. This is the
//   project's reason for existing; this file is that crown-jewel regression
//   guard.
//
// ─── Backend-data decision (REAL-SHAPE CANNED canister responses) ─────────────
// We use REAL-SHAPE CANNED canister responses, NOT a live `dfx` replica:
//   - The ux_probe env (Xvfb + mock keyring + real FFI via LD_LIBRARY_PATH)
//     deliberately runs WITHOUT a dfx replica — every other ux_probe test fakes
//     a "no connectivity" baseline. Spinning up `dfx start --clean && dfx deploy`
//     inside this test would add ~30-60s, make the canister id non-deterministic
//     (it changes every `--clean`), and introduce the exact CI flakiness the
//     task forbids ("GREEN and deterministic, no flakes"). `dfx` IS installed on
//     this box, but the test SUITE env does not include a running replica.
//   - This exercises the FULL real pipeline — the REAL bundled poll app
//     executes in REAL QuickJS via the Rust FFI, the REAL ScriptAppHost effect
//     dispatcher runs, and the vote is signed with a REAL freshly-generated
//     Ed25519 keypair (FFI) under the REAL ProfileController + libsecret round
//     trip. The ONLY thing replaced is the network transport: the canned bridge
//     returns the exact JSON shapes a live dfx replica emits (recorded in
//     `lib/examples/06_icp_poll.js` header + proven by
//     `test/features/scripts/live_canister_auth_test.dart`). This is the
//     established `_RecordingBridge`/`_CannedBridge` pattern already used in
//     `dapp_trust_test.dart` and `dapp_runner_screen_test.dart`. NO crypto is
//     mocked.
//
// ─── ONE through-the-catalog test (the merged F) ─────────────────────────────
// Previously this file was split F1 (catalog→runner→trust→revoke, keyless, real
// boot) + F2 (vote→tally at host level) because `DappsScreen` had NO test seam
// — its card always pushed `DappRunnerScreen(testBridge: null)`, so the
// catalog→runner push hit the real FFI bridge (unreachable without a replica),
// and the vote→tally loop could only be proven by pumping ScriptAppHost
// directly. `DappsScreen` now mirrors `DappRunnerScreen.testBridge`:
//   - `DappsScreen.testBridge` constructor param (mirrors the runner's seam);
//   - a process-wide override via the get_it service locator
//     (`registerTestScriptBridge`) so a test that boots via `app.main()` (which
//     constructs `DappsScreen()` with no args) can still inject a canned bridge
//     into the catalog→runner push. Both null-defaulted → zero prod behavior.
// The single merged test below sets the override before `app.main()`, then
// drives the WHOLE flow through the real app boot + real catalog → real runner
// → real host → real bundle → real trust gate → real vote (real Ed25519) → real
// revoke. This is strictly stronger than F1+F2: every assertion from both is
// preserved AND they now chain through one real code path instead of two.
//
// ─── Keyless → signed bridge (HUMAN_EXPECTATIONS §3) ─────────────────────────
// The flow boots KEYLESS (dismiss the wizard, never complete it) so the
// keyless "view-only" + "Create a profile to vote" CTA is exercised. The poll
// auto-loads (listPolls + getTally are anonymous → render view-only). Voting,
// however, is an AUTHENTICATED effect — the host correctly blocks it without a
// keypair (missingAuth, a security property). To cross the "act with identity"
// bridge the test creates ONE real profile via the running app's
// ProfileController (real FFI gen + real libsecret round-trip under the mock
// keyring) — NOT via the wizard UI, which is already proven end-to-end by
// `r3_addendum_test.dart` Addendum-A. After the profile is active, the vote
// signs with the real Ed25519 keypair and the tally updates (1→2).
//
// ─── Run (mock keyring required for the mid-flow profile create) ──────────────
//   DISPLAY=:99 LD_LIBRARY_PATH=/code/icp-cc/target/release \
//     scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/f_dapp_vote_flow_test.dart
//
// The mid-flow profile creation uses real secure storage → this test runs under
// PASS 2 (mock keyring) of `just test-ux-probe`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/services/service_locator.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

import 'r3_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The shipped poll dapp (referenced by stable id, NOT `.first` — the catalog
  // intentionally lists the mainnet example first now, so registry order is not
  // a test contract). Keyed everywhere trust/config persist.
  final DappDescriptor pollDescriptor =
      exampleDapps.firstWhere((d) => d.id == 'icp_poll');
  final String dappId = pollDescriptor.id;

  // ===========================================================================
  // F — ONE through-the-catalog headline flow: real boot → catalog → runner →
  // trust → polls render → keyless CTA → create profile → vote → tally 1→2 →
  // revoke. Merges the former F1 (boot+trust+keyless+revoke) and F2
  // (vote→tally) into a single real-code-path chain.
  // ===========================================================================
  testWidgets(
      'F: real boot → catalog → On-chain Polls → trust → polls → vote 1→2 → '
      'revoke (one through-the-catalog flow)', (tester) async {
    // --- Belt-and-suspenders state clearing so this run starts first-run ---
    // r3_helpers wipes the data dir; the persisted trust grant + connection
    // overrides live in SharedPreferences, which we clear in the in-process
    // singleton the app will share.
    await clearProfileStateR3();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dapp.$dappId.trusted');
    await prefs.remove('dapp.$dappId.backend_id');
    await prefs.remove('dapp.$dappId.host');

    // --- FFI probe: fail LOUD if libicp_core.so didn't load. Every downstream
    // assertion (bundle exec, keypair gen, vote signing) is meaningless without
    // the real FFI. ---
    const loader = RustBridgeLoader();
    final String? ffiProbe = loader.jsExec(script: '1', jsonArg: null);
    expect(ffiProbe, isNotNull,
        reason: 'libicp_core.so must load — set '
            'LD_LIBRARY_PATH=/code/icp-cc/target/release.');

    // --- Canned canister bridge (the ONLY transport seam). voterPrincipal is
    // filled in AFTER the real profile is created mid-flow (so whoami returns
    // the real signing principal — NO crypto is mocked). ---
    final bridge = _PollCannedBridge(voterPrincipal: '');

    // --- Inject through the service locator so the catalog→runner push uses
    // the canned bridge while still exercising the real app boot + wizard +
    // bottom-nav. Null-defaulted in prod → zero behavior change.
    registerTestScriptBridge(bridge);

    try {
      await launchAppR3(tester);
      // Dismiss (do NOT complete) the first-run wizard: the keyless state is
      // part of this flow — the CTA + view-only status are asserted below.
      await dismissWizardR3(tester);

      // --- Step 2: tap the Dapps nav item → the On-chain Polls card --------
      final dappsNav = find.text('Dapps');
      expect(presentR3(dappsNav, tester), isTrue,
          reason: 'The Dapps nav item must be present on the main shell.');
      await tester.tap(dappsNav.first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      final pollCard = find.text(pollDescriptor.title); // 'On-chain Polls'
      expect(presentR3(pollCard, tester), isTrue,
          reason: 'The "On-chain Polls" example dapp card must be in the '
              'catalog.');
      await tester.ensureVisible(pollCard);
      await tester.tap(pollCard);
      await tester.pump(const Duration(seconds: 1));

      // --- Step 3: assert the "Trust this dapp?" dialog appears (UX-10) -----
      // The dialog only fires after: the runner mounted, the host booted, the
      // REAL bundle executed in QuickJS via FFI (init), and emitted the
      // listPolls canister effect — which is what triggers the trust gate. So
      // this single assertion proves the whole catalog→runner→host→bundle boot
      // chain works through the REAL DappsScreen card push (using the injected
      // canned bridge).
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
                  'boot is broken — check FFI load (LD_LIBRARY_PATH), the bundle '
                  'asset path, and the service-locator ScriptBridge override.');
      // The trust gate REPLACES the strict per-method dialog — it must not
      // appear.
      expect(presentR3(find.text('Allow canister call?'), tester), isFalse);

      await tester.tap(find.text('Trust this dapp'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // --- Step 4: the broad grant → "Trusted" chip visible (UX-10 visibility)
      expect(presentR3(find.text('Trusted'), tester), isTrue,
          reason: 'UX-10 visibility: surfacing the grant as a "Trusted" chip '
              'so the user never wonders "did I trust this?".');

      // --- Step 5: polls RENDER (canned listPolls/getTally, real-shape data) -
      // This is the gap F1 could not close (real FFI bridge → unreachable
      // without a replica). With the canned bridge injected through the
      // DappsScreen seam, the catalog→runner→host→bundle chain now delivers
      // real-shape poll data the same way F2 proven it at the host level.
      bool pollsRendered = false;
      for (int i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (presentR3(find.text('Rust or Motoko?'), tester)) {
          pollsRendered = true;
          break;
        }
      }
      expect(pollsRendered, isTrue,
          reason: 'UX-11 auto-load through the catalog: init → listPolls → '
              'getTally must render the poll question without a manual Refresh, '
              'proven now through the real DappsScreen → DappRunnerScreen push.');
      // The bundled poll has two options rendered as FilledButtons.
      expect(find.widgetWithText(FilledButton, 'Rust'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Motoko'), findsOneWidget);
      // Initial tally for Rust is "1" (the canned seeded tally).
      expect(_optionTallyText(tester, 'Rust'), '1',
          reason: 'Initial Rust tally must render as "1".');

      // --- Step 6: keyless CTA visible (HUMAN_EXPECTATIONS §3 dual-path) -----
      // (Wizard-create-profile is proven end-to-end by r3_addendum_test.dart
      // Addendum-A; the CTA deep-link into the wizard is proven by
      // dapp_runner_screen_test.dart. Not duplicated here.)
      expect(
          presentR3(find.byKey(const Key('dappCreateProfileToVoteCta')), tester),
          isTrue,
          reason: 'A keyless user must see a one-tap "Create a profile to vote" '
              'CTA inline — the pedagogical bridge from "I can see polls" to "I '
              'can vote".');
      expect(presentR3(find.text('Create a profile to vote'), tester), isTrue);
      expect(presentR3(find.textContaining('viewing only'), tester), isTrue,
          reason: 'The keyless status chip must state view-only mode.');

      // --- Step 7: create ONE real profile so the authenticated vote can sign -
      // The vote effect is `authenticated: true`; the host correctly blocks it
      // without a keypair (missingAuth — a security property). Crossing the
      // "act with identity" bridge requires a real Ed25519 keypair. We create
      // it via the RUNNING app's ProfileController (real FFI gen + real
      // libsecret round-trip under the mock keyring) — NOT via the wizard UI
      // (r3_addendum owns the wizard UI path). After this, the runner rebuilds
      // (ProfileScope listen) and the host's next authenticated effect signs as
      // this keypair.
      final BuildContext scopeContext =
          tester.element(find.byType(DappRunnerScreen));
      // Grabbing the running app's controller from the live tree after prior
      // async pumps is intentional and safe here (no navigation across the gap).
      final ProfileController profileController = ProfileScope.of(
        // ignore: use_build_context_synchronously
        scopeContext,
        listen: false,
      );
      String? voterPrincipal;
      await tester.runAsync(() async {
        final profile = await profileController.createProfile(
          profileName: 'F Voter',
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        );
        voterPrincipal = profile.keypairs.first.principal;
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(voterPrincipal, isNotNull,
          reason: 'Profile creation must yield a real Ed25519 principal via '
              'FFI + libsecret under the mock keyring.');
      // Feed the real principal back to the canned bridge so whoami returns the
      // voter's real identity (not a placeholder) — honesty: NO crypto mocked.
      bridge.voterPrincipal = voterPrincipal!;
      // The runner must have rebuilt with the new active keypair.
      expect(profileController.activeKeypair, isNotNull,
          reason: 'The created profile must be active so the host can sign the '
              'vote.');

      // --- Step 8: tap "Rust" → authenticated vote → tally updates 1→2 -------
      // The headline pedagogical loop (HUMAN_EXPECTATIONS §3 — see a real
      // canister respond to your vote), now driven through the real catalog.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Rust'));
      await tester.tap(find.widgetWithText(FilledButton, 'Rust'));
      // The vote → result → refresh(whoami+listPolls) → getTally chain is a
      // multi-step async dispatch; bounded-pump until the tally flips to "2".
      bool tallyUpdated = false;
      for (int i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (_optionTallyText(tester, 'Rust') == '2') {
          tallyUpdated = true;
          break;
        }
      }
      expect(tallyUpdated, isTrue,
          reason: 'vote→tally loop: after voting for Rust (signed by the real '
              'Ed25519 keypair), the tally must update from "1" to "2" in the '
              'UI. This is the headline pedagogical loop, now proven through '
              'the real catalog→runner→host chain.');
      // The vote really was an authenticated UPDATE through the real keypair.
      expect(bridge.authenticatedVoteCalls, greaterThanOrEqualTo(1),
          reason: 'The vote must be an authenticated UPDATE canister call '
              'signed by the real Ed25519 keypair (the bundle sets '
              'authenticated:true on vote effects; the host resolves the key — '
              'raw keys never enter the sandbox).');

      // --- Step 9: Manage trust → Revoke → confirm → "Trusted" chip disappears
      await tester.tap(find.byTooltip('Manage trust'));
      await tester.pump(const Duration(seconds: 1));
      expect(presentR3(find.text('Manage dapp trust'), tester), isTrue,
          reason: 'The shield toolbar button must open the Manage-trust dialog.');

      // First "Revoke trust" (in the manage dialog) opens the explicit yes/no
      // confirmation — a single accidental tap on the red button must not
      // silently undo the broad grant.
      await tester.tap(find.text('Revoke trust'));
      await tester.pump(const Duration(seconds: 1));
      expect(presentR3(find.text('Revoke trust?'), tester), isTrue,
          reason: 'Revocation of the broad grant must require confirmation.');

      // Second "Revoke trust" (in the confirm dialog) performs the revoke.
      await tester.tap(find.text('Revoke trust'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(presentR3(find.text('Trusted'), tester), isFalse,
          reason: 'UX-10 completeness: after revocation the "Trusted" chip '
              'must disappear (the broad grant is rolled back, the next '
              'canister call re-prompts).');
      // The persisted grant is gone too — not just the in-memory flag.
      expect(await DappTrustStore.isTrusted(dappId), isFalse,
          reason: 'Revocation must clear the persisted trust grant.');
      // (Restart-zero-prompts — the inverse of this revoke — is already covered
      // by dapp_trust_test.dart (b): a persisted grant yields ZERO prompts on a
      // fresh host. Not duplicated here.)
    } finally {
      // NEVER leak the process-wide override into other tests.
      await resetServiceLocator();
    }
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

/// Canned canister bridge for the bundled poll dapp.
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
/// `voterPrincipal` is mutable: the unified test sets it AFTER creating the real
/// Ed25519 profile mid-flow, so `whoami` returns the voter's real principal
/// (not a placeholder) — NO crypto is mocked.
///
/// The `jsApp*` lifecycle methods are unused: the host never invokes them on
/// `testBridge` — the REAL `ScriptAppRuntime` owns bundle execution via its own
/// `RustScriptBridge`. They return null only to satisfy the interface.
class _PollCannedBridge implements ScriptBridge {
  _PollCannedBridge({required this.voterPrincipal});

  /// Returned by `whoami` — the ACTUAL principal of the real signing keypair
  /// (so the dapp displays the voter's real identity, not a placeholder). Set
  /// by the test after the real profile is created mid-flow.
  String voterPrincipal;

  /// Count of authenticated `vote` UPDATE calls observed (asserted in the test).
  int authenticatedVoteCalls = 0;

  /// Flipped to true when an authenticated `vote` lands; subsequent getTally
  /// responses reflect the vote.
  bool _voted = false;

  @override
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) async {
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
  Future<String?> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) async {
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
