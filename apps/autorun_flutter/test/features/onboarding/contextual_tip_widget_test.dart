import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/contextual_tip_service.dart';
import 'package:icp_autorun/widgets/contextual_tip.dart';

void main() {
  group('ContextualTip Widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows child when tip should not display', (tester) async {
      // Mark tip as seen so it won't show
      final service = ContextualTipService();
      await service.markTipSeen(ContextualTipFeature.scriptsView);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.scriptsView,
            child: const Text('Child Content'),
          ),
        ),
      ));

      // Wait for async loading
      await tester.pumpAndSettle();

      // Child should be visible
      expect(find.text('Child Content'), findsOneWidget);
      // Tip should not be visible
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsNothing);
    });

    testWidgets('shows tip banner when first visiting feature', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.scriptsView,
            child: const Text('Child Content'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // Both tip and child should be visible
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsOneWidget);
      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('dismisses tip when close button tapped', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.scriptsView,
            child: const Text('Child Content'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // Tip should be visible
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsOneWidget);

      // Tap dismiss button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tip should be gone, child remains
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsNothing);
      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('dismissal persists - tip does not show again', (tester) async {
      // First, show and dismiss
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.scriptEditor,
            child: const Text('Child Content'),
          ),
        ),
      ));

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Remount - tip should not show
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.scriptEditor,
            child: const Text('Child Content'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsNothing);
      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('calls onDismiss callback when dismissed', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContextualTip(
            feature: ContextualTipFeature.exploreView,
            onDismiss: () => dismissed = true,
            child: const Text('Child Content'),
          ),
        ),
      ));

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });

  group('InlineContextualTip Widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('is invisible when tip should not display', (tester) async {
      final service = ContextualTipService();
      await service.markTipSeen(ContextualTipFeature.marketplace);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              InlineContextualTip(
                feature: ContextualTipFeature.marketplace,
              ),
              const Text('Other Content'),
            ],
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // Only other content visible
      expect(find.text('Other Content'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });

    testWidgets('shows inline tip when first visiting feature', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              InlineContextualTip(
                feature: ContextualTipFeature.marketplace,
              ),
              const Text('Other Content'),
            ],
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // Tip icon should be visible
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(find.text('Other Content'), findsOneWidget);
    });

    testWidgets('dismisses inline tip when close button tapped',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              InlineContextualTip(
                feature: ContextualTipFeature.marketplace,
              ),
              const Text('Other Content'),
            ],
          ),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(find.text('Other Content'), findsOneWidget);
    });
  });
}
