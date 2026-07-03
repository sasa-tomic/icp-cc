import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/theme/modern_components.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

import '../../shared/fake_connectivity_service.dart';

/// UX-2 — the "Canisters" bottom-nav tab and the BookmarksScreen AppBar title
/// must show the SAME label. Previously the tab said "Canisters" while the
/// AppBar said "Explore ICP Services" (an honesty/clarity gap). Both now source
/// their text from [kCanistersTabLabel].
void main() {
  testWidgets(
      'UX-2: AppBar title matches the bottom-nav tab label for the Canisters '
      'screen', (tester) async {
    // Pump the real BookmarksScreen (the Canisters tab body) together with a
    // ModernNavigationBar that uses the same shared label constant as main.dart.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectivityScope(
            service: FakeConnectivityService(),
            child: const BookmarksScreen(bridge: RustBridgeLoader()),
          ),
          bottomNavigationBar: ModernNavigationBar(
            currentIndex: 1, // Canisters tab active
            onTap: (_) {},
            items: const [
              ModernNavigationItem(
                icon: Icons.code_outlined,
                activeIcon: Icons.code_rounded,
                label: 'Scripts',
              ),
              ModernNavigationItem(
                icon: Icons.dns_outlined,
                activeIcon: Icons.dns_rounded,
                label: kCanistersTabLabel,
              ),
            ],
          ),
        ),
      ),
    );
    // Let ConnectivityScope's async init (periodic-check setup) run so its
    // timer is created and then cleanly cancelled on tree disposal (mirrors the
    // scripts test harness settle).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The AppBar title (the screen header) and the nav tab label are BOTH the
    // shared constant, so the exact text appears exactly twice.
    expect(
      find.text(kCanistersTabLabel),
      findsNWidgets(2),
      reason: 'Canisters label must appear once in the AppBar header and once '
          'in the bottom-nav tab — they must match (UX-2).',
    );

    // Pin each occurrence to its surface so a future refactor that drops one
    // side is caught.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(kCanistersTabLabel)),
      findsOneWidget,
      reason: 'The BookmarksScreen AppBar title must be the Canisters label.',
    );
    expect(
      find.descendant(
          of: find.byType(ModernNavigationBar),
          matching: find.text(kCanistersTabLabel)),
      findsOneWidget,
      reason: 'The bottom-nav tab label must be the Canisters label.',
    );

    // The old, dishonest header must be gone.
    expect(find.text('Explore ICP Services'), findsNothing);
  });
}
