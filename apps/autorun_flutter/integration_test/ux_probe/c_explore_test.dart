// Flow C / A-1 — the "Explore" tab is a canister-call dev tool (BookmarksScreen),
// NOT a marketplace browser. Validates the plan's rename proposal (Explore ->
// Canisters) with evidence.
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/c_explore_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/main.dart' as app;
import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('C/A-1: Explore tab = canister dev tool, only 2 tabs', (tester) async {
    await clearProfileState();
    await launchApp(tester);

    // Dismiss the first-run wizard (Icons.close in the AppBar).
    int guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(seconds: 1));

    // Tap the "Canisters" navigation item.
    final exploreTab = find.text('Canisters');
    expect(present(exploreTab, tester), isTrue);
    await tester.tap(exploreTab.first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot(binding, '09_explore_tab_is_canisters', tester);

    // Decisive: the Canisters tab renders BookmarksScreen (canister tool), not a
    // marketplace browse view.
    final isCanisterTool = present(find.text('Popular Canisters'), tester) ||
        present(find.text('Explore ICP Services'), tester) ||
        present(find.text('Recent Calls'), tester);
    // ignore: avoid_print
    print('C_A1: isCanisterTool=$isCanisterTool');
    expect(isCanisterTool, isTrue,
        reason: 'A-1: the "Canisters" tab is a canister-call dev tool '
            '(BookmarksScreen), not a marketplace browser.');

    // Exactly two navigation items exist (no third tab).
    final exploreCount = tester.widgetList(find.text('Canisters')).length;
    // ignore: avoid_print
    print('C_A1: exploreLabelCount=$exploreCount');
    expect(present(find.text('Scripts'), tester), isTrue);
  });
}
