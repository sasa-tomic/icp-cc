import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

void main() {
  group('ScriptsScreen featured section', () {
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

    testWidgets('screen has proper layout structure', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Scripts'), findsOneWidget);
    });

    testWidgets('search bar is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('filter button is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('FAB is present for creating new scripts', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('handles loading and empty states gracefully', (tester) async {
      await pumpScriptsScreen(tester);
      await tester.pump(const Duration(seconds: 3));

      final hasProgressIndicator =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasEmptyState =
          find.text('Your Script Library is Empty').evaluate().isNotEmpty;

      expect(hasProgressIndicator || hasEmptyState, isTrue);
    });

    testWidgets('no featured scripts carousel is shown', (tester) async {
      await pumpScriptsScreen(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Featured'), findsNothing);
    });

    testWidgets('no horizontal scrolling featured section', (tester) async {
      await pumpScriptsScreen(tester);
      await tester.pump(const Duration(seconds: 3));

      final horizontalScrollables = find
          .byWidgetPredicate((widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal)
          .evaluate();

      expect(horizontalScrollables.isEmpty, isTrue);
    });
  });
}
