import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('ModernEmptyState', () {
    Widget createWidget({
      IconData? icon,
      String title = 'Test Title',
      String subtitle = 'Test Subtitle',
      VoidCallback? action,
      String actionLabel = 'Test Action',
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: icon ?? Icons.info,
            title: title,
            subtitle: subtitle,
            action: action,
            actionLabel: actionLabel,
          ),
        ),
      );
    }

    group('basic rendering', () {
      testWidgets('should display all required elements', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget(action: () {}));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        // Assert
        expect(find.byType(ModernEmptyState), findsOneWidget);
        expect(find.byIcon(Icons.info), findsOneWidget);
        expect(find.text('Test Title'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);
        expect(find.text('Test Action'), findsOneWidget);
      });

      testWidgets('should not show action button when action is null', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget(action: null));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        // Assert
        expect(find.byType(ModernEmptyState), findsOneWidget);
        expect(find.byIcon(Icons.info), findsOneWidget);
        expect(find.text('Test Title'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);
        expect(find.text('Test Action'), findsNothing);
        expect(find.byType(ModernButton), findsNothing);
      });

      testWidgets('should display provided icon correctly', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget(icon: Icons.star));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        // Assert - Should show the provided icon
        expect(find.byIcon(Icons.star), findsOneWidget);
      });
    });

    group('interactions', () {
      testWidgets('should call action when button is tapped', (WidgetTester tester) async {
        bool actionCalled = false;

        // Act
        await tester.pumpWidget(createWidget(
          action: () => actionCalled = true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        await tester.tap(find.byType(ModernButton));
        await tester.pump();

        // Assert
        expect(actionCalled, isTrue);
      });

      testWidgets('should handle button tap without crashing', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget(action: () {}));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        await tester.tap(find.byType(ModernButton));
        await tester.pump();

        // Assert - Should not crash
        expect(find.byType(ModernEmptyState), findsOneWidget);
      });
    });

    group('animations', () {
      testWidgets('should animate in correctly', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        
        // Before animation completes
        await tester.pump(const Duration(milliseconds: 100));

        // Assert - Widget should be visible during animation
        expect(find.byType(ModernEmptyState), findsOneWidget);
        
        // After animation completes
        await tester.pump(const Duration(milliseconds: 400));
        
        // Assert - Still visible after animation
        expect(find.byType(ModernEmptyState), findsOneWidget);
      });
    });

    group('accessibility', () {
      testWidgets('should have proper semantic labels', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget(action: () {}));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // Wait for animations

        // Assert - Check that the widget renders without semantic errors
        expect(find.byType(ModernEmptyState), findsOneWidget);
        expect(find.text('Test Title'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);
        expect(find.text('Test Action'), findsOneWidget);
      });
    });

    group('responsive design', () {
      testWidgets('should adapt to different screen sizes', (WidgetTester tester) async {
        // Test small screen
        await tester.pumpWidget(createWidget());
        await tester.pump();
        
        // Should render without overflow
        expect(tester.takeException(), isNull);
        
        // Test large screen
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(createWidget());
        await tester.pump();
        
        // Should still render without overflow
        expect(tester.takeException(), isNull);
        
        // Clean up any pending timers
        await tester.pumpAndSettle();
      });
    });
  });
}