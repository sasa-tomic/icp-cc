import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/quick_profile_creation_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuickProfileCreationDialog', () {
    group('UI Elements', () {
      testWidgets('displays "What\'s your name?" prompt', (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text("What's your name?"), findsOneWidget);
      });

      testWidgets('displays name input field', (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Your name'), findsOneWidget);
      });

      testWidgets('displays Continue button', (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Continue'), findsOneWidget);
      });

      testWidgets('displays skip option', (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Skip'), findsOneWidget);
      });
    });

    group('Button Behavior', () {
      testWidgets('Continue button is disabled when name is empty',
          (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        final button = find.widgetWithText(FilledButton, 'Continue');
        expect(button, findsOneWidget);

        final filledButton = tester.widget<FilledButton>(button);
        expect(filledButton.onPressed, isNull);
      });

      testWidgets('Continue button is enabled when name is provided',
          (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Test User');
        await tester.pump();

        final button = find.widgetWithText(FilledButton, 'Continue');
        final filledButton = tester.widget<FilledButton>(button);
        expect(filledButton.onPressed, isNotNull);
      });
    });

    group('Profile Creation', () {
      testWidgets('returns profile with display name when Continue is tapped',
          (tester) async {
        QuickProfileCreationResult? result;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<QuickProfileCreationResult>(
                    context: context,
                    builder: (context) => const QuickProfileCreationDialog(),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Launch'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Alice');
        await tester.pump();

        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.profileName, equals('Alice'));
        expect(result!.skipped, isFalse);
      });

      testWidgets('returns skipped result when Skip is tapped', (tester) async {
        QuickProfileCreationResult? result;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<QuickProfileCreationResult>(
                    context: context,
                    builder: (context) => const QuickProfileCreationDialog(),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Launch'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Skip'));
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.skipped, isTrue);
      });
    });

    group('Subtext', () {
      testWidgets('explains account registration is optional', (tester) async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: QuickProfileCreationDialog(),
          ),
        ));
        await tester.pumpAndSettle();

        // Should explain that account registration is optional/deferred
        expect(find.textContaining('account'), findsOneWidget);
      });
    });
  });
}
