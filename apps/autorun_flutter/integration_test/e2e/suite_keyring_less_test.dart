// ignore_for_file: lines_longer_than_80_chars

/// Suite — PASS 1 (keyring-less / StorageUnavailable).
///
/// Boots the REAL app ONCE, then runs phases with `resetAppState` + remount
/// between isolation groups. This is the fast shared-boot harness: one
/// build/load for the whole keyring-less surface instead of one per file.
///
/// Run: `just e2e-desktop` (PASS 1 — no Secret Service required).
///
/// Covered flows (registered in [FlowRegistry]):
///   first_run.dismiss_wizard, first_run.reopen_wizard_chip,
///   profile.open_menu, settings.open, settings.unlock_dev_options,
///   shortcut.tab_switch
@TestOn('linux')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/profile_setup_chip.dart';

import 'flow_catalog.dart';
import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  final registry = FlowRegistry()
    ..register('first_run.dismiss_wizard', (tester, d) async {
      await d.boot(tester);
      expect(d.present(find.byType(UnifiedSetupWizard), tester), isTrue,
          reason: 'A clean store must show the setup wizard on boot.');
      await d.dismissWizard(tester);
    })
    ..register('first_run.reopen_wizard_chip', (tester, d) async {
      // After wizard is dismissed, the persistent chip re-opens it.
      final chip = find.byType(ProfileSetupChip);
      expect(d.present(chip, tester), isTrue,
          reason: 'ProfileSetupChip must be visible after wizard dismissal.');
      await tester.tap(chip);
      final reopened = await d.waitUntil(
          tester, () => d.present(find.byType(UnifiedSetupWizard), tester),
          timeout: const Duration(seconds: 5));
      expect(reopened, isTrue,
          reason: 'Tapping the chip must re-open the wizard.');
    })
    ..register('profile.open_menu', (tester, d) async {
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(d.present(find.text('Settings'), tester), isTrue,
          reason: 'Profile menu must show a Settings tile.');
      expect(d.present(find.textContaining('Account'), tester), isTrue,
          reason: 'Profile menu must show a My Account tile.');
    })
    ..register('settings.open', (tester, d) async {
      // Menu is already open from profile.open_menu; tap Settings.
      await tester.tap(find.text('Settings'));
      final opened = await d.waitUntil(
          tester, () => d.present(find.byType(SettingsScreen), tester),
          timeout: const Duration(seconds: 5));
      expect(opened, isTrue, reason: 'Tapping Settings must open SettingsScreen.');
    })
    ..register('settings.unlock_dev_options', (tester, d) async {
      // Wait for the version text to render (loaded async from package_info).
      final versionReady = await d.waitUntil(
          tester, () => d.present(find.textContaining('Version'), tester),
          timeout: const Duration(seconds: 5));
      expect(versionReady, isTrue,
          reason: 'Settings must display a version entry.');

      // Scroll the version text into view (it's at the bottom of the list).
      await tester.ensureVisible(find.textContaining('Version').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the version text 7 times to unlock dev options.
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.textContaining('Version').first);
        await tester.pump(const Duration(milliseconds: 200));
      }
      final devVisible = await d.waitUntil(
          tester, () => d.present(find.text('DEVELOPER INFO'), tester),
          timeout: const Duration(seconds: 3));
      expect(devVisible, isTrue,
          reason: 'Seven taps on version must reveal the DEVELOPER INFO section.');
    })
    ..register('shortcut.tab_switch', (tester, d) async {
      // Alt+2 → Canisters (BookmarksScreen).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final canisters = await d.waitUntil(
          tester, () => d.present(find.byType(BookmarksScreen), tester),
          timeout: const Duration(seconds: 3));
      expect(canisters, isTrue,
          reason: 'Alt+2 must switch to the Canisters tab.');

      // Alt+1 → Scripts.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final scripts = await d.waitUntil(
          tester, () => d.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 3));
      expect(scripts, isTrue,
          reason: 'Alt+1 must switch back to the Scripts tab.');
    });

  testWidgets('e2e suite — keyring-less: shared boot + flows', (tester) async {
    // ── GROUP A: harness mechanism (boot + isolation) ──────────────────────
    // PHASE 0: clean slate + first boot → wizard present.
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.boot(tester);
    driver.phase('0', 'booted — asserting first-run wizard present');
    final wizardOnBoot = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnBoot, isTrue,
        reason: 'On a wiped store with no Secret Service the first-run gate '
            'must show the setup wizard.');
    await driver.screenshot(tester, 'kl_00_first_run_wizard');
    driver.phase('0', 'OK');

    // PHASE 1: resetAppState + remount → wizard re-fires (isolation proof).
    await resetAppState(tester: tester, wipeSecureStorage: false);
    await driver.remount(tester);
    driver.phase('1', 'remount — asserting first-run gate re-fired');
    final wizardOnRemount = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardOnRemount, isTrue,
        reason: 'resetAppState + remount must reproduce a first-run boot.');
    driver.phase('1', 'OK');

    // ── GROUP B: user flows on a single session ────────────────────────────
    // PHASE 2: dismiss wizard → ScriptsScreen visible.
    driver.phase('2', 'dismiss wizard → ScriptsScreen');
    await driver.dismissWizard(tester);
    final scriptsVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 10));
    expect(scriptsVisible, isTrue,
        reason: 'After dismissing the wizard the Scripts tab must render.');
    driver.phase('2', 'OK — first_run.dismiss_wizard');

    // PHASE 3: reopen wizard via persistent chip.
    driver.phase('3', 'tap ProfileSetupChip → wizard re-opens');
    await registry.runFor('first_run.reopen_wizard_chip')!(tester, driver);
    driver.phase('3', 'OK — first_run.reopen_wizard_chip');

    // PHASE 4: dismiss again → ScriptsScreen → open profile menu.
    driver.phase('4', 'dismiss + open profile menu');
    await driver.dismissWizard(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 5));
    await registry.runFor('profile.open_menu')!(tester, driver);
    driver.phase('4', 'OK — profile.open_menu');

    // PHASE 5: tap Settings tile → SettingsScreen.
    driver.phase('5', 'navigate to Settings');
    await registry.runFor('settings.open')!(tester, driver);
    driver.phase('5', 'OK — settings.open');

    // PHASE 6: unlock dev options (7 taps on version).
    driver.phase('6', 'unlock dev options');
    await registry.runFor('settings.unlock_dev_options')!(tester, driver);
    driver.phase('6', 'OK — settings.unlock_dev_options');

    // PHASE 7: keyboard shortcuts (Alt+1/2 tab switching).
    driver.phase('7', 'keyboard shortcuts');
    // Close Settings to return to the main shell.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    // Ensure we're back on the Scripts tab.
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 5));
    await registry.runFor('shortcut.tab_switch')!(tester, driver);
    driver.phase('7', 'OK — shortcut.tab_switch');

    // ── COVERAGE REPORT ────────────────────────────────────────────────────
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} implemented; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.total, greaterThan(90), reason: 'Catalog must list all flows.');
    expect(cov.implemented, greaterThanOrEqualTo(6));

    // ignore: avoid_print
    print('SUITE_KEYRING_LESS: PASS — ${cov.implemented} flows covered.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
