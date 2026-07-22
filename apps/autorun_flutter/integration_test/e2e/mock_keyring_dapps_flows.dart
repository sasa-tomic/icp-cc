// ignore_for_file: lines_longer_than_80_chars

/// Flow registry for the mock-keyring dapps + shortcut e2e suite.
///
/// Extracted from `suite_mock_keyring_dapps_test.dart` so the same flow
/// implementations can be driven either:
///   - chained in one shared-boot `testWidgets` (the monolith suite, used by
///     `just e2e-desktop` PASS 2b), or
///   - one-per-`testWidgets` in `flows_mock_keyring_dapps_test.dart` (used by
///     `just e2e-one <flow-id> mock-keyring-dapps` for fast <20s iteration).
///
/// The flows are self-contained `(tester, driver) → Future<void>` closures.
/// Each closure assumes a specific app state (documented inline); see the
/// `_prereqs` map in `flows_mock_keyring_dapps_test.dart` for the dependency
/// chains used by the per-flow runner.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'mock_keyring_dapp_helpers.dart';
import 'suite_helpers.dart';

/// Profile name used by the wizard flow in this suite.
const kDappsProfileName = 'Dapp Suite Owner';

/// Build the FlowRegistry for the mock-keyring dapps + shortcut suite.
///
/// Re-constructed on each call so closures capture fresh state (no shared
/// mutable singletons across suites).
FlowRegistry buildMockKeyringDappsRegistry() {
  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  return FlowRegistry()
    // ── first_run.create_profile_with_account: drive the FULL wizard flow
    // (display name + username → Get Started → success → Start Exploring),
    // creating both a profile AND a backend account. Self-contained: assumes
    // the wizard is on stage (caller did `resetAppState + boot` and has NOT
    // dismissed the wizard).
    ..register('first_run.create_profile_with_account', (tester, d) async {
      expect(d.present(find.byType(UnifiedSetupWizard), tester), isTrue,
          reason: 'Wizard must be on stage for this flow.');

      final displayNameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('How should we call you?') ??
              false));
      // Wait for the wizard's text fields to render (cold-compile races
      // can leave the wizard widget present but its children not yet laid out).
      await d.waitUntil(tester, () => d.present(displayNameField, tester),
          timeout: const Duration(seconds: 5));
      await tester.enterText(displayNameField, kDappsProfileName);
      await tester.pump(const Duration(milliseconds: 300));

      final uniqueUsername = 'wiz_${DateTime.now().millisecondsSinceEpoch}';
      final usernameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('Choose a username') ?? false));
      await tester.enterText(usernameField, uniqueUsername);
      await tester.pump(const Duration(milliseconds: 500));

      final buttonEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Get Started'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 15));
      expect(buttonEnabled, isTrue,
          reason: 'Get Started must become enabled after valid input.');

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump(const Duration(milliseconds: 500));

      await dismissPostRegistrationSecurityPrompt(tester, d);

      final successShown = await d.waitUntil(
          tester, () => d.present(find.text('Success!'), tester),
          timeout: const Duration(seconds: 20));
      expect(successShown, isTrue,
          reason: 'The wizard must complete and show the success screen.');
      expect(d.present(find.textContaining('marketplace account'), tester),
          isTrue,
          reason: 'The success copy must mention the marketplace account.');

      await tester.tap(find.text('Start Exploring'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      final wizardClosed = await d.waitUntil(
          tester, () => !d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardClosed, isTrue,
          reason: 'Tapping Start Exploring must dismiss the wizard.');
      expect(d.present(find.byType(ScriptsScreen), tester), isTrue,
          reason: 'After the wizard completes, ScriptsScreen must render.');

      final profileController = ProfileScope.of(
          tester.element(find.byType(ScriptsScreen)),
          listen: false);
      final profile = profileController.activeProfile;
      expect(profile, isNotNull,
          reason: 'The wizard must have persisted an active profile.');
      expect(profile!.name, kDappsProfileName,
          reason: 'The persisted profile name must match what we entered.');
      expect(profile.username, uniqueUsername,
          reason: 'The persisted profile username must match what we entered.');
    })
    // ── dapps.copy_principal: open the ICP Ledger dapp → DappRunnerScreen →
    // tap the auth-status chip → assert the clipboard contains the principal.
    // Assumes the app is at ScriptsScreen with a registered profile.
    ..register('dapps.copy_principal', (tester, d) async {
      await tester.runAsync(() => DappTrustStore.setTrusted('icp_ledger'));
      await tester.pump(const Duration(milliseconds: 200));

      final profileController = newStandaloneController();
      final activeProfile = profileController.activeProfile;
      final expectedPrincipal =
          activeProfile?.primaryKeypair.principal ?? '';

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

      await tester.runAsync(() =>
          Clipboard.setData(const ClipboardData(text: '')));
      await tester.pump(const Duration(milliseconds: 200));

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
            reason: 'IC principals are dash-separated.');
      }

      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
      await closeDappRunner(tester, d);
    })
    // ── dapps.trust_grant: open the ICP Ledger dapp → DO NOT pre-trust → the
    // bundle's first canister call fires the "Trust this dapp?" dialog.
    // Assumes the app is at ScriptsScreen with a registered profile.
    ..register('dapps.trust_grant', (tester, d) async {
      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
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

      final dialogShown = await d.waitUntil(
          tester, () => d.present(find.text('Trust this dapp?'), tester),
          timeout: const Duration(seconds: 20));
      expect(dialogShown, isTrue,
          reason: 'The first canister call must fire the trust dialog.');

      await tester.runAsync(() async {
        await tester.tap(find.text('Trust this dapp'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));

      final trustedChipShown = await d.waitUntil(
          tester, () => d.present(find.text('Trusted'), tester),
          timeout: const Duration(seconds: 5));
      expect(trustedChipShown, isTrue,
          reason: 'Granting trust must surface the "Trusted" status chip.');

      final persisted = await tester
          .runAsync<bool>(() => DappTrustStore.isTrusted('icp_ledger'));
      expect(persisted, isTrue,
          reason: 'The trust grant must persist via DappTrustStore.');

      await tester.runAsync(() => DappTrustStore.clear('icp_ledger'));
      await closeDappRunner(tester, d);
    })
    // ── dapps.manage_trust_revoke: pre-trust → open → manage trust → revoke.
    // Assumes the app is at ScriptsScreen with a registered profile.
    ..register('dapps.manage_trust_revoke', (tester, d) async {
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
      expect(runnerOpen, isTrue);

      final trustedInitially = await d.waitUntil(
          tester, () => d.present(find.text('Trusted'), tester),
          timeout: const Duration(seconds: 10));
      expect(trustedInitially, isTrue,
          reason: 'A pre-trusted dapp must show the Trusted chip.');

      final manageBtn = find.byTooltip('Manage trust');
      expect(d.present(manageBtn, tester), isTrue,
          reason: 'DappRunnerScreen AppBar must show the Manage trust button.');
      await tester.tap(manageBtn);
      await tester.pump(const Duration(milliseconds: 500));

      final manageDialogShown = await d.waitUntil(
          tester,
          () => d.present(find.text('Manage dapp trust'), tester),
          timeout: const Duration(seconds: 5));
      expect(manageDialogShown, isTrue,
          reason: 'Tapping Manage trust must open the management dialog.');
      expect(d.present(find.textContaining('This dapp is trusted'), tester),
          isTrue);
      expect(d.present(find.text('Revoke trust'), tester), isTrue);

      await tester.tap(find.text('Revoke trust'));
      await tester.pump(const Duration(milliseconds: 500));

      final confirmShown = await d.waitUntil(
          tester, () => d.present(find.text('Revoke trust?'), tester),
          timeout: const Duration(seconds: 5));
      expect(confirmShown, isTrue,
          reason: 'Revoke must show an explicit yes/no confirmation dialog.');
      await tester.tap(find.text('Revoke trust').last);
      await tester.pump(const Duration(milliseconds: 500));

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
    // edit Bio, send Ctrl+S → assert success SnackBar.
    // Assumes the app is at ScriptsScreen with a registered profile.
    ..register('shortcut.account_save', (tester, d) async {
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
          reason: 'Registered-mode AccountProfileScreen must show Save Changes.');

      final bioField = tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
          (tf) => tf.decoration?.labelText == 'Bio',
          orElse: () => throw StateError(
              'Bio TextField not found in AccountProfileScreen.'));
      final uniqueBio =
          'E2E ctrl+s bio ${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byWidget(bioField), uniqueBio);
      await tester.pump(const Duration(milliseconds: 300));

      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 500));

      final successShown = await d.waitUntil(
          tester,
          () =>
              d.present(find.text('Profile updated successfully'), tester),
          timeout: const Duration(seconds: 10));
      expect(successShown, isTrue,
          reason: 'Ctrl+S must fire _saveProfile and show the success '
              'SnackBar — proving the desktop keyboard shortcut is correctly '
              'bound to the save action.');

      await tester.pageBack();
      await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));
    });
}
