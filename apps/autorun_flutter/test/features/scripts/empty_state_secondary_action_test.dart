import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('Empty State Secondary Action (TODO #13)', () {
    /// This test verifies the ModernEmptyState widget supports secondary actions.
    /// The ScriptsScreen should use this to provide "Browse Marketplace" as
    /// an alternative to "Create Script" for users who want to explore first.
    testWidgets('empty state widget supports secondary action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Create your first script or browse the marketplace',
            action: () {},
            actionLabel: 'Create Script',
            secondaryAction: () {},
            secondaryActionLabel: 'Browse Marketplace',
          ),
        ),
      ));

      // Wait for animations
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Both actions should be visible
      expect(find.text('Your Script Library is Empty'), findsOneWidget);
      expect(find.text('Create Script'), findsOneWidget);
      expect(find.text('Browse Marketplace'), findsOneWidget);
    });

    testWidgets('secondary action uses ghost button variant', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Create your first script or browse the marketplace',
            action: () {},
            actionLabel: 'Create Script',
            secondaryAction: () {},
            secondaryActionLabel: 'Browse Marketplace',
          ),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Secondary action should use ghost variant
      final ghostButton = find.byWidgetPredicate(
        (widget) =>
            widget is ModernButton &&
            widget.variant == ModernButtonVariant.ghost,
      );
      expect(ghostButton, findsOneWidget);
    });

    testWidgets('tapping secondary action triggers callback', (tester) async {
      bool primaryCalled = false;
      bool secondaryCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Create your first script or browse the marketplace',
            action: () => primaryCalled = true,
            actionLabel: 'Create Script',
            secondaryAction: () => secondaryCalled = true,
            secondaryActionLabel: 'Browse Marketplace',
          ),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Tap the ghost button (secondary action)
      final ghostButton = find.byWidgetPredicate(
        (widget) =>
            widget is ModernButton &&
            widget.variant == ModernButtonVariant.ghost,
      );
      await tester.tap(ghostButton);
      await tester.pump();

      // Secondary should be called, primary should NOT
      expect(primaryCalled, isFalse);
      expect(secondaryCalled, isTrue);
    });

    testWidgets('primary action uses primary button variant', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Create your first script or browse the marketplace',
            action: () {},
            actionLabel: 'Create Script',
            secondaryAction: () {},
            secondaryActionLabel: 'Browse Marketplace',
          ),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Primary action should use primary variant
      final primaryButton = find.byWidgetPredicate(
        (widget) =>
            widget is ModernButton &&
            widget.variant == ModernButtonVariant.primary,
      );
      expect(primaryButton, findsOneWidget);
    });
  });
}
