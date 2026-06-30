import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/welcome_onboarding_screen.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('WelcomeOnboardingScreen', () {
    Widget createTestApp() {
      return const MaterialApp(
        home: WelcomeOnboardingScreen(),
      );
    }

    testWidgets('displays welcome message', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Welcome to ICP Autorun'), findsOneWidget);
    });

    testWidgets('displays app description', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Create and run TypeScript scripts that interact with ICP canisters'),
        findsOneWidget,
      );
      expect(
        find.text('Browse the marketplace or write your own'),
        findsOneWidget,
      );
    });

    testWidgets('displays feature list', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Write Scripts'), findsOneWidget);
      expect(find.text('Run Locally'), findsOneWidget);
    });

    testWidgets('displays Get Started button', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('displays Skip option', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('Get Started returns correct result', (tester) async {
      OnboardingResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<OnboardingResult>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => const WelcomeOnboardingScreen(),
                    ),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Get Started'));
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(result, equals(OnboardingResult.getStarted));
    });

    testWidgets('Skip returns correct result', (tester) async {
      OnboardingResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<OnboardingResult>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => const WelcomeOnboardingScreen(),
                    ),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(result, equals(OnboardingResult.skipped));
    });

    testWidgets('Browse Marketplace button returns correct result',
        (tester) async {
      OnboardingResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<OnboardingResult>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => const WelcomeOnboardingScreen(),
                    ),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      final browseButtons =
          find.widgetWithText(ModernButton, 'Browse Marketplace');
      await tester.ensureVisible(browseButtons);
      await tester.tap(browseButtons);
      await tester.pumpAndSettle();

      expect(result, equals(OnboardingResult.browseMarketplace));
    });
  });
}
