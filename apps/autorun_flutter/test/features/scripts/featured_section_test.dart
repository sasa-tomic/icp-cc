import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';

void main() {
  group('ScriptsScreen featured section', () {
    testWidgets('screen has proper layout structure', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Scripts'), findsOneWidget);
    });

    testWidgets('search bar is present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('filter button is present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('FAB is present for creating new scripts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('handles loading and empty states gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final hasProgressIndicator =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasEmptyState =
          find.text('Your Script Library is Empty').evaluate().isNotEmpty;

      expect(hasProgressIndicator || hasEmptyState, isTrue);
    });
  });
}
