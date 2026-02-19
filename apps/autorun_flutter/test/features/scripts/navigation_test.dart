import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';

void main() {
  group('ScriptsScreen navigation', () {
    testWidgets('AppBar contains overflow menu button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('overflow menu contains Download History item', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();

      expect(find.text('Download History'), findsOneWidget);
    });

    testWidgets(
        'overflow menu displays history icon with Download History text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();

      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('Download History'), findsOneWidget);
    });

    testWidgets('has no tab bar (flattened UI)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
    });
  });
}
