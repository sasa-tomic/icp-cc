import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/spotlight_service.dart';
import 'package:icp_autorun/widgets/spotlight_overlay.dart';

void main() {
  group('SpotlightService', () {
    late SpotlightService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = SpotlightService();
    });

    group('initial state', () {
      test('shouldShowTour returns false for new user (opt-in only)', () async {
        // Tour does NOT auto-start for new users - it's opt-in via Settings
        expect(await service.shouldShowTour(), isFalse);
      });

      test('currentStep returns 0 for new user', () async {
        expect(await service.currentStep(), equals(0));
      });

      test('isCompleted returns false for new user', () async {
        expect(await service.isCompleted(), isFalse);
      });

      test('isDismissed returns false for new user', () async {
        expect(await service.isDismissed(), isFalse);
      });
    });

    group('navigation', () {
      test('nextStep increments current step', () async {
        await service.nextStep();
        expect(await service.currentStep(), equals(1));

        await service.nextStep();
        expect(await service.currentStep(), equals(2));
      });

      test('previousStep decrements current step', () async {
        await service.nextStep();
        await service.nextStep();
        await service.previousStep();
        expect(await service.currentStep(), equals(1));
      });

      test('previousStep does not go below 0', () async {
        await service.previousStep();
        expect(await service.currentStep(), equals(0));
      });

      test('goToStep sets specific step', () async {
        await service.goToStep(3);
        expect(await service.currentStep(), equals(3));
      });

      test('goToStep clamps to valid range', () async {
        await service.goToStep(-1);
        expect(await service.currentStep(), equals(0));

        await service.goToStep(100);
        expect(
            await service.currentStep(), equals(SpotlightService.totalSteps));
      });
    });

    group('completion', () {
      test('completeTour marks tour as completed', () async {
        await service.resetAndStart();
        await service.completeTour();
        expect(await service.isCompleted(), isTrue);
        expect(await service.shouldShowTour(), isFalse);
      });

      test('completeTour sets current step to total steps', () async {
        await service.completeTour();
        expect(
            await service.currentStep(), equals(SpotlightService.totalSteps));
      });
    });

    group('dismissal', () {
      test('dismissTour marks tour as dismissed', () async {
        await service.resetAndStart();
        await service.dismissTour();
        expect(await service.isDismissed(), isTrue);
        expect(await service.shouldShowTour(), isFalse);
      });

      test('dismissTour preserves current step', () async {
        await service.resetAndStart();
        await service.nextStep();
        await service.nextStep();
        await service.dismissTour();
        expect(await service.currentStep(), equals(2));
      });
    });

    group('shouldShowTour logic', () {
      test('returns false if completed', () async {
        await service.resetAndStart();
        await service.completeTour();
        expect(await service.shouldShowTour(), isFalse);
      });

      test('returns false if dismissed', () async {
        await service.resetAndStart();
        await service.dismissTour();
        expect(await service.shouldShowTour(), isFalse);
      });

      test('returns true if explicitly started and not completed or dismissed',
          () async {
        await service.resetAndStart();
        await service.nextStep();
        expect(await service.shouldShowTour(), isTrue);
      });

      test('returns false if not explicitly started', () async {
        await service.nextStep();
        // Even after navigation, tour won't show if not explicitly started
        expect(await service.shouldShowTour(), isFalse);
      });
    });

    group('persistence', () {
      test('state persists across service instances', () async {
        await service.goToStep(2);
        await service.dismissTour();

        final newService = SpotlightService();
        expect(await newService.currentStep(), equals(2));
        expect(await newService.isDismissed(), isTrue);
      });

      test('completion persists across service instances', () async {
        await service.completeTour();

        final newService = SpotlightService();
        expect(await newService.isCompleted(), isTrue);
      });
    });

    group('reset', () {
      test('reset clears all tour state', () async {
        await service.goToStep(3);
        await service.dismissTour();
        await service.resetAndStart();

        expect(await service.currentStep(), equals(0));
        expect(await service.isDismissed(), isFalse);
        expect(await service.isCompleted(), isFalse);
        expect(await service.shouldShowTour(), isTrue);
      });

      test('reset does not auto-start tour (need resetAndStart)', () async {
        await service.goToStep(3);
        await service.dismissTour();
        await service.reset();

        expect(await service.currentStep(), equals(0));
        expect(await service.isDismissed(), isFalse);
        expect(await service.isCompleted(), isFalse);
        // After plain reset, tour is NOT shown (opt-in only)
        expect(await service.shouldShowTour(), isFalse);
      });
    });

    group('resetAndStart', () {
      test('resetAndStart enables tour to show', () async {
        await service.resetAndStart();
        expect(await service.shouldShowTour(), isTrue);
      });

      test('resetAndStart clears previous state and starts fresh', () async {
        await service.goToStep(3);
        await service.completeTour();
        await service.resetAndStart();

        expect(await service.currentStep(), equals(0));
        expect(await service.isCompleted(), isFalse);
        expect(await service.isDismissed(), isFalse);
        expect(await service.shouldShowTour(), isTrue);
      });
    });

    group('step info', () {
      test('getStepInfo returns valid info for all steps', () {
        for (var i = 0; i < SpotlightService.totalSteps; i++) {
          final info = service.getStepInfo(i);
          expect(info.title, isNotEmpty);
          expect(info.description, isNotEmpty);
          expect(info.targetKey, isNotEmpty);
        }
      });

      test('getStepInfo throws for invalid step', () {
        expect(
          () => service.getStepInfo(-1),
          throwsA(isA<RangeError>()),
        );
      });
    });
  });

  group('SpotlightStep', () {
    test('creates with all required fields', () {
      const step = SpotlightStep(
        targetKey: 'home_tab',
        title: 'Welcome',
        description: 'This is your home',
        position: SpotlightPosition.bottom,
      );

      expect(step.targetKey, equals('home_tab'));
      expect(step.title, equals('Welcome'));
      expect(step.description, equals('This is your home'));
      expect(step.position, equals(SpotlightPosition.bottom));
    });
  });

  group('SpotlightOverlay widget', () {
    testWidgets('renders with correct title and description', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Test Title',
              description: 'Test Description',
              currentPosition: SpotlightPosition.bottom,
              onNext: null,
              onBack: null,
              onDismiss: null,
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);
    });

    testWidgets('shows Next button when onNext is provided', (tester) async {
      var nextPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Test',
              description: 'Test',
              currentPosition: SpotlightPosition.bottom,
              onNext: () => nextPressed = true,
              onBack: null,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Next'));
      await tester.pump();

      expect(nextPressed, isTrue);
    });

    testWidgets('shows Skip button when onDismiss is provided', (tester) async {
      var dismissPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Test',
              description: 'Test',
              currentPosition: SpotlightPosition.bottom,
              onNext: null,
              onBack: null,
              onDismiss: () => dismissPressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pump();

      expect(dismissPressed, isTrue);
    });

    testWidgets('shows Back button when onBack is provided', (tester) async {
      var backPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Test',
              description: 'Test',
              currentPosition: SpotlightPosition.bottom,
              onNext: null,
              onBack: () => backPressed = true,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Back'));
      await tester.pump();

      expect(backPressed, isTrue);
    });

    testWidgets('shows Done button on last step instead of Next',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Final Step',
              description: 'You are done!',
              currentPosition: SpotlightPosition.bottom,
              isLastStep: true,
              onNext: null,
              onBack: null,
              onDismiss: null,
            ),
          ),
        ),
      );

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('shows step indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpotlightOverlay(
              title: 'Test',
              description: 'Test',
              currentPosition: SpotlightPosition.bottom,
              stepNumber: 2,
              totalSteps: 5,
              onNext: null,
              onBack: null,
              onDismiss: null,
            ),
          ),
        ),
      );

      expect(find.text('2 of 5'), findsOneWidget);
    });
  });
}
