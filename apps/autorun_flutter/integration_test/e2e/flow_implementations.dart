// ignore_for_file: lines_longer_than_80_chars

/// Shared [FlowRun] implementations — cross-surface flow bodies that work
/// identically on desktop (`integration_test` + real FFI) and Web
/// (`flutter test -d chrome` + substrate fakes).
///
/// Each function is a single [FlowRun]:
///   `Future<void> Function(WidgetTester tester, E2EDriver driver)`
///
/// The desktop suites (`integration_test/e2e/suite_*.dart`) currently inline
/// their flow bodies as closure literals; this library is where NEW
/// cross-surface flows live so the desktop suites can later swap their
/// inlined bodies for the library versions one flow at a time (DRY migration
/// without big-bang risk). See `2026-07-19-e2e-and-ux-continuation.md`
/// Phase C-Tier-A.
///
/// Design rules:
/// - Pure widget-tree interaction (no `dart:io`, no FFI, no `package:http`).
/// - All async work goes through the [E2EDriver]'s helpers or bounded `pump`s.
/// - Same surface-agnostic finders (`find.text`, `find.byType`, `find.byTooltip`)
///   that already work on both surfaces.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

import 'e2e_driver.dart';

/// `first_run.dismiss_wizard` — boot, expect wizard, dismiss via X.
///
/// Surface-agnostic: the wizard's `Close setup` tooltip works on both
/// desktop and Web canvaskit. Boot is delegated to the driver
/// (real `app.main()` on desktop; `pumpWidget(KeypairApp())` on Web).
Future<void> firstRunDismissWizard(
    WidgetTester tester, E2EDriver driver) async {
  await driver.boot(tester);
  final wizard = find.byType(UnifiedSetupWizard);
  final present = await driver.waitUntil(tester, () => driver.present(wizard, tester),
      timeout: const Duration(seconds: 15));
  if (!present) {
    // Wizard may have already been dismissed in a prior flow on this surface
    // (e.g. profile prefs pre-seeded). That is also a valid terminal state
    // for the cross-surface contract — the chip should be visible instead.
    final chip = find.textContaining('Set up profile');
    expect(driver.present(chip, tester), isTrue,
        reason: 'Either the wizard must show on clean boot, or the persistent '
            '"Set up profile" chip must be visible after dismissal.');
    return;
  }
  await driver.dismissWizard(tester);
  expect(driver.present(find.byType(UnifiedSetupWizard), tester), isFalse,
      reason: 'Tapping "Close setup" must dismiss the wizard.');
}

/// `profile.open_menu` — tap the profile avatar, expect Settings + Account
/// entries in the bottom sheet.
Future<void> profileOpenMenu(WidgetTester tester, E2EDriver driver) async {
  await tester.tap(find.byType(ProfileAvatarButton));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 500));
  expect(driver.present(find.text('Settings'), tester), isTrue,
      reason: 'Profile menu must show a Settings tile.');
  expect(driver.present(find.textContaining('Account'), tester), isTrue,
      reason: 'Profile menu must show a My Account tile.');
}

/// `settings.open` — assumes the menu is open from `profile.open_menu`; tap
/// the Settings tile, expect `SettingsScreen` to mount.
Future<void> settingsOpen(WidgetTester tester, E2EDriver driver) async {
  await tester.tap(find.text('Settings'));
  final opened = await driver.waitUntil(
      tester, () => driver.present(find.byType(SettingsScreen), tester),
      timeout: const Duration(seconds: 5));
  expect(opened, isTrue, reason: 'Tapping Settings must open SettingsScreen.');
}

