// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 3 (mock Secret Service / daps + wizard + shortcut split-off).
///
/// Boots the REAL app ONCE under the mock keyring
/// (`scripts/run-with-mock-keyring.sh`), drives the FULL first-run wizard
/// (creating a real profile + registering a real backend account), then
/// runs the dapp trust/copy-principal flows and the Ctrl+S save-profile
/// shortcut flow against the registered state.
///
/// These flows were split out of `suite_mock_keyring_test.dart` because
/// that suite's single `testWidgets` body was approaching the flutter_test
/// binding's stability threshold (the documented "Cannot close sink while
/// adding stream" crash past ~30 phases — same root cause as
/// `suite_keyring_less_test.dart` per OPEN_ISSUES E2E-PHASE56+57). The
/// profile/account/keypair/vault flows stay in the original suite; the
/// wizard + dapp + shortcut flows move here.
///
/// Run: `just e2e-desktop` (PASS 2b — wrapped in the mock Secret Service,
/// same as PASS 2). Also runnable standalone via
/// `just e2e-one first_run.create_profile_with_account mock-keyring-dapps`
/// (or any other flow id in this suite).
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'mock_keyring_dapp_helpers.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  const testProfileName = 'Dapp Suite Owner';

  final registry = FlowRegistry()
    // ── first_run.create_profile_with_account: drive the FULL wizard flow
    // (display name + username → Get Started → success → Start Exploring),
    // creating both a profile AND a backend account. Runs as PHASE 1 in this
    // suite (the wizard is on stage after PHASE 0's boot). Also doubles as
    // this suite's profile setup — the dapp/shortcut phases that follow
    // rely on the registered account this wizard call creates.
    ..register('first_run.create_profile_with_account', (tester, d) async {
      // The wizard must be on stage from PHASE 0.
      expect(d.present(find.byType(UnifiedSetupWizard), tester), isTrue,
          reason: 'PHASE 0 must have wiped state + booted, leaving the '
              'wizard on stage.');

      // Enter display name (find by hintText — the TextFormField wraps an
      // internal TextField that carries the InputDecoration at runtime).
      final displayNameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('How should we call you?') ??
              false));
      await tester.enterText(displayNameField, testProfileName);
      await tester.pump(const Duration(milliseconds: 300));

      // Enter a unique username (validation includes a real backend
      // availability check, so the value MUST be unique across runs).
      final uniqueUsername = 'wiz_${DateTime.now().millisecondsSinceEpoch}';
      final usernameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('Choose a username') ?? false));
      await tester.enterText(usernameField, uniqueUsername);
      await tester.pump(const Duration(milliseconds: 500));

      // Username validation is debounced (~500ms) + involves a real backend
      // round-trip (isUsernameAvailable). Wait for Get Started to become
      // clickable (the _canCreate getter returns true only when validation
      // passed).
      final buttonEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Get Started'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 15));
      expect(buttonEnabled, isTrue,
          reason: 'After entering a valid display name + unique username, '
              'Get Started must become enabled.');

      // Tap Get Started → _handleCreate (createProfile + registerAccount +
      // connectivity probe). Real FFI keygen + signed POST. Drive the
      // round-trip under runAsync so the network I/O completes.
      // NOTE: "Get Started" appears twice — as the AppBar title (size 24)
      // AND as the FilledButton label (size 16). Use widgetWithText to
      // disambiguate to the button.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // UX-H6: after registerAccount succeeds, the wizard shows a "Secure
      // your account" prompt (vault password / passkey enrollment). Dismiss
      // it (Skip) so the wizard can reach the Success screen. The vault +
      // passkey flows are exercised by their own dedicated e2e flows.
      await dismissPostRegistrationSecurityPrompt(tester, d);

      // The success screen renders with "Success!" header.
      final successShown = await d.waitUntil(
          tester, () => d.present(find.text('Success!'), tester),
          timeout: const Duration(seconds: 20));
      expect(successShown, isTrue,
          reason: 'The wizard must complete profile + account creation and '
              'show the success screen.');
      expect(d.present(find.textContaining('marketplace account'), tester),
          isTrue,
          reason: 'The success copy must mention the marketplace account was '
              'created (not the local-only path).');

      // Tap "Start Exploring" → pops the wizard with the result.
      await tester.tap(find.text('Start Exploring'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // The wizard must have popped + the main shell must render.
      final wizardClosed = await d.waitUntil(
          tester, () => !d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardClosed, isTrue,
          reason: 'Tapping Start Exploring must dismiss the wizard.');
      expect(d.present(find.byType(ScriptsScreen), tester), isTrue,
          reason: 'After the wizard completes, ScriptsScreen must render.');

      // Verify the profile + account actually persisted. Read via the
      // running app's ProfileScope (the wizard used the same controller).
      // Creating a standalone controller here would construct a fresh
      // ProfileRepository that may not see writes that haven't been
      // flushed yet.
      final profileController = ProfileScope.of(
          tester.element(find.byType(ScriptsScreen)),
          listen: false);
      final profile = profileController.activeProfile;
      expect(profile, isNotNull,
          reason: 'The wizard must have persisted an active profile.');
      expect(profile!.name, testProfileName,
          reason: 'The persisted profile name must match what we entered.');
      expect(profile.username, uniqueUsername,
          reason: 'The persisted profile username must match what we entered '
              '(the wizard calls updateProfileUsername after registerAccount).');
    })
    // ── dapps.copy_principal: open the ICP Ledger dapp (mainnet, no local
    // replica needed) → DappRunnerScreen mounts → the auth-status chip
    // "Signed as: <principal>" is tap-to-copy. Pre-trust the dapp via
    // DappTrustStore so the first canister call doesn't fire the trust
    // dialog. Tap the chip → assert the clipboard contains the principal.
    ..register('dapps.copy_principal', (tester, d) async {
      // Pre-trust (avoids the trust dialog firing above the runner).
      await tester.runAsync(() => DappTrustStore.setTrusted('icp_ledger'));
      await tester.pump(const Duration(milliseconds: 200));

      // Capture the expected principal BEFORE opening the runner.
      final profileController = newStandaloneController();
      final activeProfile = profileController.activeProfile;
      final expectedPrincipal = activeProfile?.primaryKeypair.principal ?? '';

      await navigateToDapps(tester, d);
      await tapLedgerCard(tester, d);
      final runnerOpen = await d.waitUntil(
          tester, () => d.present(find.byType(DappRunnerScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(runnerOpen, isTrue,
          reason: 'Tapping the ICP Ledger card must push DappRunnerScreen.');

      final chipVisible = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('Signed as:'), tester),
          timeout: const Duration(seconds: 10));
      expect(chipVisible, isTrue,
          reason: 'DappRunnerScreen must show the "Signed as: <principal>" '
              'auth-status chip when an active profile exists.');

      // Clear clipboard first so we can be sure the value we read came from
      // our tap (not a prior test phase).
      await tester.runAsync(() =>
          Clipboard.setData(const ClipboardData(text: '')));
      await tester.pump(const Duration(milliseconds: 200));

      // Tap the chip via its Tooltip 'Copy principal'.
      await tester.tap(find.byTooltip('Copy principal'));
      await tester.pump(const Duration(milliseconds: 400));
      final String? clipboardValue = await tester.runAsync<String?>(
          () => Clipboard.getData('text/plain').then((data) => data?.text));
      expect(clipboardValue, isNotNull,
          reason: 'Tapping the auth-status chip must write the principal to '
              'the clipboard.');
      expect(clipboardValue!.isNotEmpty, isTrue,
          reason: 'The clipboard value must not be empty.');
      if (expectedPrincipal.isNotEmpty) {
        expect(clipboardValue, expectedPrincipal,
            reason: 'The clipboard principal must match the active '
                'profile\'s primary keypair principal.');
      } else {
        expect(clipboardValue.contains('-'), isTrue,
            reason: 'IC principals are dash-separated; got "$clipboardValue".');
      }

      // Clear the trust grant for the next phase.
      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
      await closeDappRunner(tester, d);
    })
    // ── dapps.trust_grant: open the ICP Ledger dapp → DO NOT pre-trust →
    // the bundle's first canister call fires the "Trust this dapp?" dialog.
    // Tap "Trust this dapp" → assert the persistent "Trusted" status chip
    // shows + DappTrustStore.isTrusted returns true.
    ..register('dapps.trust_grant', (tester, d) async {
      // Defensive: ensure no stale trust grant from a prior run.
      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
      await tester.pump(const Duration(milliseconds: 200));

      // Remount to ensure we start at the root ScriptsScreen tab.
      await d.remount(tester);
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 10));

      await navigateToDapps(tester, d);
      await tapLedgerCard(tester, d);
      final runnerOpen = await d.waitUntil(
          tester, () => d.present(find.byType(DappRunnerScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(runnerOpen, isTrue,
          reason: 'Tapping the ICP Ledger card must push DappRunnerScreen.');

      final dialogShown = await d.waitUntil(
          tester, () => d.present(find.text('Trust this dapp?'), tester),
          timeout: const Duration(seconds: 20));
      expect(dialogShown, isTrue,
          reason: 'The bundle\'s first canister call must fire the per-dapp '
              '"Trust this dapp?" permission dialog.');

      // Tap "Trust this dapp" (the FilledButton with the allow-always label).
      await tester.runAsync(() async {
        await tester.tap(find.text('Trust this dapp'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));

      final trustedChipShown = await d.waitUntil(
          tester, () => d.present(find.text('Trusted'), tester),
          timeout: const Duration(seconds: 5));
      expect(trustedChipShown, isTrue,
          reason: 'Granting trust must surface the persistent "Trusted" '
              'status chip (the ValueListenableBuilder rebuilds on '
              '_trustState.value = true).');

      final persisted = await tester
          .runAsync<bool>(() => DappTrustStore.isTrusted('icp_ledger'));
      expect(persisted, isTrue,
          reason: 'The trust grant must persist via DappTrustStore.setTrusted.');

      // Clear so the next dapp flow starts clean.
      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
      await closeDappRunner(tester, d);
    })
    // ── dapps.manage_trust_revoke: pre-trust the dapp → open it (no dialog,
    // trust already granted) → tap the AppBar "Manage trust" IconButton →
    // confirm revoke → assert the Trusted status chip disappears.
    ..register('dapps.manage_trust_revoke', (tester, d) async {
      // PRE-trust so the trust dialog doesn't appear.
      await tester.runAsync(() => DappTrustStore.setTrusted('icp_ledger'));
      await tester.pump(const Duration(milliseconds: 200));

      await d.remount(tester);
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 10));

      await navigateToDapps(tester, d);
      await tapLedgerCard(tester, d);
      final runnerOpen = await d.waitUntil(
          tester, () => d.present(find.byType(DappRunnerScreen), tester),
          timeout: const Duration(seconds: 10));
      expect(runnerOpen, isTrue,
          reason: 'Tapping the ICP Ledger card must push DappRunnerScreen.');

      // The Trusted chip should appear once the host loads trust state.
      final trustedInitially = await d.waitUntil(
          tester, () => d.present(find.text('Trusted'), tester),
          timeout: const Duration(seconds: 10));
      expect(trustedInitially, isTrue,
          reason: 'A pre-trusted dapp must show the persistent Trusted chip '
              'once the host loads trust state.');

      // Tap the AppBar "Manage trust" IconButton (tooltip 'Manage trust').
      final manageBtn = find.byTooltip('Manage trust');
      expect(d.present(manageBtn, tester), isTrue,
          reason: 'DappRunnerScreen AppBar must show the Manage trust '
              'IconButton (UX-10).');
      await tester.tap(manageBtn);
      await tester.pump(const Duration(milliseconds: 500));

      final manageDialogShown = await d.waitUntil(
          tester,
          () => d.present(find.text('Manage dapp trust'), tester),
          timeout: const Duration(seconds: 5));
      expect(manageDialogShown, isTrue,
          reason: 'Tapping Manage trust must open the management dialog.');
      expect(d.present(find.textContaining('This dapp is trusted'), tester),
          isTrue,
          reason: 'The dialog body must reflect the trusted state.');
      expect(d.present(find.text('Revoke trust'), tester), isTrue,
          reason: 'The dialog must offer Revoke trust when trusted.');

      // Tap "Revoke trust" — triggers the explicit yes/no confirmation dialog.
      await tester.tap(find.text('Revoke trust'));
      await tester.pump(const Duration(milliseconds: 500));

      final confirmShown = await d.waitUntil(
          tester, () => d.present(find.text('Revoke trust?'), tester),
          timeout: const Duration(seconds: 5));
      expect(confirmShown, isTrue,
          reason: 'Revoke must show an explicit yes/no confirmation dialog.');
      // Confirm by tapping the Revoke FilledButton in the confirm dialog
      // (the topmost / last rendered of the two "Revoke trust" buttons).
      await tester.tap(find.text('Revoke trust').last);
      await tester.pump(const Duration(milliseconds: 500));

      // The Trusted chip must disappear.
      final chipHidden = await d.waitUntil(
          tester, () => !d.present(find.text('Trusted'), tester),
          timeout: const Duration(seconds: 5));
      expect(chipHidden, isTrue,
          reason: 'Revoking trust must hide the Trusted status chip.');

      final persisted = await tester
          .runAsync<bool>(() => DappTrustStore.isTrusted('icp_ledger'));
      expect(persisted, isFalse,
          reason: 'Revoking trust must clear DappTrustStore.');

      await closeDappRunner(tester, d);
    })
    // ── shortcut.account_save: open AccountProfileScreen (registered mode),
    // edit the Bio field, then send Ctrl+S — the desktop keyboard shortcut
    // wired by ScreenShortcuts (kShortcutSpecs['account_save'] → mod+S).
    // Asserts the shortcut fires _saveProfile and the success SnackBar
    // renders, proving the Ctrl+S binding reaches the same save path as the
    // Save Changes button (UX-9).
    ..register('shortcut.account_save', (tester, d) async {
      // Open profile menu → My Account → AccountProfileScreen.
      await d.remount(tester);
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 10));
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('My Account'));
      final pushed = await d.waitUntil(
          tester, () => d.present(find.byType(AccountProfileScreen), tester),
          timeout: const Duration(seconds: 5));
      expect(pushed, isTrue,
          reason: 'Tapping My Account must push AccountProfileScreen.');

      final saveVisible = await d.waitUntil(
          tester, () => d.present(find.text('Save Changes'), tester),
          timeout: const Duration(seconds: 10));
      expect(saveVisible, isTrue,
          reason: 'Registered-mode AccountProfileScreen must show the Save '
              'Changes button (the shortcut and the button share _saveProfile).');

      final bioField = tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
          (tf) => tf.decoration?.labelText == 'Bio',
          orElse: () => throw StateError(
              'Bio TextField not found in AccountProfileScreen.'));
      final uniqueBio =
          'E2E ctrl+s bio ${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byWidget(bioField), uniqueBio);
      await tester.pump(const Duration(milliseconds: 300));

      // Clear stale SnackBars.
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

      // Send Ctrl+S — ScreenShortcuts maps mod+S → _SaveIntent → _saveProfile.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 500));

      final successShown = await d.waitUntil(
          tester, () => d.present(find.text('Profile updated successfully'), tester),
          timeout: const Duration(seconds: 10));
      expect(successShown, isTrue,
          reason: 'Ctrl+S must fire _saveProfile (the same callback as the '
              'Save Changes button) and show the success SnackBar — proving '
              'the desktop keyboard shortcut is correctly bound to the save '
              'action.');

      await tester.pageBack();
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));
    });

  testWidgets(
      'e2e suite — mock keyring dapps + shortcut: trust/copy/save flows',
      (tester) async {
    // ── PHASE 0: clean slate + boot → wizard present ──────────────────────
    await resetAppState(tester: tester);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'Clean store under the mock keyring must show the wizard.');
    driver.phase('0', 'OK');

    // ── PHASE 1: first_run.create_profile_with_account ───────────────────
    // Drive the FULL wizard UI flow (display name + unique username → Get
    // Started → success → Start Exploring). This is BOTH the
    // first_run.create_profile_with_account flow AND the profile-setup
    // phase for this suite's subsequent dapp/shortcut flows — the wizard
    // creates a real profile + registers a real backend account, which is
    // exactly the precondition the dapp flows need.
    driver.phase('1', 'wizard: display name + username → account created');
    await registry.runFor('first_run.create_profile_with_account')!(tester, driver);
    if (shouldStopAfter('first_run.create_profile_with_account')) return;
    driver.phase('1', 'OK — first_run.create_profile_with_account');

    // Verify the profile is loaded (the wizard flow already asserted the
    // persisted state; here we just confirm the shell is interactive).
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a profile + registered account in the store, the '
            'remounted app loads it and skips the first-run gate.');
    driver.phase('1b', 'profile + account loaded — wizard popped');

    // ── PHASE 2: dapps.copy_principal ─────────────────────────────────────
    driver.phase('2', 'dapps: copy principal (auth-status chip → clipboard)');
    await registry.runFor('dapps.copy_principal')!(tester, driver);
    if (shouldStopAfter('dapps.copy_principal')) return;
    driver.phase('2', 'OK — dapps.copy_principal');

    // ── PHASE 3: dapps.trust_grant ────────────────────────────────────────
    driver.phase('3', 'dapps: grant trust (Trust dialog → Trusted chip)');
    await registry.runFor('dapps.trust_grant')!(tester, driver);
    if (shouldStopAfter('dapps.trust_grant')) return;
    driver.phase('3', 'OK — dapps.trust_grant');

    // ── PHASE 4: dapps.manage_trust_revoke ────────────────────────────────
    driver.phase('4', 'dapps: manage trust → revoke (chip disappears)');
    await registry.runFor('dapps.manage_trust_revoke')!(tester, driver);
    if (shouldStopAfter('dapps.manage_trust_revoke')) return;
    driver.phase('4', 'OK — dapps.manage_trust_revoke');

    // ── PHASE 5: shortcut.account_save ────────────────────────────────────
    driver.phase('5', 'shortcut: Ctrl+S save profile');
    await registry.runFor('shortcut.account_save')!(tester, driver);
    if (shouldStopAfter('shortcut.account_save')) return;
    driver.phase('5', 'OK — shortcut.account_save');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(5),
        reason: 'mock-keyring-dapps must cover at least 5 flows.');

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING_DAPS: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
