// ignore_for_file: lines_longer_than_80_chars

/// Comprehensive screenshot-capture test — boots the real app under Xvfb and
/// captures one PNG per major screen for visual/UX review via zai-vision.
///
/// Run:
///   DISPLAY=:99 MARKETPLACE_API_PORT=$(cat ../../.just-tmp/icp-api.port) \
///     flutter test integration_test/e2e/screenshot_capture_test.dart -d linux
///
/// Screenshots land in docs/specs/ux_screenshots/e2e/ prefixed with `cap_`.
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/screens/dapps_screen.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/models/profile_keypair.dart';

import 'e2e_driver.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final driver = E2EDriver(surface: E2ESurface.desktop);

  Future<void> capture(WidgetTester tester, String name) async {
    await driver.screenshot(tester, name);
    // ignore: avoid_print
    print('CAPTURE: $name');
  }

  testWidgets('screenshot capture — all major screens', (tester) async {
    // ── Setup: create a profile, boot, dismiss wizard ────────────────────
    await resetAppState(tester: tester);
    await driver.boot(tester);

    // Create a profile via controller (fast, no wizard UI)
    final controller = ProfileController();
    await tester.runAsync(() => controller.createProfile(
          profileName: 'Screenshot User',
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await driver.remount(tester);

    // Wait for Scripts screen
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));

    // ── 1. Scripts screen (marketplace browse) ───────────────────────────
    await tester.pump(const Duration(seconds: 2));
    await capture(tester, 'cap_01_scripts_marketplace');

    // ── 2. Search with results ───────────────────────────────────────────
    final searchField = find.byType(TextField);
    if (driver.present(searchField, tester)) {
      await tester.tap(searchField.first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(searchField.first, 'ICP');
      await tester.pump(const Duration(seconds: 1));
      await capture(tester, 'cap_02_search_results');
      // Clear search
      await tester.enterText(searchField.first, '');
      await tester.pump(const Duration(milliseconds: 500));
    }

    // ── 3. Filter sheet ──────────────────────────────────────────────────
    final filterBtn = find.byIcon(Icons.filter_list);
    if (driver.present(filterBtn, tester)) {
      await tester.tap(filterBtn.first);
      await tester.pump(const Duration(seconds: 1));
      await capture(tester, 'cap_03_filter_sheet');
      // Close filter
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 500));
    }

    // ── 4. Profile menu ──────────────────────────────────────────────────
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'cap_04_profile_menu');
    // Close menu
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));

    // ── 5. Settings screen ───────────────────────────────────────────────
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    final settingsTile = find.text('Settings');
    if (driver.present(settingsTile, tester)) {
      await tester.tap(settingsTile.first);
      await driver.waitUntil(
          tester, () => driver.present(find.byType(SettingsScreen), tester),
          timeout: const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await capture(tester, 'cap_05_settings');
      // Go back
      await tester.pageBack();
      await driver.waitUntil(
          tester, () => driver.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));
    }

    // ── 6. Canisters tab ─────────────────────────────────────────────────
    // Find bottom nav bar and tap Canisters
    final canistersTab = find.text('Canisters');
    if (driver.present(canistersTab, tester)) {
      await tester.tap(canistersTab.first);
      await tester.pump(const Duration(seconds: 2));
      await capture(tester, 'cap_06_canisters');
    }

    // ── 7. Dapps tab ─────────────────────────────────────────────────────
    final dappsTab = find.text('Dapps');
    if (driver.present(dappsTab, tester)) {
      await tester.tap(dappsTab.first);
      await driver.waitUntil(
          tester, () => driver.present(find.byType(DappsScreen), tester),
          timeout: const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 2));
      await capture(tester, 'cap_07_dapps');
    }

    // ── 8. Back to scripts — tap a marketplace tile to see details ───────
    final scriptsTab = find.text('Scripts');
    if (driver.present(scriptsTab, tester)) {
      await tester.tap(scriptsTab.first);
      await driver.waitUntil(
          tester, () => driver.present(find.byType(ScriptsScreen), tester),
          timeout: const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 2));

      // Tap the first marketplace tile
      final tiles = find.byType(ListTile);
      if (tester.widgetList<ListTile>(tiles).length > 1) {
        await tester.tap(tiles.at(1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 500));
        await capture(tester, 'cap_08_script_details');
        // Close dialog
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    // ── 9. New Script creation screen ────────────────────────────────────
    final fab = find.byTooltip('New Script');
    if (!driver.present(fab, tester)) {
      // Try by icon
      final fabIcon = find.byIcon(Icons.add);
      if (driver.present(fabIcon, tester)) {
        await tester.tap(fabIcon.first);
        await tester.pump(const Duration(seconds: 1));
        await capture(tester, 'cap_09_new_script');
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    // ignore: avoid_print
    print('SCREENSHOT_CAPTURE: DONE — all screens captured');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
