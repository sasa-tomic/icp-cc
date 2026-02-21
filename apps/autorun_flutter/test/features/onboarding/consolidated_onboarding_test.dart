import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';
import 'package:icp_autorun/services/onboarding_progress_service.dart';
import 'package:icp_autorun/services/spotlight_service.dart';

/// Consolidated Onboarding Tests
///
/// These tests verify that the streamlined onboarding flow works correctly:
/// 1. First launch: QuickProfileCreationDialog (name entry)
/// 2. After profile created: Show main app immediately (no dialogs!)
/// 3. PostSetupGuide delayed until 5s OR first meaningful action
/// 4. SpotlightTour: Only trigger from "Restart Tour" in Settings
/// 5. GettingStartedCard: Only show AFTER first script interaction
void main() {
  group('Consolidated Onboarding Flow', () {
    late OnboardingService onboardingService;
    late OnboardingProgressService progressService;
    late SpotlightService spotlightService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onboardingService = OnboardingService();
      progressService = OnboardingProgressService();
      spotlightService = SpotlightService();
    });

    group('Phase 1: First Launch', () {
      test(
          'shows QuickProfileCreationDialog when no profiles and no scripts exist',
          () async {
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(shouldShow, isTrue,
            reason:
                'First-time users with no profiles should see QuickProfileCreationDialog');
      });

      test('does NOT show onboarding when profiles already exist', () async {
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: true,
          hasScripts: false,
        );

        expect(shouldShow, isFalse,
            reason:
                'Users with existing profiles should NOT see QuickProfileCreationDialog');
      });
    });

    group('Phase 2: After Profile Creation', () {
      test('PostSetupGuide is NOT ready immediately after profile creation',
          () async {
        // User just created profile - hasn't seen app yet
        final ready = await onboardingService.isPostSetupGuideReady();

        expect(ready, isFalse,
            reason:
                'PostSetupGuide should NOT show immediately after profile creation');
      });

      test('GettingStartedCard is NOT shown immediately after profile creation',
          () async {
        // User just created profile - no script interaction yet
        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();

        expect(hasInteraction, isFalse,
            reason:
                'GettingStartedCard should NOT show without script interaction');
      });

      test('SpotlightTour does NOT auto-start for new users', () async {
        // Spotlight should NOT auto-start - it's opt-in via Settings only
        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isFalse,
            reason: 'SpotlightTour should NOT auto-start. '
                'It should only be triggered from "Restart Tour" in Settings');
      });
    });

    group('Phase 3: PostSetupGuide Timing', () {
      test('becomes ready after first meaningful action', () async {
        await onboardingService.recordFirstMeaningfulAction();

        final ready = await onboardingService.isPostSetupGuideReady();

        expect(ready, isTrue,
            reason:
                'PostSetupGuide should be ready after first meaningful action');
      });

      test('becomes ready after 5 second delay', () async {
        await onboardingService.markAppUsable();

        // Simulate 5+ seconds passing
        final prefs = await SharedPreferences.getInstance();
        final fiveSecondsAgo = DateTime.now()
            .subtract(const Duration(seconds: 5))
            .millisecondsSinceEpoch;
        await prefs.setInt('app_usable_since', fiveSecondsAgo);

        final ready = await onboardingService.isPostSetupGuideReady();

        expect(ready, isTrue,
            reason: 'PostSetupGuide should be ready after 5 second delay');
      });
    });

    group('Phase 4: GettingStartedCard Timing', () {
      test('does NOT show before first script interaction', () async {
        // Even if user has done other things, no GettingStartedCard yet
        await onboardingService.markAppUsable();
        await onboardingService.recordFirstMeaningfulAction();

        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final shouldShowGuide = await progressService.shouldShowGuide();

        // Guide logic should require script interaction
        final shouldShowCard = shouldShowGuide && hasInteraction;

        expect(shouldShowCard, isFalse,
            reason:
                'GettingStartedCard should NOT show without script interaction');
      });

      test('shows AFTER first script interaction', () async {
        // User creates/views their first script
        await progressService.recordFirstScriptInteraction();

        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final shouldShowGuide = await progressService.shouldShowGuide();

        // Now the card can show
        final shouldShowCard = shouldShowGuide && hasInteraction;

        expect(shouldShowCard, isTrue,
            reason:
                'GettingStartedCard should show after first script interaction');
      });

      test('records script interaction persistently', () async {
        await progressService.recordFirstScriptInteraction();

        // Create new service instance
        final newService = OnboardingProgressService();
        final hasInteraction = await newService.hasHadFirstScriptInteraction();

        expect(hasInteraction, isTrue,
            reason: 'Script interaction should persist across sessions');
      });
    });

    group('Phase 5: SpotlightTour is Opt-In', () {
      test('does NOT auto-start even for brand new users', () async {
        // Even after profile creation and meaningful action
        await onboardingService.markAppUsable();
        await onboardingService.recordFirstMeaningfulAction();

        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isFalse,
            reason:
                'SpotlightTour should never auto-start. Only opt-in via Settings.');
      });

      test('starts ONLY when explicitly triggered from Settings', () async {
        // User clicks "Restart Tour" in Settings
        await spotlightService.resetAndStart();

        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isTrue,
            reason:
                'SpotlightTour should only start when user explicitly requests it');
      });

      test('remains dismissed after completion', () async {
        await spotlightService.resetAndStart();
        await spotlightService.completeTour();

        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isFalse,
            reason: 'SpotlightTour should not show after completion');
      });

      test('remains dismissed if user skips it', () async {
        await spotlightService.resetAndStart();
        await spotlightService.dismissTour();

        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isFalse,
            reason: 'SpotlightTour should not show after dismissal');
      });
    });

    group('No Overlapping Onboarding', () {
      test('at most one major onboarding UI should be visible', () async {
        // After profile creation:
        // - PostSetupGuide: NOT ready yet (no action, no delay)
        // - GettingStartedCard: NOT ready yet (no script interaction)
        // - SpotlightTour: NOT ready (opt-in only)

        final postSetupReady = await onboardingService.isPostSetupGuideReady();
        final hasScriptInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightReady = await spotlightService.shouldShowTour();

        final visibleCount = [
          postSetupReady,
          hasScriptInteraction && await progressService.shouldShowGuide(),
          spotlightReady,
        ].where((v) => v).length;

        expect(visibleCount, equals(0),
            reason:
                'No onboarding UI should be visible immediately after profile creation');
      });

      test('after first script: only GettingStartedCard shows (not Spotlight)',
          () async {
        await progressService.recordFirstScriptInteraction();
        await onboardingService.markAppUsable();
        await onboardingService.recordFirstMeaningfulAction();

        // Simulate 5 seconds passing
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            'app_usable_since',
            DateTime.now()
                .subtract(const Duration(seconds: 5))
                .millisecondsSinceEpoch);

        final postSetupReady = await onboardingService.isPostSetupGuideReady();
        final hasScriptInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightReady = await spotlightService.shouldShowTour();

        // PostSetupGuide: may be ready (after action/delay)
        // GettingStartedCard: ready (after script interaction)
        // SpotlightTour: NOT ready (opt-in only)

        expect(spotlightReady, isFalse,
            reason: 'SpotlightTour should never auto-start');

        expect(hasScriptInteraction, isTrue,
            reason: 'Script interaction should be recorded');

        // Both PostSetupGuide and GettingStartedCard can coexist
        // but they are shown at different times in the UI flow
        expect(postSetupReady || hasScriptInteraction, isTrue);
      });
    });

    group('Reset Functionality', () {
      test('resetOnboarding clears all onboarding state', () async {
        // Set up some state
        await onboardingService.markOnboardingShown();
        await onboardingService.markAppUsable();
        await onboardingService.recordFirstMeaningfulAction();
        await onboardingService.markPostSetupGuideShown();
        await progressService.recordFirstScriptInteraction();
        await spotlightService.completeTour();

        // Reset
        await onboardingService.resetOnboarding();
        await progressService.reset();
        await spotlightService.reset();

        // Verify all reset
        final shouldShowOnboarding =
            await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );
        final postSetupReady = await onboardingService.isPostSetupGuideReady();
        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightCompleted = await spotlightService.isCompleted();

        expect(shouldShowOnboarding, isTrue);
        expect(postSetupReady, isFalse);
        expect(hasInteraction, isFalse);
        expect(spotlightCompleted, isFalse);
      });
    });
  });
}
