// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 2c (mock Secret Service / identity + scripts publish flows).
///
/// Boots the REAL app ONCE under the mock keyring
/// (`scripts/run-with-mock-keyring.sh`), then runs three flows that each
/// need a Secret Service for keypair generation + signing:
///
///   PHASE 1 — `account.register_from_publish` (group D account)
///     A LOCAL-ONLY profile tries to publish → "Register Username" prompt
///     → AccountRegistrationWizard → real `registerAccount` round-trip.
///
///   PHASE 2 — `scripts.publish` (group E scripts)
///     Now that the profile has a registered account, create a local script
///     → invoke `LocalScriptRowMenu.onPublish` → fill QuickUploadDialog →
///     real signed `uploadScript` round-trip → success SnackBar.
///
///   PHASE 3 — `profile.create_via_menu_dialog` (group B profile)
///     The Phase-O UX-PMD-1 fix flow: open profile menu → "Switch Profile"
///     → manage sheet → "Create New Profile" → UnifiedSetupWizard pushes
///     (the post-fix navigator capture path) → fill display name + username
///     → real `createProfile` + `registerAccount` round-trip → success.
///
/// These three flows live in a dedicated 3-phase mini-suite (mirroring the
/// Phase N `suite_mock_keyring_dapps_test.dart` split pattern) so the
/// existing keyring-less + mock-keyring suites stay below the documented
/// flutter_test binding stability threshold (see OPEN_ISSUES
/// E2E-PHASE56+57). State evolves naturally: local-only → registered →
/// second profile, so no resetAppState between phases.
///
/// Run: `just e2e-desktop` (PASS 2c — wrapped in the mock Secret Service,
/// same as PASS 2). Also runnable standalone via
/// `just e2e-one <flow-id> mock-keyring-identity` for any of the three
/// flow ids above.
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_registration_wizard.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/widgets/script_row_menus.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  ProfileController newStandaloneController() =>
      ProfileController(profileRepository: ProfileRepository());

  const firstProfileName = 'Identity Suite Owner';

  final registry = FlowRegistry()
    // ── account.register_from_publish: from a LOCAL-ONLY profile, attempt
    // to publish → the marketplace-publish gate fires the "Share to
    // Marketplace" prompt → "Register Username" → AccountRegistrationWizard
    // pushes → fill username + display name → real registerAccount →
    // wizard pops with the Account. We then CANCEL the subsequent
    // QuickUploadDialog: the flow's contract is "registration round-trip
    // reachable + succeeds from the publish prompt", not "publishes the
    // script" (that's PHASE 2 below against a registered profile).
    ..register('account.register_from_publish', (tester, d) async {
      // Create a local script first (so we have a row to publish from).
      // The profile from PHASE 0 is local-only — perfect for this flow.
      await createLocalScript(tester, d, title: 'Register From Publish');

      // Find the LocalScriptRowMenu for the just-created script and invoke
      // onPublish directly. The popup-menu's gesture interception is
      // unreliable in the headless binding (documented across the existing
      // suite_keyring_less + suite_mock_keyring tests).
      final menu = findLocalScriptMenu(tester, title: 'Register From Publish');
      // Clear any stale SnackBars (the "Script created" SnackBar with its
      // Publish action would absorb the next tap).
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

      // Invoke onPublish. This synchronously enters _publishToMarketplace,
      // which detects no username and shows the registration prompt dialog.
      await tester.runAsync(() async {
        menu.onPublish();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));

      final promptShown = await d.waitUntil(
          tester,
          () => d.present(find.text('Share to Marketplace'), tester),
          timeout: const Duration(seconds: 5));
      expect(promptShown, isTrue,
          reason: 'A local-only profile attempting to publish must surface '
              'the "Share to Marketplace" registration prompt.');

      // Tap "Register Username" → AccountRegistrationWizard pushes.
      await tester.tap(find.text('Register Username'));
      final wizardPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(AccountRegistrationWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardPushed, isTrue,
          reason: 'Tapping Register Username must push the wizard.');

      // Fill username + display name. Username needs to be unique (real
      // backend availability check). Display Name is required by
      // `_canRegister` so we set it FIRST.
      final displayNameField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Display Name *');
      if (d.present(displayNameField, tester)) {
        await tester.enterText(displayNameField, firstProfileName);
        await tester.pump(const Duration(milliseconds: 300));
      }

      final uniqueUsername =
          'p${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.labelText == 'Username'),
          uniqueUsername);
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for username validation (debounced ~500ms + real backend round-trip).
      final registerEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Register'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 20));
      expect(registerEnabled, isTrue,
          reason: 'After entering a valid display name + unique username, '
              'Register must become enabled.');
      // Tap Register → real registerAccount round-trip. Drive under
      // runAsync so the FFI signing + HTTP complete.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Register'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // The wizard pops with the Account on success. The publish gate
      // then pushes QuickUploadDialog as the next step. Bail out by
      // cancelling the QuickUploadDialog (the publish flow's contract
      // ends at successful registration — the upload itself is PHASE 2).
      final wizardClosed = await d.waitUntil(
          tester,
          () => !d.present(find.byType(AccountRegistrationWizard), tester),
          timeout: const Duration(seconds: 20));
      expect(wizardClosed, isTrue,
          reason: 'The AccountRegistrationWizard must pop after the '
              'registerAccount round-trip succeeds.');

      // The publish flow continues into QuickUploadDialog. Verify it
      // opened (proves the wizard returned an Account, not null) then
      // cancel via Esc so the next phase starts clean.
      final uploadDialogShown = await d.waitUntil(
          tester,
          () => d.present(find.byType(QuickUploadDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(uploadDialogShown, isTrue,
          reason: 'After registration the publish flow must proceed into '
              'QuickUploadDialog (proves the wizard returned an Account).');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 500));

      // Verify the running app's ProfileScope sees the registered username.
      final profileController = ProfileScope.of(
          tester.element(find.byType(ScriptsScreen)),
          listen: false);
      final profile = profileController.activeProfile;
      expect(profile, isNotNull,
          reason: 'A profile must remain active after registration.');
      expect(profile!.username, uniqueUsername,
          reason: 'The active profile username must match the one just '
              'registered through the publish prompt.');
    })
    // ── scripts.publish: now that the profile has a registered account,
    // create a fresh local script → publish via QuickUploadDialog → real
    // signed uploadScript round-trip → success SnackBar. The signed upload
    // is already covered by Rust `marketplace_http_tests`; this flow
    // asserts the success state end-to-end through the UI.
    ..register('scripts.publish', (tester, d) async {
      await createLocalScript(tester, d, title: 'Publish Me');

      final menu = findLocalScriptMenu(tester, title: 'Publish Me');
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

      // Invoke onPublish. Profile has a registered username (from PHASE 1),
      // so the publish gate skips the registration prompt and pushes
      // QuickUploadDialog directly.
      await tester.runAsync(() async {
        menu.onPublish();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));

      final dialogShown = await d.waitUntil(
          tester,
          () => d.present(find.byType(QuickUploadDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(dialogShown, isTrue,
          reason: 'A registered profile invoking publish must push '
              'QuickUploadDialog directly (no registration prompt).');

      // Fill the form. Title is auto-derived from the script record; we
      // overwrite to a unique value so we can later assert it via the
      // marketplace browse API.
      final uniqueTitle = 'Pub_${DateTime.now().millisecondsSinceEpoch}';
      final titleField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Title *');
      await tester.enterText(titleField, '');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(titleField, uniqueTitle);
      await tester.pump(const Duration(milliseconds: 300));

      final descField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Description *');
      await tester.enterText(descField, 'E2E published script');
      await tester.pump(const Duration(milliseconds: 300));

      final tagsField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.labelText == 'Tags (comma-separated)');
      await tester.enterText(tagsField, 'e2e, smoke');
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the primary action (key=quick-upload-submit). Default label is
      // "Upload to Marketplace"; switches to "Uploading N%" during the
      // round-trip. The upload is async (sign + HTTP); drive under runAsync.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('quick-upload-submit')));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // The dialog pops + a success SnackBar renders (either from the
      // dialog's _uploadScript or from _publishToMarketplace's callback).
      final dialogClosed = await d.waitUntil(
          tester,
          () => !d.present(find.byType(QuickUploadDialog), tester),
          timeout: const Duration(seconds: 20));
      expect(dialogClosed, isTrue,
          reason: 'QuickUploadDialog must close after a successful upload.');

      final successShown = await d.waitUntil(
          tester,
          () => d.present(find.textContaining('published successfully'), tester),
          timeout: const Duration(seconds: 5));
      expect(successShown, isTrue,
          reason: 'A success SnackBar ("Script published successfully!") '
              'must confirm the signed upload round-trip.');

      // Cleanup: dismiss the SnackBar so it doesn't linger into PHASE 3.
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();
      await tester.pump(const Duration(milliseconds: 300));
    })
    // ── profile.create_via_menu_dialog: the UX-PMD-1 regression flow.
    // Open profile menu → "Switch Profile" → manage sheet → "Create New
    // Profile" → UnifiedSetupWizard pushes via the post-fix navigator
    // capture path → fill display name + username → Get Started → real
    // createProfile + registerAccount → Start Exploring. Asserts the new
    // profile is present in the running app's ProfileScope.
    ..register('profile.create_via_menu_dialog', (tester, d) async {
      // Open profile menu (top-left ProfileAvatarButton).
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap "Switch Profile" → manage sheet opens (single-profile case
      // routes here too; the sheet offers create/rename/delete).
      await tester.tap(find.text('Switch Profile'));
      final sheetOpen = await d.waitUntil(
          tester,
          () => d.present(find.text('Create New Profile'), tester),
          timeout: const Duration(seconds: 5));
      expect(sheetOpen, isTrue,
          reason: 'Tapping Switch Profile must open the manage sheet with '
              'the "Create New Profile" tile.');

      // Pump past the menu's exit animation so the original
      // _ProfileMenuWidgetState is definitely disposed (the UX-PMD-1
      // repro path). 1s > ~250ms default Material sheet transition.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));

      // Tap "Create New Profile" → onCreateProfile closure fires:
      // navigator.pop() (the manage sheet) + pushCreateProfileWizard.
      // Before the UX-PMD-1 fix this threw "State no longer has a context".
      await tester.tap(find.text('Create New Profile'));
      final wizardPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardPushed, isTrue,
          reason: 'The UnifiedSetupWizard must push from the manage sheet '
              'without throwing use-after-dispose (UX-PMD-1).');

      // Drive the full wizard UI: display name + username → Get Started →
      // real createProfile + registerAccount → success.
      final uniqueUsername =
          'm${DateTime.now().millisecondsSinceEpoch}';
      final displayNameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('How should we call you?') ??
              false));
      await tester.enterText(displayNameField, 'Menu Created Profile');
      await tester.pump(const Duration(milliseconds: 300));

      final usernameField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('Choose a username') ?? false));
      await tester.enterText(usernameField, uniqueUsername);
      await tester.pump(const Duration(milliseconds: 500));

      // Username validation is debounced + has a real backend round-trip.
      final getStartedEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Get Started'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 15));
      expect(getStartedEnabled, isTrue,
          reason: 'After entering a valid display name + unique username, '
              'Get Started must become enabled.');

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // UX-H6: after registerAccount succeeds, the wizard shows a "Secure
      // your account" prompt. Dismiss it (Skip) so the wizard reaches the
      // Success screen.
      await dismissPostRegistrationSecurityPrompt(tester, d);

      final successShown = await d.waitUntil(
          tester, () => d.present(find.text('Success!'), tester),
          timeout: const Duration(seconds: 20));
      expect(successShown, isTrue,
          reason: 'The wizard must complete profile + account creation and '
              'show the success screen.');

      // Tap "Start Exploring" → wizard pops with the result.
      await tester.tap(find.text('Start Exploring'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      final wizardClosed = await d.waitUntil(
          tester,
          () => !d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardClosed, isTrue,
          reason: 'Tapping Start Exploring must dismiss the wizard.');

      // Verify the new profile exists in the running app's ProfileScope.
      // The wizard used the same controller as the app shell, so writes
      // are visible without a remount.
      final profileController = ProfileScope.of(
          tester.element(find.byType(ScriptsScreen)),
          listen: false);
      final matchingProfile = profileController.profiles.firstWhere(
          (p) => p.username == uniqueUsername,
          orElse: () => throw StateError(
              'Newly-created profile $uniqueUsername not found in '
              '${profileController.profiles.map((p) => p.username)}.'));
      expect(matchingProfile.name, 'Menu Created Profile',
          reason: 'The new profile name must match what was entered.');
    });

  // ── Shared helpers (top-level functions below main) ───────────────────

  testWidgets(
      'e2e suite — mock keyring identity: register_from_publish + publish + '
      'create_via_menu_dialog', (tester) async {
    // ── PHASE 0: clean slate + boot + create first LOCAL-ONLY profile ──
    await resetAppState(tester: tester);
    await driver.boot(tester);
    driver.phase('0', 'booted — creating local-only profile via controller');

    // Pre-create a LOCAL-ONLY profile (no username) so PHASE 1 hits the
    // "no account → register prompt" branch of _publishToMarketplace.
    // Using the controller directly keeps PHASE 0 fast; the wizard UI is
    // exercised end-to-end in PHASE 3 below.
    final setupController = newStandaloneController();
    await tester.runAsync(() => setupController.createProfile(
          profileName: firstProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await driver.remount(tester);
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'With a local-only profile in the store, the remounted app '
            'loads it and skips the first-run gate.');
    driver.phase('0', 'OK — local-only profile loaded');

    // ── PHASE 1: account.register_from_publish ───────────────────────────
    driver.phase('1', 'account: register from publish prompt');
    await registry.runFor('account.register_from_publish')!(tester, driver);
    if (shouldStopAfter('account.register_from_publish')) return;
    driver.phase('1', 'OK — account.register_from_publish');

    // ── PHASE 2: scripts.publish ──────────────────────────────────────────
    driver.phase('2', 'scripts: publish via QuickUploadDialog');
    await registry.runFor('scripts.publish')!(tester, driver);
    if (shouldStopAfter('scripts.publish')) return;
    driver.phase('2', 'OK — scripts.publish');

    // ── PHASE 3: profile.create_via_menu_dialog ──────────────────────────
    driver.phase('3', 'profile: create via manage-sheet dialog (UX-PMD-1)');
    await registry.runFor('profile.create_via_menu_dialog')!(tester, driver);
    if (shouldStopAfter('profile.create_via_menu_dialog')) return;
    driver.phase('3', 'OK — profile.create_via_menu_dialog');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.implemented, greaterThanOrEqualTo(3),
        reason: 'mock-keyring-identity must cover at least 3 flows.');

    // ignore: avoid_print
    print('SUITE_MOCK_KEYRING_IDENTITY: PASS — ${cov.implemented} flows '
        'covered.');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

// ── Top-level shared helpers ──────────────────────────────────────────────

/// Create a local script with the given [title] via the real UI
/// (New Script FAB → ScriptCreationScreen → Title field → Create Script).
///
/// Top-level so the registry closures above can reference it before its
/// declaration in source order.
Future<void> createLocalScript(
  WidgetTester tester,
  E2EDriver d, {
  required String title,
}) async {
  await d.waitUntil(
      tester, () => d.present(find.byType(ScriptsScreen), tester),
      timeout: const Duration(seconds: 5));

  await tester.tap(find.text('New Script'));
  final creationOpen = await d.waitUntil(
      tester, () => d.present(find.byType(ScriptCreationScreen), tester),
      timeout: const Duration(seconds: 5));
  expect(creationOpen, isTrue,
      reason: 'Tapping New Script must push ScriptCreationScreen.');

  await tester.enterText(find.byType(TextFormField).first, title);
  await tester.pump(const Duration(milliseconds: 300));

  await tester.ensureVisible(find.text('Create Script'));
  await tester.tap(find.text('Create Script'));

  final popped = await d.waitUntil(
      tester,
      () => !d.present(find.byType(ScriptCreationScreen), tester),
      timeout: const Duration(seconds: 10));
  expect(popped, isTrue,
      reason: 'Create Script must persist + pop the screen.');
  final snackBar = await d.waitUntil(
      tester,
      () => d.present(find.textContaining('Script created'), tester),
      timeout: const Duration(seconds: 5));
  expect(snackBar, isTrue,
      reason: 'A success SnackBar must confirm the script was created.');
}

/// Find the LocalScriptRowMenu whose record has [title].
LocalScriptRowMenu findLocalScriptMenu(
  WidgetTester tester, {
  required String title,
}) {
  final menus = tester.widgetList<LocalScriptRowMenu>(
      find.byType(LocalScriptRowMenu));
  return menus.firstWhere(
      (m) => m.record.title == title,
      orElse: () => throw StateError(
          'No LocalScriptRowMenu for "$title" found. '
          'Available: ${menus.map((m) => m.record.title)}'));
}