/// `settings.theme` — tap "Dark", expect the `SegmentedButton<ThemeMode>`
/// selected segment to move; then restore "System" so the theme doesn't leak
/// across flows.
Future<void> settingsTheme(WidgetTester tester, E2EDriver driver) async {
  await tester.ensureVisible(find.text('Dark'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Dark'));
  await tester.pump(const Duration(milliseconds: 500));
  // The theme picker is a SegmentedButton<ThemeMode>. The selected segment
  // is reflected in the button's `selected` set.
  final segmented =
      tester.widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>));
  expect(segmented.selected, equals({ThemeMode.dark}),
      reason: 'Selecting Dark must mark the Dark segment as selected.');
  // Restore System to avoid leaking the theme across phases. Re-scroll into
  // view first: switching themes reflows the layout.
  await tester.ensureVisible(find.text('System'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('System'));
  await tester.pump(const Duration(milliseconds: 500));
}

/// `settings.version_display` — assert the version heading renders. Waits
/// for the Settings body to finish loading (`PackageInfo.fromPlatform()` is
/// async; until it resolves, the body shows a spinner instead of the
/// "ICP Autorun" heading).
Future<void> settingsVersionDisplay(
    WidgetTester tester, E2EDriver driver) async {
  final headingReady = await driver.waitUntil(
      tester, () => driver.present(find.text('ICP Autorun'), tester),
      timeout: const Duration(seconds: 5));
  expect(headingReady, isTrue,
      reason: 'Settings must show the "ICP Autorun" heading '
          '(PackageInfo.fromPlatform must resolve).');
}

/// `scripts.browse_marketplace` — assert the 3 seeded scripts render. Caller
/// must be on the Scripts tab (default after wizard dismiss).
Future<void> scriptsBrowseMarketplace(
    WidgetTester tester, E2EDriver driver) async {
  // The substrate server returns exactly: Interactive Counter, ICP Balance
  // Reader, Hello IC Starter. Wait for each to appear (the marketplace fetch
  // fires async after the Scripts tab mounts).
  const titles = <String>[
    'Interactive Counter',
    'ICP Balance Reader',
    'Hello IC Starter',
  ];
  for (final title in titles) {
    final found = await driver.waitUntil(
        tester, () => driver.present(find.text(title), tester),
        timeout: const Duration(seconds: 15));
    expect(found, isTrue, reason: 'Marketplace must list "$title".');
  }
}

/// `first_run.reopen_wizard_chip` — after dismissal, the persistent chip
/// re-opens the wizard. Assumes the wizard was dismissed in a prior flow.
Future<void> firstRunReopenWizardChip(
    WidgetTester tester, E2EDriver driver) async {
  final chip = find.textContaining('Set up profile');
  final present =
      await driver.waitUntil(tester, () => driver.present(chip, tester),
          timeout: const Duration(seconds: 5));
  expect(present, isTrue,
      reason: 'ProfileSetupChip must be visible after wizard dismissal.');
  await tester.tap(chip);
  final reopened = await driver.waitUntil(
      tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
      timeout: const Duration(seconds: 5));
  expect(reopened, isTrue, reason: 'Tapping the chip must re-open the wizard.');
  // Dismiss it again to leave the shell in a known state for the next flow.
  await driver.dismissWizard(tester);
}

// ── Settings flows (assume settings.open already ran: SettingsScreen on stage)
// All ported cross-surface from the desktop keyring-less suite. These are
// surface-agnostic widget-tree interactions (no dart:io, no FFI).

/// `settings.unlock_dev_options` — tap the version row 7 times to reveal the
/// hidden DEVELOPER INFO section. Assumes SettingsScreen is already mounted.
Future<void> settingsUnlockDevOptions(
    WidgetTester tester, E2EDriver driver) async {
  final versionReady = await driver.waitUntil(
      tester, () => driver.present(find.textContaining('Version'), tester),
      timeout: const Duration(seconds: 5));
  expect(versionReady, isTrue,
      reason: 'Settings must display a version entry.');
  await tester.ensureVisible(find.textContaining('Version').first);
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 7; i++) {
    await tester.tap(find.textContaining('Version').first);
    await tester.pump(const Duration(milliseconds: 200));
  }
  final devVisible = await driver.waitUntil(
      tester, () => driver.present(find.text('DEVELOPER INFO'), tester),
      timeout: const Duration(seconds: 3));
  expect(devVisible, isTrue,
      reason: 'Seven taps on version must reveal the DEVELOPER INFO section.');
}

/// `settings.docs_link` — assert the Documentation row renders.
Future<void> settingsDocsLink(WidgetTester tester, E2EDriver driver) async {
  expect(driver.present(find.text('Documentation'), tester), isTrue,
      reason: 'Settings must show a Documentation link.');
}

/// `settings.report_issue` — assert the Report Issue row renders.
Future<void> settingsReportIssue(WidgetTester tester, E2EDriver driver) async {
  expect(driver.present(find.text('Report Issue'), tester), isTrue,
      reason: 'Settings must show a Report Issue link.');
}

/// `settings.getting_started` — tap "Getting Started", expect a confirmation
/// SnackBar.
Future<void> settingsGettingStarted(
    WidgetTester tester, E2EDriver driver) async {
  await tester.ensureVisible(find.text('Getting Started'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Getting Started'));
  final snackBar = await driver.waitUntil(
      tester,
      () => driver.present(find.textContaining('Getting Started guide'), tester),
      timeout: const Duration(seconds: 3));
  expect(snackBar, isTrue,
      reason: 'Getting Started must show a confirmation SnackBar.');
}

/// `settings.restart_tour` — tap "Restart Tour", expect the scheduling SnackBar.
Future<void> settingsRestartTour(WidgetTester tester, E2EDriver driver) async {
  await tester.ensureVisible(find.text('Restart Tour'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Restart Tour'));
  final tourScheduled = await driver.waitUntil(
      tester,
      () => driver.present(find.textContaining('Tour will start'), tester),
      timeout: const Duration(seconds: 3));
  expect(tourScheduled, isTrue,
      reason: 'Restart Tour must schedule the spotlight tour.');
}

/// `settings.copy_api_endpoint` — assumes dev options unlocked (run
/// `settings.unlock_dev_options` first). Taps the Copy IconButton and expects
/// a SnackBar.
Future<void> settingsCopyApiEndpoint(
    WidgetTester tester, E2EDriver driver) async {
  expect(driver.present(find.text('API Endpoint'), tester), isTrue,
      reason: 'Dev-options card must show the API Endpoint row.');
  await tester.ensureVisible(find.text('API Endpoint'));
  await tester.pump(const Duration(milliseconds: 300));
  final copyBtn = find.widgetWithIcon(IconButton, Icons.copy);
  expect(driver.present(copyBtn, tester), isTrue,
      reason: 'API Endpoint row must have a Copy IconButton.');
  tester.widget<IconButton>(copyBtn).onPressed!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final copied = await driver.waitUntil(
      tester, () => driver.present(find.byType(SnackBar), tester),
      timeout: const Duration(seconds: 3));
  expect(copied, isTrue, reason: 'Copy callback must show a SnackBar.');
}

/// `settings.clear_dev_options` — assumes dev options unlocked. Taps "Clear
/// Developer Options" and expects the DEVELOPER INFO card to vanish.
Future<void> settingsClearDevOptions(
    WidgetTester tester, E2EDriver driver) async {
  await tester.ensureVisible(find.text('Clear Developer Options'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Clear Developer Options'), warnIfMissed: false);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 500));
  final devGone = await driver.waitUntil(
      tester, () => !driver.present(find.text('DEVELOPER INFO'), tester),
      timeout: const Duration(seconds: 5));
  expect(devGone, isTrue,
      reason: 'Clearing dev options must remove the DEVELOPER INFO card.');
}
