// Flow D / WU-6 — desktop keyboard shortcuts: are they discoverable, and is
// Ctrl+3 a dead shortcut (registered but no third tab exists)?
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

  testWidgets('D: Ctrl+2/Ctrl+1 switch tabs; Ctrl+3 is DEAD (no 3rd tab)', (tester) async {
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

    // Ctrl+3 -> "navigate" to tab index 2 which DOES NOT EXIST.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final exploreAfterCtrl3 = present(find.text('Popular Canisters'), tester);
    // ignore: avoid_print
    print('D_WU6: exploreShownAfterCtrl3=$exploreAfterCtrl3 (Ctrl+3 dead -> no change from Ctrl+1)');

    // Verdicts.
    expect(exploreAfterCtrl2, isTrue,
        reason: 'WU-6 partial: Ctrl+2 DOES navigate to Canisters tab (shortcut works).');
    expect(exploreAfterCtrl1, isFalse,
        reason: 'WU-6 partial: Ctrl+1 returns to Scripts (shortcut works).');
    // Ctrl+3 fired but there is no 3rd tab, so the view must NOT have jumped
    // to Canisters again — it stays on Scripts (exploreAfterCtrl3 == false).
    expect(exploreAfterCtrl3, isFalse,
        reason: 'WU-6: Ctrl+3 is a DEAD shortcut — registered in keyboard_shortcuts.dart '
            '(_NavigateTabIntent(2)) but only 2 tabs exist. Fires with no effect.');
  });

  testWidgets('D: shortcuts are NOT discoverable (no "?" overlay / always-on hints)', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    await tester.pump(const Duration(seconds: 1));
    await shot(binding, '11_shortcut_undiscoverable', tester);

    // There is no keyboard-shortcuts help overlay triggered by "?" or any
    // always-visible shortcut legend. ShortcutTooltip only renders on hover as
    // a Material Tooltip, which a user cannot discover without hovering every
    // control.
    final hasHelpOverlay = present(find.text('?'), tester) ||
        present(find.text('Shortcuts'), tester) ||
        present(find.text('Keyboard Shortcuts'), tester) ||
        present(find.textContaining('? for shortcuts'), tester);
    // ignore: avoid_print
    print('D_WU6_discoverability: hasShortcutHelpOverlay=$hasHelpOverlay');
    expect(hasHelpOverlay, isFalse,
        reason: 'WU-6: no discoverable shortcut help (no "?" overlay, no legend); '
            'shortcuts only surface as hover Tooltips.');
  });
}
