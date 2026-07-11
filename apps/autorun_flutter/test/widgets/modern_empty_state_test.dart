import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/modern_empty_state.dart';
import 'package:icp_autorun/theme/modern_components.dart';

// Walking the semantics tree uses `pipelineOwner` + `SemanticsNode.hasFlag`,
// the stable test API for semantics introspection. The newer `flagsCollection`
// replacement isn't available in this SDK, so suppress the deprecation here.
// ignore_for_file: deprecated_member_use

void main() {
  group('ModernEmptyState', () {
    Widget createWidget({
      IconData? icon,
      String title = 'Test Title',
      String subtitle = 'Test Subtitle',
      VoidCallback? action,
      String actionLabel = 'Test Action',
      VoidCallback? secondaryAction,
      String secondaryActionLabel = 'Test Secondary',
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ModernEmptyState(
            icon: icon ?? Icons.info,
            title: title,
            subtitle: subtitle,
            action: action,
            actionLabel: actionLabel,
            secondaryAction: secondaryAction,
            secondaryActionLabel: secondaryActionLabel,
          ),
        ),
      );
    }

    group('basic rendering', () {
      testWidgets('should display all required elements',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(action: () {}));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(ModernEmptyState), findsOneWidget);
        expect(find.byIcon(Icons.info), findsOneWidget);
        expect(find.text('Test Title'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);
        expect(find.text('Test Action'), findsOneWidget);
      });

      testWidgets('should not show action button when action is null',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(action: null));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(ModernEmptyState), findsOneWidget);
        expect(find.byIcon(Icons.info), findsOneWidget);
        expect(find.text('Test Title'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);
        expect(find.text('Test Action'), findsNothing);
        expect(find.byType(ModernButton), findsNothing);
      });

      testWidgets('should display provided icon correctly',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(icon: Icons.star));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byIcon(Icons.star), findsOneWidget);
      });
    });

    group('secondary action', () {
      testWidgets('should display secondary action button when provided',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(
          action: () {},
          secondaryAction: () {},
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Test Secondary'), findsOneWidget);
      });

      testWidgets('should not display secondary action when null',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(
          action: () {},
          secondaryAction: null,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Test Secondary'), findsNothing);
      });

      testWidgets('should call secondary action when tapped',
          (WidgetTester tester) async {
        bool primaryCalled = false;
        bool secondaryCalled = false;

        await tester.pumpWidget(createWidget(
          action: () => primaryCalled = true,
          secondaryAction: () => secondaryCalled = true,
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

        expect(primaryCalled, isFalse);
        expect(secondaryCalled, isTrue);
      });

      testWidgets('secondary action button uses ghost variant',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget(
          action: () {},
          secondaryAction: () {},
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final ghostButton = find.byWidgetPredicate(
          (widget) =>
              widget is ModernButton &&
              widget.variant == ModernButtonVariant.ghost,
        );
        expect(ghostButton, findsOneWidget);
      });
    });

    group('interactions', () {
      testWidgets('should call action when button is tapped',
          (WidgetTester tester) async {
        bool actionCalled = false;

        await tester.pumpWidget(createWidget(
          action: () => actionCalled = true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.tap(find.byType(ModernButton));
        await tester.pump();

        expect(actionCalled, isTrue);
      });
    });

    group('accessibility — no doubled announcements (W6-7)', () {
      // W6-7: `Semantics(label: title)` wrapping `Text(title)` made screen
      // readers announce every string TWICE ("No Bookmarks Yet No Bookmarks
      // Yet"). The fix lets the `Text` expose the string once and uses a
      // `container` button wrapper so the action label is set exactly once.
      List<String> collectAllLabels(WidgetTester tester) {
        final root = tester
            .binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        final labels = <String>[];
        bool visit(SemanticsNode node) {
          if (node.label.isNotEmpty) labels.add(node.label);
          node.visitChildren(visit);
          return true;
        }

        visit(root);
        return labels;
      }

      testWidgets('title string is announced exactly once', (tester) async {
        await tester.pumpWidget(createWidget(
          title: 'No Bookmarks Yet',
          action: () {},
        ));
        final handle = tester.ensureSemantics();
        await tester.pumpAndSettle();
        // NOTE: dispose the semantics handle BEFORE the assertions —
        // testWidgets verifies handles were disposed right after the body
        // returns (before addTearDown), so collect first, dispose, then assert.
        final labels = collectAllLabels(tester);
        handle.dispose();

        const title = 'No Bookmarks Yet';
        for (final label in labels) {
          final occurrences = title.allMatches(label).length;
          expect(
            occurrences,
            lessThanOrEqualTo(1),
            reason: 'Title "$title" must not be announced twice within a '
                'single semantics node, but node label was: "$label"',
          );
        }
      });

      testWidgets('subtitle string is announced exactly once', (tester) async {
        await tester.pumpWidget(createWidget(
          subtitle: 'Tap the bookmark icon to save a canister',
          action: () {},
        ));
        final handle = tester.ensureSemantics();
        await tester.pumpAndSettle();
        final labels = collectAllLabels(tester);
        handle.dispose();

        const subtitle = 'Tap the bookmark icon to save a canister';
        for (final label in labels) {
          final occurrences = subtitle.allMatches(label).length;
          expect(
            occurrences,
            lessThanOrEqualTo(1),
            reason: 'Subtitle must not be announced twice within a single '
                'semantics node, but node label was: "$label"',
          );
        }
      });

      testWidgets('action button label is announced exactly once and is a button',
          (tester) async {
        await tester.pumpWidget(createWidget(
          actionLabel: 'Browse Marketplace',
          action: () {},
        ));
        final handle = tester.ensureSemantics();
        await tester.pumpAndSettle();

        const action = 'Browse Marketplace';
        final labels = collectAllLabels(tester);
        // Walk the tree to find the node(s) with this exact label.
        final root = tester
            .binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        final matches = <SemanticsNode>[];
        bool visit(SemanticsNode node) {
          if (node.label == action) matches.add(node);
          node.visitChildren(visit);
          return true;
        }

        visit(root);
        handle.dispose();

        expect(matches, hasLength(1),
            reason: 'action label should appear on exactly one node, '
                'got: $labels');
        expect(matches.single.hasFlag(SemanticsFlag.isButton), isTrue,
            reason: 'the action must be exposed as a button');
        // And no node announces it twice.
        for (final label in labels) {
          expect(action.allMatches(label).length, lessThanOrEqualTo(1));
        }
      });
    });

    group('responsive design', () {
      testWidgets('should adapt to different screen sizes',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidget());
        await tester.pump();

        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(createWidget());
        await tester.pump();

        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
      });
    });
  });
}
