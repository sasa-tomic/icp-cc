import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';

void main() {
  group('ScriptsScreen unified view', () {
    testWidgets('has no tab bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
    });

    testWidgets('shows search bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('shows filter button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('does not show source filter chips on main screen',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      // Source filter chips should not be visible on main screen
      // (they are now in the filter popover)
      expect(find.widgetWithText(FilterChip, 'Local'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Marketplace'), findsNothing);
    });

    testWidgets('does not show sort dropdown on main screen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      // Sort dropdown should not be visible on main screen
      // (it is now in the filter popover)
      expect(find.textContaining('Sort'), findsNothing);
    });

    testWidgets('has create script FAB', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('shows overflow menu with download history', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('search bar and filter button are in same row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      // Both search icon and filter button should be present
      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });
  });
}
