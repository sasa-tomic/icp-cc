// ROUND-3 UX re-review probe.
//
// Launches the REAL app under the integration-test binding and drives each
// improved flow, capturing screenshots into docs/specs/ux_screenshots/round3/
// and printing decisive widget-tree assertions that back the verdicts in
// docs/specs/UX_REVIEW_ROUND3.md:
//
//   WU-7  : nav tab 2 label is "Canisters" (was "Explore").
//   WU-S2 : first-run wizard shows the BLOCKING ACTIONABLE secure-storage
//           panel (friendly title + copyable install cmd + Retry) instead of
//           letting createProfile throw a raw PlatformException.
//   WU-6  : an always-visible keyboard-icon help button sits next to the
//           profile avatar; tapping it opens the ShortcutsHelpSheet. Ctrl+3
//           is no longer bound (dead binding removed).
//   WU-1  : with no profile (wizard dismissed), the Scripts library
//           empty-state offers "Set Up Profile" instead of the
//           keypair-dependent Create/Browse CTAs.
//   WU-4  : CANNOT-VERIFY on this box (needs >=2 profiles, blocked by no
//           keyring) — documented; code is committed + unit-tested.
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/r3_review_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'r3_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // WU-7: "Explore" tab relabelled to "Canisters".
  // ---------------------------------------------------------------------
  testWidgets('WU-7: 2nd nav tab label is "Canisters" (was "Explore")',
      (tester) async {
    await clearProfileStateR3();
    await launchAppR3(tester);
    await dismissWizardR3(tester);
    await tester.pump(const Duration(seconds: 1));
    await shotR3(binding, '02_nav_canisters_label', tester);

    final hasCanisters = presentR3(find.text('Canisters'), tester);
    final hasExploreLabel = presentR3(find.text('Explore'), tester);
    // ignore: avoid_print
    print('R3_WU7: hasCanistersLabel=$hasCanisters hasExploreLabel=$hasExploreLabel');
    expect(hasCanisters, isTrue,
        reason: 'WU-7: the 2nd nav tab must read "Canisters".');
  });

  // ---------------------------------------------------------------------
  // WU-S2: first-run wizard shows the actionable secure-storage panel.
  //
  // On this keyring-less box, SecureStorageReadiness.check() returns
  // StorageUnavailable, so the wizard renders _buildReadinessPanel on entry
  // (initState post-frame readiness probe) — BEFORE any create attempt.
  // ---------------------------------------------------------------------
  testWidgets('WU-S2: wizard shows actionable secure-storage panel (not raw exception)',
      (tester) async {
    await clearProfileStateR3();
    await launchAppR3(tester);

    // The wizard probes readiness on entry. Wait for the actionable panel:
    // look for the "Setup needed" title and the "Retry" FilledButton.
    bool panelSeen = false;
    bool checkingSeen = false;
    int guard = 0;
    while (guard < 120) {
      await tester.pump(const Duration(milliseconds: 250));
      if (presentR3(find.text('Checking secure storage…'), tester)) {
        checkingSeen = true;
      }
      if (presentR3(find.text('Setup needed'), tester) &&
          presentR3(find.widgetWithText(FilledButton, 'Retry'), tester)) {
        panelSeen = true;
        break;
      }
      // Safety: if the readiness probe somehow said "ready", the form appears.
      if (presentR3(find.text('Create Your Profile'), tester) &&
          !presentR3(find.text('Setup needed'), tester)) {
        break;
      }
      guard++;
    }
    await shotR3(binding, '03_wizard_secure_storage_panel', tester);

    // NEW-4: assert NO raw 'PlatformException(…)' leaks into any painted Text.
    final allText = _allVisibleText(tester);
    final leaksPlatformException = allText
        .where((t) => t.contains('PlatformException'))
        .toList();
    final hasCopyableCmd = presentR3(find.byIcon(Icons.copy_outlined), tester);
    final hasInstallCommandLabel =
        presentR3(find.text('Install command'), tester);
    final hasLockIcon = presentR3(find.byIcon(Icons.lock_outline), tester);

    // ignore: avoid_print
    print('R3_WUS2: panelSeen=$panelSeen checkingSeen=$checkingSeen '
        'hasCopyableCmd=$hasCopyableCmd hasInstallCommandLabel=$hasInstallCommandLabel '
        'hasLockIcon=$hasLockIcon leaksPlatformException=${leaksPlatformException.length}');

    expect(panelSeen, isTrue,
        reason: 'WU-S2: on a keyring-less box the wizard must render the '
            'actionable "Setup needed" panel with a Retry button.');
    expect(hasCopyableCmd, isTrue,
        reason: 'WU-S2: the panel must offer a copyable install command.');
    expect(hasInstallCommandLabel, isTrue,
        reason: 'WU-S2: the "Install command" label must be present.');
    expect(leaksPlatformException, isEmpty,
        reason: 'NEW-4: no painted Text may leak the raw PlatformException(…).');
  });

  // ---------------------------------------------------------------------
  // WU-6: discoverable keyboard help (button + sheet) + Ctrl+3 unbound.
  // ---------------------------------------------------------------------
  testWidgets('WU-6: keyboard help button visible, opens sheet; Ctrl+3 unbound',
      (tester) async {
    await clearProfileStateR3();
    await launchAppR3(tester);
    await dismissWizardR3(tester);
    await tester.pump(const Duration(seconds: 1));

    // Always-visible keyboard-icon help button next to the profile avatar.
    final helpBtn = find.byIcon(Icons.keyboard_outlined);
    final hasHelpBtn = presentR3(helpBtn, tester);
    await shotR3(binding, '04_keyboard_help_button', tester);
    // ignore: avoid_print
    print('R3_WU6: hasShortcutsHelpButton=$hasHelpBtn');
    expect(hasHelpBtn, isTrue,
        reason: 'WU-6: ShortcutsHelpButton (keyboard icon) must be visible.');

    // Tap it -> opens the ShortcutsHelpSheet (title "Keyboard Shortcuts").
    await tester.tap(helpBtn.first, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final sheetOpen = presentR3(find.text('Keyboard Shortcuts'), tester) ||
        presentR3(find.text('NAVIGATION'), tester);
    await shotR3(binding, '05_keyboard_help_sheet', tester);
    // ignore: avoid_print
    print('R3_WU6: helpSheetOpenAfterTap=$sheetOpen');
    expect(sheetOpen, isTrue,
        reason: 'WU-6: tapping the help button must open the shortcuts sheet.');

    // Close the sheet via a barrier tap so later steps start clean.
    if (presentR3(find.text('Keyboard Shortcuts'), tester)) {
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(seconds: 1));
    }

    // Ctrl+3 must NOT navigate anywhere (dead binding removed; only 2 tabs).
    final onScriptsBefore = presentR3(find.text('Popular Canisters'), tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final onScriptsAfter = presentR3(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('R3_WU6: ctrl3IsDead=${onScriptsBefore == onScriptsAfter} '
        '(PopularCanisters before=$onScriptsBefore after=$onScriptsAfter)');
    expect(onScriptsAfter, isFalse,
        reason: 'WU-6: Ctrl+3 is unbound; it must not jump to Canisters.');
  });

  // ---------------------------------------------------------------------
  // WU-1: profile-aware empty-state (no profile -> "Set Up Profile" CTA).
  // ---------------------------------------------------------------------
  testWidgets('WU-1: no-profile empty-state offers "Set Up Profile" CTA',
      (tester) async {
    await clearProfileStateR3();
    await launchAppR3(tester);
    await dismissWizardR3(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shotR3(binding, '06_empty_state_set_up_profile', tester);

    final hasSetUpProfileCta = presentR3(find.text('Set Up Profile'), tester);
    final hasSetUpProfileTitle = presentR3(find.text('Set Up Your Profile'), tester);
    final hasLegacyCreateCta = presentR3(find.text('Create Script'), tester);
    // ignore: avoid_print
    print('R3_WU1: hasSetUpProfileCta=$hasSetUpProfileCta '
        'hasSetUpProfileTitle=$hasSetUpProfileTitle '
        'hasLegacyCreateCta=$hasLegacyCreateCta');
    expect(hasSetUpProfileCta || hasSetUpProfileTitle, isTrue,
        reason: 'WU-1: with no profile, the Scripts library empty-state must '
            'offer the profile-setup CTA, not the keypair-dependent Create.');
  });

  // ---------------------------------------------------------------------
  // Navigation sweep: tap the Canisters tab and screenshot it.
  // ---------------------------------------------------------------------
  testWidgets('Nav: Canisters tab opens BookmarksScreen', (tester) async {
    await clearProfileStateR3();
    await launchAppR3(tester);
    await dismissWizardR3(tester);
    await tester.pump(const Duration(seconds: 1));

    final canistersTab = find.text('Canisters');
    await tester.tap(canistersTab.first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shotR3(binding, '07_canisters_tab', tester);

    final isCanisterTool =
        presentR3(find.text('Popular Canisters'), tester) ||
            presentR3(find.text('Explore ICP Services'), tester) ||
            presentR3(find.text('Recent Calls'), tester);
    // ignore: avoid_print
    print('R3_NAV: canistersTabIsCanisterTool=$isCanisterTool');
    expect(isCanisterTool, isTrue,
        reason: 'The Canisters tab renders BookmarksScreen (canister dev tool).');
  });
}

/// Concatenate every visible Text widget's data (used to prove NEW-4: no raw
/// PlatformException leaks into painted UI).
List<String> _allVisibleText(WidgetTester tester) {
  final out = <String>[];
  tester.widgetList(find.byType(Text)).forEach((w) {
    final t = w as Text;
    final data = t.data ?? '';
    if (data.isNotEmpty) out.add(data);
  });
  return out;
}
