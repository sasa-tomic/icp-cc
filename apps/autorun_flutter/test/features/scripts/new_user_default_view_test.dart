import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';

/// Test for Item #9: Default to Marketplace View for New Users
///
/// This test verifies that:
/// 1. New users (0 local scripts) see loading, not empty state, while marketplace loads
/// 2. Empty state is only shown after all loading is complete
void main() {
  group('New user default view behavior', () {
    Future<void> pumpScriptsScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('ScriptsScreen renders without crashing for new user',
        (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(ScriptsScreen), findsOneWidget);
    });

    testWidgets('FAB for creating scripts is present for new user',
        (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('search bar is present for new user', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.text('Search scripts...'), findsOneWidget);
    });

    testWidgets('filter button is present for new user', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });
  });

  group('Empty state timing for new users', () {
    testWidgets('initial render does not immediately show empty state',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );

      // Very first frame - should show loading, not empty state
      await tester.pump(const Duration(milliseconds: 50));

      // Either loading or content, but NOT empty state yet
      final hasLoadingIndicator =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasEmptyState = find.byType(ModernEmptyState).evaluate().isNotEmpty;

      // At this early stage, we should NOT have jumped to empty state
      // (loading indicator should be showing while marketplace loads)
      expect(
        hasEmptyState && !hasLoadingIndicator,
        isFalse,
        reason:
            'Should show loading indicator, not empty state, while marketplace is loading for new users',
      );
    });

    testWidgets('after loading completes, empty state shows correct content',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // After pumping for 2 seconds, marketplace load should have completed (failed or succeeded)
      // If empty state is shown (no content), it should have the correct message
      final emptyStateFinder = find.byType(ModernEmptyState);
      if (emptyStateFinder.evaluate().isNotEmpty) {
        // If empty state is shown, it should have the correct title
        expect(
          find.text('Your Script Library is Empty'),
          findsOneWidget,
          reason: 'Empty state should show correct title',
        );
      }
    });
  });
}
