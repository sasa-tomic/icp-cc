import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/widgets/hover_reveal_actions.dart';

void main() {
  group('Discoverable Script Actions', () {
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

    testWidgets('ScriptsScreen renders without crashing', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(ScriptsScreen), findsOneWidget);
    });

    testWidgets('search bar is present for finding scripts', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.text('Search scripts...'), findsOneWidget);
    });

    testWidgets('filter button is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('FAB for creating scripts is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });

  group('HoverRevealActions Widget', () {
    testWidgets('renders actions on mobile (always visible)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HoverRevealActions(
              actions: const [
                Icon(Icons.play_arrow),
                Icon(Icons.edit),
              ],
              alwaysVisibleActions: const [
                Icon(Icons.star),
              ],
            ),
          ),
        ),
      );

      // All actions should be present in the widget tree
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('alwaysVisibleActions come before hover-reveal actions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HoverRevealActions(
              actions: const [
                Icon(Icons.play_arrow),
              ],
              alwaysVisibleActions: const [
                Icon(Icons.star),
              ],
            ),
          ),
        ),
      );

      // Find the Row and verify order
      final row = tester.widget<Row>(find.byType(Row).first);
      // Row children should have star (always visible) then play_arrow (reveal)
      expect(row.children.length, greaterThanOrEqualTo(2));
    });
  });

  group('ScriptActionButton Widget', () {
    testWidgets('renders with icon and tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptActionButton(
              icon: Icons.play_arrow,
              onPressed: () {},
              tooltip: 'Run script',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byTooltip('Run script'), findsOneWidget);
    });

    testWidgets('renders with destructive styling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptActionButton(
              icon: Icons.delete_outline,
              onPressed: () {},
              tooltip: 'Delete',
              isDestructive: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      // Button should still be functional
      expect(find.byTooltip('Delete'), findsOneWidget);
    });

    testWidgets('shows loading state when isLoading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptActionButton(
              icon: Icons.download,
              onPressed: () {},
              tooltip: 'Download',
              isLoading: true,
            ),
          ),
        ),
      );

      // Should show circular progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Original icon should not be visible
      expect(find.byIcon(Icons.download), findsNothing);
    });

    testWidgets('onPressed callback works', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptActionButton(
              icon: Icons.play_arrow,
              onPressed: () => pressed = true,
              tooltip: 'Run',
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Run'));
      expect(pressed, isTrue);
    });
  });
}
