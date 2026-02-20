import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/post_setup_guide.dart';

void main() {
  group('PostSetupGuide', () {
    testWidgets('renders all three action tiles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (_) {},
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Getting Started'), findsOneWidget);
      expect(find.text('Browse the Marketplace'), findsOneWidget);
      expect(find.text('Create Your First Script'), findsOneWidget);
      expect(find.text('Explore Canisters'), findsOneWidget);
    });

    testWidgets('shows Dont show again button when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (_) {},
                onDismiss: () {},
                showDontShowAgain: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text("Don't show again"), findsOneWidget);
    });

    testWidgets('hides Dont show again button when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (_) {},
                onDismiss: () {},
                showDontShowAgain: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text("Don't show again"), findsNothing);
    });

    testWidgets('calls onActionSelected with browseMarketplace when tapped',
        (tester) async {
      PostSetupAction? selectedAction;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (action) => selectedAction = action,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Browse the Marketplace'));
      await tester.pump();

      expect(selectedAction, PostSetupAction.browseMarketplace);
    });

    testWidgets('calls onActionSelected with createScript when tapped',
        (tester) async {
      PostSetupAction? selectedAction;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (action) => selectedAction = action,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create Your First Script'));
      await tester.pump();

      expect(selectedAction, PostSetupAction.createScript);
    });

    testWidgets('calls onActionSelected with exploreCanisters when tapped',
        (tester) async {
      PostSetupAction? selectedAction;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (action) => selectedAction = action,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Explore Canisters'));
      await tester.pump();

      expect(selectedAction, PostSetupAction.exploreCanisters);
    });

    testWidgets('calls onDismiss when Dont show again is tapped',
        (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostSetupGuide(
                onActionSelected: (_) {},
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.text("Don't show again"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't show again"));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('dialog can be dismissed with Maybe Later', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => PostSetupGuide(
                        onActionSelected: (_) {},
                        onDismiss: () {},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Getting Started'), findsOneWidget);

      await tester.ensureVisible(find.text('Maybe Later'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maybe Later'));
      await tester.pumpAndSettle();

      expect(find.text('Getting Started'), findsNothing);
    });
  });
}
