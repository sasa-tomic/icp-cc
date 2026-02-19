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

    testWidgets('shows source filter chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.widgetWithText(FilterChip, 'All'), findsWidgets);
      expect(find.widgetWithText(FilterChip, 'Local'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Marketplace'), findsOneWidget);
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

    testWidgets('shows sort dropdown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.textContaining('Sort'), findsOneWidget);
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
  });
}
