// ignore_for_file: lines_longer_than_80_chars

/// Flow registry for the mock-keyring identity + scripts.publish e2e suite.
///
/// Extracted from `suite_mock_keyring_identity_test.dart` so the same flow
/// implementations can be driven either:
///   - chained in one shared-boot `testWidgets` (the monolith suite, used by
///     `just e2e-desktop` PASS 2c), or
///   - one-per-`testWidgets` in `flows_mock_keyring_identity_test.dart`
///     (used by `just e2e-one <flow-id> mock-keyring-identity` for fast
///     <20s iteration).
///
/// The flows are self-contained `(tester, driver) → Future<void>` closures.
/// State evolves naturally: local-only → registered → second profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/account_registration_wizard.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/widgets/script_row_menus.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

/// Profile name used across the identity suite's flows.
const kIdentityProfileName = 'Identity Suite Owner';

/// Build the FlowRegistry for the mock-keyring identity suite.
FlowRegistry buildMockKeyringIdentityRegistry() {
  return FlowRegistry()
    // ── account.register_from_publish: from a LOCAL-ONLY profile, attempt
    // to publish → the marketplace-publish gate fires the "Share to
    // Marketplace" prompt → "Register Username" → AccountRegistrationWizard
    // pushes → fill username + display name → real registerAccount →
    // wizard pops with the Account. Then CANCEL the subsequent
    // QuickUploadDialog (the flow's contract ends at registration success).
    ..register('account.register_from_publish', (tester, d) async {
      await createLocalScript(tester, d, title: 'Register From Publish');

      final menu = findLocalScriptMenu(tester, title: 'Register From Publish');
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

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

      await tester.tap(find.text('Register Username'));
      final wizardPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(AccountRegistrationWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardPushed, isTrue,
          reason: 'Tapping Register Username must push the wizard.');

      final displayNameField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Display Name *');
      if (d.present(displayNameField, tester)) {
        await tester.enterText(displayNameField, kIdentityProfileName);
        await tester.pump(const Duration(milliseconds: 300));
      }

      final uniqueUsername = 'p${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.labelText == 'Username'),
          uniqueUsername);
      await tester.pump(const Duration(milliseconds: 500));

      final registerEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Register'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 20));
      expect(registerEnabled, isTrue,
          reason: 'Register must become enabled after valid input.');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Register'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // UX-H6: dismiss the post-registration security prompt.
      await dismissPostRegistrationSecurityPrompt(tester, d);

      final wizardClosed = await d.waitUntil(
          tester,
          () => !d.present(find.byType(AccountRegistrationWizard), tester),
          timeout: const Duration(seconds: 20));
      expect(wizardClosed, isTrue,
          reason: 'The AccountRegistrationWizard must pop after the '
              'registerAccount round-trip succeeds.');

      final uploadDialogShown = await d.waitUntil(
          tester,
          () => d.present(find.byType(QuickUploadDialog), tester),
          timeout: const Duration(seconds: 5));
      expect(uploadDialogShown, isTrue,
          reason: 'After registration the publish flow must proceed into '
              'QuickUploadDialog (proves the wizard returned an Account).');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 500));

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
    // ── scripts.publish: create a fresh local script → publish via
    // QuickUploadDialog → real signed uploadScript round-trip → success.
    // Assumes profile has a registered username.
    ..register('scripts.publish', (tester, d) async {
      await createLocalScript(tester, d, title: 'Publish Me');

      final menu = findLocalScriptMenu(tester, title: 'Publish Me');
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();

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
              'QuickUploadDialog directly.');

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

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('quick-upload-submit')));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pump(const Duration(milliseconds: 500));

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
          reason: 'A success SnackBar must confirm the signed upload.');

      ScaffoldMessenger.of(scaffoldCtx).removeCurrentSnackBar();
      await tester.pump(const Duration(milliseconds: 300));
    })
    // ── profile.create_via_menu_dialog: the UX-PMD-1 regression flow.
    // Open profile menu → "Switch Profile" → manage sheet → "Create New
    // Profile" → UnifiedSetupWizard pushes → fill + Get Started → success.
    // Assumes app is at ScriptsScreen.
    ..register('profile.create_via_menu_dialog', (tester, d) async {
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Switch Profile'));
      final sheetOpen = await d.waitUntil(
          tester,
          () => d.present(find.text('Create New Profile'), tester),
          timeout: const Duration(seconds: 5));
      expect(sheetOpen, isTrue,
          reason: 'Tapping Switch Profile must open the manage sheet.');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Create New Profile'));
      final wizardPushed = await d.waitUntil(
          tester,
          () => d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardPushed, isTrue,
          reason: 'The UnifiedSetupWizard must push from the manage sheet '
              'without throwing use-after-dispose (UX-PMD-1).');

      final uniqueUsername = 'm${DateTime.now().millisecondsSinceEpoch}';
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

      final getStartedEnabled = await d.waitUntil(
          tester,
          () {
            final btn = tester.widgetList<FilledButton>(
                find.widgetWithText(FilledButton, 'Get Started'));
            return btn.isNotEmpty && btn.first.onPressed != null;
          },
          timeout: const Duration(seconds: 15));
      expect(getStartedEnabled, isTrue,
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

      await tester.tap(find.text('Start Exploring'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      final wizardClosed = await d.waitUntil(
          tester,
          () => !d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(wizardClosed, isTrue,
          reason: 'Tapping Start Exploring must dismiss the wizard.');

      final profileController = ProfileScope.of(
          tester.element(find.byType(ScriptsScreen)),
          listen: false);
      final matchingProfile = profileController.profiles.firstWhere(
          (p) => p.username == uniqueUsername,
          orElse: () => throw StateError(
              'Newly-created profile $uniqueUsername not found.'));
      expect(matchingProfile.name, 'Menu Created Profile',
          reason: 'The new profile name must match what was entered.');
    });
}

// ── Top-level shared helpers ──────────────────────────────────────────────

/// Create a local script with the given [title] via the real UI
/// (New Script FAB → ScriptCreationScreen → Title field → Create Script).
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
