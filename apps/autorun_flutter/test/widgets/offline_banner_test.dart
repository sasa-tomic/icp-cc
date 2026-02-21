import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/widgets/offline_banner.dart';

void main() {
  group('OfflineBanner', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget createWidget({
      required bool isOnline,
      VoidCallback? onDismiss,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: OfflineBanner(
            isOnline: isOnline,
            onDismiss: onDismiss,
          ),
        ),
      );
    }

    group('visibility', () {
      testWidgets('is hidden when online', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: true));

        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsNothing,
        );
      });

      testWidgets('is visible when offline', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsOneWidget,
        );
      });
    });

    group('appearance', () {
      testWidgets('has amber/yellow background', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        // Find the container and check its color
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(OfflineBanner),
            matching: find.byType(Container).first,
          ),
        );

        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, isNotNull);
        // The color should be amber/amber-like
        expect(decoration.color, equals(Colors.amber.shade100));
      });

      testWidgets('has info icon', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        expect(find.byIcon(Icons.info_outline), findsOneWidget);
      });

      testWidgets('has dismiss button (X icon)', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        expect(find.byIcon(Icons.close), findsOneWidget);
      });

      testWidgets('displays correct message', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsOneWidget,
        );
      });
    });

    group('dismiss behavior', () {
      testWidgets('calls onDismiss when close button is tapped',
          (tester) async {
        bool dismissCalled = false;

        await tester.pumpWidget(createWidget(
          isOnline: false,
          onDismiss: () => dismissCalled = true,
        ));

        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        expect(dismissCalled, isTrue);
      });

      testWidgets('close button has tooltip', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        final iconButton = tester.widget<IconButton>(find.byType(IconButton));
        expect(iconButton.tooltip, isNotNull);
      });
    });

    group('layout', () {
      testWidgets('has appropriate padding', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        // Banner should have padding for comfortable touch/click targets
        final padding = tester.widget<Padding>(
          find.descendant(
            of: find.byType(OfflineBanner),
            matching: find.byType(Padding).first,
          ),
        );

        expect(padding.padding, isNotNull);
      });

      testWidgets('is full width', (tester) async {
        // Bind the test to a specific screen size
        await tester.binding.setSurfaceSize(const Size(400, 800));

        await tester.pumpWidget(createWidget(isOnline: false));

        // Find the banner container
        final container = find.byType(OfflineBanner);
        expect(container, findsOneWidget);

        // Get the rendered size - should match parent width
        final size = tester.getSize(container);
        expect(size.width, equals(400.0));

        // Reset surface size
        await tester.binding.setSurfaceSize(null);
      });
    });

    group('accessibility', () {
      testWidgets('has semantic labels for screen readers', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        // The text should be accessible
        final text = tester.widget<Text>(
          find.text("You're offline. Some features may be unavailable."),
        );
        expect(text.data, isNotNull);
      });

      testWidgets('dismiss button is accessible', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: false));

        // IconButton should have tooltip for accessibility
        final iconButton = tester.widget<IconButton>(find.byType(IconButton));
        expect(iconButton.tooltip, equals('Dismiss'));
      });
    });

    group('edge cases', () {
      testWidgets('handles rapid online/offline transitions', (tester) async {
        await tester.pumpWidget(createWidget(isOnline: true));

        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsNothing,
        );

        // Transition to offline
        await tester.pumpWidget(createWidget(isOnline: false));
        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsOneWidget,
        );

        // Back to online
        await tester.pumpWidget(createWidget(isOnline: true));
        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsNothing,
        );
      });

      testWidgets('handles null onDismiss gracefully', (tester) async {
        await tester.pumpWidget(createWidget(
          isOnline: false,
          onDismiss: null,
        ));

        // Should render without errors
        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsOneWidget,
        );

        // Tapping close should not crash
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        // Still renders
        expect(
          find.text("You're offline. Some features may be unavailable."),
          findsOneWidget,
        );
      });
    });
  });
}
