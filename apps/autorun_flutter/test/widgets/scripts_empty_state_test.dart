import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/theme/modern_components.dart';
import 'package:icp_autorun/widgets/scripts_empty_state.dart';

void main() {
  group('ScriptsEmptyState library CTAs (UX-H2)', () {
    Widget buildHarness({
      required bool hasProfile,
      VoidCallback? onCreateScript,
      VoidCallback? onBrowseMarketplace,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ScriptsEmptyState(
            kind: ScriptsEmptyStateKind.library,
            hasProfile: hasProfile,
            onCreateScript: onCreateScript,
            onBrowseMarketplace: onBrowseMarketplace,
          ),
        ),
      );
    }

    testWidgets('Browse Marketplace is the primary CTA when a profile exists',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildHarness(
        hasProfile: true,
        onCreateScript: () {},
        onBrowseMarketplace: () {},
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      final Finder primary = find.byWidgetPredicate(
        (w) => w is ModernButton && w.variant == ModernButtonVariant.primary,
      );
      expect(primary, findsOneWidget,
          reason: 'exactly one primary button should be on screen');

      final ModernButton primaryButton = tester.widget(primary);
      final Text label = primaryButton.child! as Text;
      expect(label.data, 'Browse Marketplace');

      final Finder secondary = find.byWidgetPredicate(
        (w) => w is ModernButton && w.variant == ModernButtonVariant.ghost,
      );
      expect(secondary, findsOneWidget);
      final ModernButton secondaryButton = tester.widget(secondary);
      expect((secondaryButton.child! as Text).data, 'Create Script');
    });

    testWidgets('primary Browse Marketplace fires onBrowseMarketplace',
        (WidgetTester tester) async {
      bool browse = false;
      bool create = false;
      await tester.pumpWidget(buildHarness(
        hasProfile: true,
        onCreateScript: () => create = true,
        onBrowseMarketplace: () => browse = true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      final Finder primary = find.byWidgetPredicate(
        (w) => w is ModernButton && w.variant == ModernButtonVariant.primary,
      );
      await tester.tap(primary);
      await tester.pump();

      expect(browse, isTrue);
      expect(create, isFalse);
    });
  });

  group('ScriptsEmptyState favorites-filter label (LOW-1)', () {
    testWidgets('uses "Browse Marketplace" not "Browse Scripts"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptsEmptyState(
              kind: ScriptsEmptyStateKind.favoritesFilter,
              onClearFavoritesFilter: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Browse Marketplace'), findsOneWidget);
      expect(find.text('Browse Scripts'), findsNothing);
    });
  });
}
