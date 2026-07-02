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
