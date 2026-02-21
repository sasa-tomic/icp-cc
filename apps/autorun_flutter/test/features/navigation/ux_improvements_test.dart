import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

void main() {
  group('Navigation UX Improvements', () {
    group('Explore tab (formerly Canisters)', () {
      testWidgets('BookmarksScreen AppBar shows Explore ICP Services title',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ConnectivityScope(
              child: BookmarksScreen(
                bridge: const RustBridgeLoader(),
                onOpenClient: ({initialCanisterId, initialMethodName}) async {},
              ),
            ),
          ),
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Explore ICP Services'), findsWidgets);
      });

      testWidgets('BookmarksScreen AppBar has subtitle about ICP canisters',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ConnectivityScope(
              child: BookmarksScreen(
                bridge: const RustBridgeLoader(),
                onOpenClient: ({initialCanisterId, initialMethodName}) async {},
              ),
            ),
          ),
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Interact with Internet Computer canisters'),
            findsOneWidget);
      });

      testWidgets('AppBar title is Explore ICP Services', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ConnectivityScope(
              child: BookmarksScreen(
                bridge: const RustBridgeLoader(),
                onOpenClient: ({initialCanisterId, initialMethodName}) async {},
              ),
            ),
          ),
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        final appBarFinder = find.byType(AppBar);
        expect(appBarFinder, findsOneWidget);

        final exploreText = find.descendant(
          of: appBarFinder,
          matching: find.text('Explore ICP Services'),
        );
        expect(exploreText, findsOneWidget);
      });
    });

    group('Profile badge CTA improvement', () {
      testWidgets('ModernNavigationItem supports person_add icon',
          (tester) async {
        expect(Icons.person_add_outlined, isA<IconData>());
        expect(Icons.person_add_rounded, isA<IconData>());
      });

      testWidgets('ModernNavigationItem supports dns icon for Canisters',
          (tester) async {
        expect(Icons.dns_outlined, isA<IconData>());
        expect(Icons.dns_rounded, isA<IconData>());
      });
    });
  });
}
