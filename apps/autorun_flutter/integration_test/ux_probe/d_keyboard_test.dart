// Flow D / WU-6 — desktop keyboard shortcuts: are they discoverable, and does
// Ctrl+3 do nothing (only 2 tabs exist, binding was removed in WU-6)?
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/d_keyboard_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> dismissWizard(WidgetTester tester) async {
    int guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    if (present(find.byIcon(Icons.close), tester)) {
      await tester.tap(find.byIcon(Icons.close).first);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('D: Ctrl+2/Ctrl+1 switch tabs; Ctrl+3 is unbound (no 3rd tab)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    // Baseline: on Scripts tab (index 0). Canisters content NOT shown yet.
    final exploreInitially = present(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('D_WU6: exploreShownInitially=$exploreInitially');

    // Ctrl+2 -> navigate to tab index 1 (Canisters / BookmarksScreen).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final exploreAfterCtrl2 = present(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('D_WU6: exploreShownAfterCtrl2=$exploreAfterCtrl2');

    // Ctrl+1 -> back to Scripts (index 0).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final exploreAfterCtrl1 = present(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('D_WU6: exploreShownAfterCtrl1=$exploreAfterCtrl1 (should be false)');

    // Ctrl+3 is not registered (only 2 tabs exist). Stays on Scripts.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final exploreAfterCtrl3 = present(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('D_WU6: exploreShownAfterCtrl3=$exploreAfterCtrl3 (Ctrl+3 unbound -> no change from Ctrl+1)');

    // Verdicts.
    expect(exploreAfterCtrl2, isTrue,
        reason: 'WU-6 partial: Ctrl+2 DOES navigate to Canisters tab (shortcut works).');
    expect(exploreAfterCtrl1, isFalse,
        reason: 'WU-6 partial: Ctrl+1 returns to Scripts (shortcut works).');
    // Ctrl+3 is no longer registered (dead binding removed in WU-6), so the
    // view must NOT have jumped to Canisters again — it stays on Scripts.
    expect(exploreAfterCtrl3, isFalse,
        reason: 'WU-6: Ctrl+3 is unbound — only 2 tabs exist, so no navigation occurs.');
  });

  testWidgets('D: shortcuts ARE discoverable (? overlay + always-visible button)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    await tester.pump(const Duration(seconds: 1));
    await shot(binding, '11_shortcut_discoverable', tester);

    // WU-6: an always-visible keyboard-icon button (next to the profile avatar)
    // makes shortcuts discoverable without a keyboard.
    final hasHelpButton = present(find.byIcon(Icons.keyboard_outlined), tester);
    // ignore: avoid_print
    print('D_WU6_discoverability: hasShortcutsButton=$hasHelpButton');
    expect(hasHelpButton, isTrue,
        reason: 'WU-6: a ShortcutsHelpButton (keyboard icon) must always be visible.');

    // Tapping it opens the shortcuts help overlay.
    await tester.tap(find.byIcon(Icons.keyboard_outlined).first, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final overlayOpen = present(find.text('Keyboard Shortcuts'), tester) ||
        present(find.text('NAVIGATION'), tester);
    // ignore: avoid_print
    print('D_WU6_discoverability: helpOverlayOpenAfterTap=$overlayOpen');
    expect(overlayOpen, isTrue,
        reason: 'WU-6: tapping the help button must open the shortcuts overlay.');
  });
}
