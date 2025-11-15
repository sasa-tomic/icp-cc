import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScriptsScreen', () {
    setUpAll(() async {
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
    });

    Widget createWidget() {
      return MaterialApp(
        home: ScriptsScreen(),
      );
    }

    group('basic UI', () {
      testWidgets('should display scripts screen', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(ScriptsScreen), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('New script'), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);
      });

      testWidgets('should show empty state initially', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.text('No scripts yet'), findsOneWidget);
        expect(find.text('Create your first script to get started'), findsOneWidget);
        expect(find.byIcon(Icons.code), findsOneWidget);
      });
    });

    group('floating action button', () {
      testWidgets('should show FAB with correct text and icon', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('New script'), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);
      });

      testWidgets('should open script creation when FAB is tapped', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(Dialog), findsOneWidget);
      });
    });

    group('app bar', () {
      testWidgets('should have app bar', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(AppBar), findsOneWidget);
      });
    });

    group('refresh functionality', () {
      testWidgets('should have refresh indicator', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(RefreshIndicator), findsOneWidget);
      });
    });

    group('error handling', () {
      testWidgets('should handle errors gracefully', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Assert - Should not crash
        expect(find.byType(ScriptsScreen), findsOneWidget);
      });
    });
  });
}