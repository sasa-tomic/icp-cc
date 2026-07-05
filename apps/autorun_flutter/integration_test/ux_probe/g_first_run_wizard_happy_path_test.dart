// ignore_for_file: lines_longer_than_80_chars

// Flow G — First-run wizard HAPPY-PATH end-to-end through a real app boot.
//
// This closes the test gap between the two existing wizards probes:
//   - a_first_run_test.dart A3 (round-2, EXCLUDED from the recipe) drove the
//     form on a KEYRING-LESS box and asserted the libsecret ERROR (NEW-2). It
//     is stale post-WU-S2 (the readiness panel now blocks before the form).
//   - r3_addendum_test.dart Addendum-A creates profiles PROGRAMMATICALLY via
//     `ProfileController.createProfile` — it never touches the wizard UI form.
// The untested bridge is the happy path: type a name in the wizard form →
// tap "Get Started" → the profile is actually created (real Ed25519 via FFI,
// real libsecret round-trip) AND the main shell becomes reachable.
//
// This probe runs under the MOCK Secret Service so `SecureStorageReadiness`
// returns `StorageReady` (the happy path). It reuses the round-3 harness
// (`r3_helpers.dart`) exactly as the PASS 2 sibling `f_dapp_vote_flow_test`
// does — same Xvfb surface, same real `app.main()` boot, same bounded-pump
// discipline. NO crypto / FFI / libsecret is mocked: the only seam is the mock
// Secret Service itself (dev infra, sanctioned in AGENTS.md).
//
// Run (mock keyring required — `SecureStorageReadiness` must reach StorageReady):
//   DISPLAY=:99 LD_LIBRARY_PATH=/code/icp-cc/target/release \
//     scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/g_first_run_wizard_happy_path_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

