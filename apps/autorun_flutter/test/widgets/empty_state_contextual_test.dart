import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('EmptyStateContextualGuidance', () {
    group('ScriptsScreen empty state', () {
      testWidgets('shows contextual title for empty script library',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.code_rounded,
              title: 'Your Script Library is Empty',
              subtitle:
                  'Create your first script or browse the marketplace to get started',
              action: () {},
              actionLabel: 'Create Script',
              secondaryAction: () {},
              secondaryActionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Your Script Library is Empty'), findsOneWidget);
        expect(
            find.text(
                'Create your first script or browse the marketplace to get started'),
            findsOneWidget);
        expect(find.text('Create Script'), findsOneWidget);
        expect(find.text('Browse Marketplace'), findsOneWidget);
      });

      testWidgets('shows different subtitle when marketplace has scripts',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.code_rounded,
              title: 'Your Script Library is Empty',
              subtitle:
                  'Download scripts from the marketplace or create your own',
              action: () {},
              actionLabel: 'Create Script',
              secondaryAction: () {},
              secondaryActionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(
            find.text(
                'Download scripts from the marketplace or create your own'),
            findsOneWidget);
      });

      testWidgets('primary action triggers create script', (tester) async {
        bool createActionCalled = false;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.code_rounded,
              title: 'Your Script Library is Empty',
              subtitle:
                  'Create your first script or browse the marketplace to get started',
              action: () => createActionCalled = true,
              actionLabel: 'Create Script',
              secondaryAction: () {},
              secondaryActionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final primaryButtons = find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.primary,
        );
        await tester.tap(primaryButtons);
        await tester.pump();

        expect(createActionCalled, isTrue);
      });

      testWidgets('secondary action triggers browse marketplace',
          (tester) async {
        bool browseActionCalled = false;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.code_rounded,
              title: 'Your Script Library is Empty',
              subtitle:
                  'Create your first script or browse the marketplace to get started',
              action: () {},
              actionLabel: 'Create Script',
              secondaryAction: () => browseActionCalled = true,
              secondaryActionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final ghostButtons = find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.ghost,
        );
        await tester.tap(ghostButtons);
        await tester.pump();

        expect(browseActionCalled, isTrue);
      });
    });

    group('BookmarksScreen empty state', () {
      testWidgets('shows contextual title and subtitle', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No Bookmarks Yet',
              subtitle: 'Save your favorite canister methods for quick access',
              action: () {},
              actionLabel: 'Explore Popular Canisters',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('No Bookmarks Yet'), findsOneWidget);
        expect(
            find.text('Save your favorite canister methods for quick access'),
            findsOneWidget);
        expect(find.text('Explore Popular Canisters'), findsOneWidget);
      });

      testWidgets('action triggers scroll to popular section', (tester) async {
        bool exploreActionCalled = false;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No Bookmarks Yet',
              subtitle: 'Save your favorite canister methods for quick access',
              action: () => exploreActionCalled = true,
              actionLabel: 'Explore Popular Canisters',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.tap(find.text('Explore Popular Canisters'));
        await tester.pump();

        expect(exploreActionCalled, isTrue);
      });
    });

    group('DownloadHistory empty state', () {
      testWidgets('shows contextual title and subtitle', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.download_for_offline_rounded,
              title: 'No Download History',
              subtitle:
                  'Scripts you download from the marketplace will appear here',
              action: () {},
              actionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('No Download History'), findsOneWidget);
        expect(
            find.text(
                'Scripts you download from the marketplace will appear here'),
            findsOneWidget);
        expect(find.text('Browse Marketplace'), findsOneWidget);
      });

      testWidgets('action triggers browse marketplace navigation',
          (tester) async {
        bool browseActionCalled = false;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ModernEmptyState(
              icon: Icons.download_for_offline_rounded,
              title: 'No Download History',
              subtitle:
                  'Scripts you download from the marketplace will appear here',
              action: () => browseActionCalled = true,
              actionLabel: 'Browse Marketplace',
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.tap(find.text('Browse Marketplace'));
        await tester.pump();

        expect(browseActionCalled, isTrue);
      });
    });
  });
}
