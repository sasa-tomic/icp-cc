import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';
import 'package:icp_autorun/theme/modern_components.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Empty State Secondary Action (TODO #13)', () {
    /// Verifies ModernEmptyState supports a secondary ("Browse Marketplace")
    /// action alongside the primary ("Create Script") action, using the ghost
    /// button variant — the ScriptsScreen library empty-state relies on this.
    testWidgets('renders both primary and secondary actions', (tester) async {
      await pumpInScaffold(
        tester,
        ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Create your first script or browse the marketplace',
          action: () {},
          actionLabel: 'Create Script',
          secondaryAction: () {},
          secondaryActionLabel: 'Browse Marketplace',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Your Script Library is Empty'), findsOneWidget);
      expect(find.text('Create Script'), findsOneWidget);
      expect(find.text('Browse Marketplace'), findsOneWidget);
    });

    testWidgets('secondary action uses ghost button variant', (tester) async {
      await pumpInScaffold(
        tester,
        ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Create your first script or browse the marketplace',
          action: () {},
          actionLabel: 'Create Script',
          secondaryAction: () {},
          secondaryActionLabel: 'Browse Marketplace',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.ghost,
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping secondary action fires only the secondary callback',
        (tester) async {
      bool primaryCalled = false;
      bool secondaryCalled = false;

      await pumpInScaffold(
        tester,
        ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Create your first script or browse the marketplace',
          action: () => primaryCalled = true,
          actionLabel: 'Create Script',
          secondaryAction: () => secondaryCalled = true,
          secondaryActionLabel: 'Browse Marketplace',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.ghost,
        ),
      );
      await tester.pump();

      expect(primaryCalled, isFalse);
      expect(secondaryCalled, isTrue);
    });

    testWidgets('primary action uses primary button variant', (tester) async {
      await pumpInScaffold(
        tester,
        ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Create your first script or browse the marketplace',
          action: () {},
          actionLabel: 'Create Script',
          secondaryAction: () {},
          secondaryActionLabel: 'Browse Marketplace',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.primary,
        ),
        findsOneWidget,
      );
    });
  });
}