import 'r3_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // The wizard happy-path, driven through the REAL UI form on a real app boot.
  //
  // Flow as it exists today (post-WU-S2):
  //   1. app.main() boots MainHome; its postFrame _checkAndShowOnboarding finds
  //      no profile and pushes UnifiedSetupWizard (fullscreenDialog route).
  //   2. The wizard's initState kicks _runReadinessCheck() (the WU-S2 gate) →
  //      renders "Checking secure storage…" while SecureStorageReadiness.check()
  //      runs. Under the mock it returns StorageReady → the setup FORM renders:
  //      AppBar "Get Started", heading "Create Your Profile", a display-name
  //      TextFormField (hint "How should we call you?"), an optional username
  //      field, and a FilledButton "Get Started".
  //   3. Typing a name enables the button; tapping it runs the real
  //      createProfile (Ed25519 FFI gen + libsecret write + profiles.json write)
  //      → the "Success!" screen renders with a "Start Exploring" button.
  //   4. Tapping "Start Exploring" pops the route → MainHome's bottom nav
  //      (Scripts / Canisters / Dapps) is now reachable.
  // ===========================================================================
  testWidgets(
      'G: wizard form submit creates a REAL profile + reaches the main shell '
      'and survives a reload (mock keyring, real FFI + libsecret)',
      (tester) async {
    // --- Fresh start: wipe on-disk profile state AND the mock's secrets.json --
    // `clearProfileStateR3` resets profiles.json to the empty list so the
    // first-run gate fires on boot. We ALSO clear secure storage via the real
    // repo so the mock keyring's secrets.json is empty (mirrors r3_addendum's
    // belt-and-suspenders reset). Both are real, production code paths.
    await clearProfileStateR3();
    final repo = ProfileRepository();
    await tester.runAsync(() => repo.deleteAllSecureData());
    await tester.pump();

    // --- Real app boot --------------------------------------------------------
    await launchAppR3(tester);

    // --- Wait for the readiness check to finish + the FORM to render ---------
    // Under the mock the gate resolves to StorageReady quickly; bounded-pump
    // for the form's display-name hint (only rendered once the form is shown).
    bool formShown = false;
    for (int i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (presentR3(find.text('How should we call you?'), tester)) {
        formShown = true;
        break;
      }
    }
    expect(formShown, isTrue,
        reason: 'WU-S2 happy path: under the mock keyring the readiness gate '
            'must resolve to StorageReady and render the wizard form (not the '
            '"Setup needed" panel). If this fails, the mock Secret Service is '
            'not running — run under scripts/run-with-mock-keyring.sh.');

    // --- Wizard form is on screen: assert the decisive form elements ---------
    expect(presentR3(find.text('Create Your Profile'), tester), isTrue,
        reason: 'Wizard heading present.');
    expect(presentR3(find.text('How should we call you?'), tester), isTrue,
        reason: 'Display-name field hint present.');
    // The submit button is the FilledButton labelled 'Get Started'. (The AppBar
    // title is a Text, not a FilledButton, so this is unambiguous — same
    // technique as a_first_run_test A3.)
    final submit = find.widgetWithText(FilledButton, 'Get Started');
    expect(presentR3(submit, tester), isTrue,
        reason: 'Wizard submit button present.');

    // --- Drive the form: type a profile name + tap submit --------------------
    const displayName = 'Wizard Happy';
    await tester.enterText(find.byType(TextFormField).first, displayName);
    await tester.pump();
    // Submit is now enabled (non-null onPressed) because the name is non-empty.
    final submitEnabled =
        tester.widget<FilledButton>(submit).onPressed != null;
    expect(submitEnabled, isTrue,
        reason: 'Get Started must be enabled once a display name is typed.');

    await tester.ensureVisible(submit);
    await tester.tap(submit);

    // --- Wait for the SUCCESS screen (real createProfile just completed) -----
    // createProfile = FFI keypair gen + libsecret write of private key +
    // mnemonic + profiles.json. Bounded-pump for the success heading OR the
    // error banner (honest: if the keyring is down between probe and create,
    // the friendly humanized banner shows — we assert that does NOT happen).
    bool sawSuccess = false;
    bool sawError = false;
    for (int i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (presentR3(find.text('Success!'), tester)) {
        sawSuccess = true;
        break;
      }
      if (presentR3(find.byIcon(Icons.error_outline), tester)) {
        sawError = true;
        break;
      }
    }
    await shotR3(IntegrationTestWidgetsFlutterBinding.instance,
        'g_wizard_success_screen', tester);
    expect(sawSuccess, isTrue,
        reason: 'Wizard happy path: a real profile must be created under the '
            'mock keyring → the Success screen renders.');
    expect(sawError, isFalse,
        reason: 'No secure-storage error on the happy path (the readiness gate '
            'already proved StorageReady; createProfile must succeed).');

    // --- Dismiss the success screen → wizard route pops → main shell ---------
    final startExploring = find.widgetWithText(FilledButton, 'Start Exploring');
    expect(presentR3(startExploring, tester), isTrue,
        reason: 'Success screen offers the "Start Exploring" exit button.');
    await tester.ensureVisible(startExploring);
    await tester.tap(startExploring);

    // Bounded-pump until the main shell's bottom nav is visible. (pumpAndSettle
    // never returns once the Scripts screen mounts — it kicks off marketplace
    // fetches against the unreachable prod URL; same constraint as every other
    // ux_probe that reaches the main shell.)
    bool mainShell = false;
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (presentR3(find.text('Dapps'), tester) &&
          presentR3(find.text('Scripts'), tester) &&
          presentR3(find.text('Canisters'), tester)) {
        mainShell = true;
        break;
      }
    }
    await shotR3(IntegrationTestWidgetsFlutterBinding.instance,
        'g_wizard_main_shell_reached', tester);
    expect(mainShell, isTrue,
        reason: 'The wizard route must be dismissed and the main shell '
            '(Scripts / Canisters / Dapps bottom nav) reachable.');
    // The wizard is GONE: its heading + display-name hint are no longer painted.
    expect(presentR3(find.text('Create Your Profile'), tester), isFalse,
        reason: 'Wizard heading must disappear once the gate is dismissed.');
    expect(presentR3(find.text('How should we call you?'), tester), isFalse,
        reason: 'Wizard form must be gone once the user reaches the shell.');

    // --- The RUNNING app's controller actually has the created profile -------
    // Grab the live ProfileController from the tree (same technique as
    // f_dapp_vote_flow_test). This is the controller the wizard just mutated.
    final BuildContext scopeContext = tester.element(find.byType(ScriptsScreen));
    // Grabbing the running app's controller from the live tree after prior
    // async pumps is intentional and safe here (no navigation across the gap) —
    // same technique + justification as f_dapp_vote_flow_test.
    final ProfileController running = ProfileScope.of(
      // ignore: use_build_context_synchronously
      scopeContext,
      listen: false,
    );
    expect(running.profiles.length, 1,
        reason: 'Exactly one profile must exist after wizard submit.');
    final Profile created = running.profiles.single;
    expect(created.name, displayName,
        reason: 'The created profile name must match the form input.');
    expect(running.activeProfileId, created.id,
        reason: 'The wizard sets the new profile as active.');
    expect(created.keypairs.length, 1,
        reason: 'The wizard creates exactly one initial keypair.');
    final keypair = created.keypairs.single;
    expect(keypair.algorithm, KeyAlgorithm.ed25519,
        reason: 'The wizard keypair is Ed25519 (real FFI gen).');
    expect(keypair.principal, isNotEmpty,
        reason: 'The keypair has a real principal (FFI-derived).');

    // --- RELOAD-SURVIVAL: a fresh controller reads profiles.json + libsecret --
    // Mirrors r3_addendum Addendum-A's persistence check, but the profile was
    // created through the UI this time. Proves the data survived to disk +
    // libsecret (the exact data loss NEW-2 guarded against).
    final reloaded = ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => reloaded.ensureLoaded());
    await tester.pump();
    expect(reloaded.profiles.length, 1,
        reason: 'loadProfiles() must reload the wizard-created profile.');
    final reloadedProfile = reloaded.profiles.single;
    expect(reloadedProfile.id, created.id,
        reason: 'Reloaded profile id matches the in-memory one.');
    expect(reloadedProfile.name, displayName,
        reason: 'Reloaded profile name matches.');
    expect(reloadedProfile.keypairs.single.principal, keypair.principal,
        reason: 'Reloaded keypair principal matches (same key).');

    // The private key + mnemonic must round-trip through libsecret under the
    // mock (real secure storage — NOT mocked).
    final keypairId = reloadedProfile.keypairs.single.id;
    String? reloadedPk;
    String? reloadedMn;
    await tester.runAsync(() async {
      reloadedPk = await ProfileRepository().getPrivateKey(keypairId);
      reloadedMn = await ProfileRepository().getMnemonic(keypairId);
    });
    // ignore: avoid_print
    print('G_PERSIST: pk=${reloadedPk == null ? "NULL(LOST)" : "present(${reloadedPk!.length})"} '
        'mnemonic=${reloadedMn == null ? "NULL(LOST)" : "present(${reloadedMn!.length})"} '
        'principal=${keypair.principal}');
    expect(reloadedPk, isNotNull,
        reason: 'Private key must survive a reload (libsecret read path under '
            'the mock keyring).');
    expect(reloadedMn, isNotNull,
        reason: 'Mnemonic must survive a reload (libsecret read path).');
    // ignore: avoid_print
    print('G: PASS — wizard form created a real Ed25519 profile end-to-end, '
        'reached the main shell, and survived a controller reload.');
  });

  // -------------------------------------------------------------------------
  // Negative nuance (empty-name rejected inline): DELIBERATELY NOT duplicated.
  // The wizard form disables the submit FilledButton when the display name is
  // empty (see `_canCreate` in unified_setup_wizard.dart), and that disabled-
  // button behavior is already asserted at
  //   test/screens/unified_setup_wizard_test.dart
  //     → 'create button is disabled when display name is empty'
  // Because the button is disabled there is no reachable inline validation
  // message to drive through the UI. Asserting it again here would duplicate
  // existing widget-test coverage (violates the "no overlap" test rule).
  // -------------------------------------------------------------------------
}
