import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';
import 'package:icp_autorun/services/onboarding_progress_service.dart';
import 'package:icp_autorun/services/spotlight_service.dart';
import 'package:icp_autorun/services/contextual_tip_service.dart';

/// Consolidated Onboarding Tests
///
/// These tests verify the contextual onboarding flow:
/// 1. First launch: App opens directly to main screen (NO upfront dialog!)
/// 2. Contextual tips appear in-context when user reaches each feature
/// 3. SpotlightTour: Only trigger from "Restart Tour" in Settings
/// 4. GettingStartedCard: Only show AFTER first script interaction
/// 5. Profile creation is deferred until needed (e.g., publishing)
void main() {
  group('Consolidated Onboarding Flow', () {
    late OnboardingService onboardingService;
    late OnboardingProgressService progressService;
    late SpotlightService spotlightService;
    late ContextualTipService tipService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onboardingService = OnboardingService();
      progressService = OnboardingProgressService();
      spotlightService = SpotlightService();
      tipService = ContextualTipService();
    });

    group('Phase 1: First Launch', () {
      test('app opens directly to main screen - NO upfront dialog', () async {
        // Even for brand new users with no profiles/scripts
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(shouldShow, isFalse,
            reason: 'App should open directly to main screen without '
                'showing "What\'s your name?" dialog');
      });

      test('contextual tips are available for new users', () async {
        // New users should see contextual tips when they reach features
        final shouldShowTip =
            await tipService.shouldShowTip(ContextualTipFeature.scriptsView);

        expect(shouldShowTip, isTrue,
            reason: 'Contextual tips should be available for new users');
      });

      test('profile is NOT forced on first launch', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.browseMarketplace,
          hasProfile: false,
        );

        expect(needsProfile, isFalse,
            reason: 'Users can browse marketplace without creating a profile');
      });
    });

    group('Phase 2: Contextual Tips', () {
      test('tips appear when user first reaches a feature', () async {
        // First time in scripts view
        expect(await tipService.shouldShowTip(ContextualTipFeature.scriptsView),
            isTrue);

        // First time in script editor
        expect(
            await tipService.shouldShowTip(ContextualTipFeature.scriptEditor),
            isTrue);

        // First time in explore
        expect(await tipService.shouldShowTip(ContextualTipFeature.exploreView),
            isTrue);

        // First time in marketplace
        expect(await tipService.shouldShowTip(ContextualTipFeature.marketplace),
            isTrue);
      });

      test('tips can be dismissed and do not reappear', () async {
        // User sees and dismisses tip
        await tipService.markTipSeen(ContextualTipFeature.scriptsView);

        // Tip should not show again
        final shouldShow =
            await tipService.shouldShowTip(ContextualTipFeature.scriptsView);
        expect(shouldShow, isFalse);

        // Other tips should still show
        expect(
            await tipService.shouldShowTip(ContextualTipFeature.scriptEditor),
            isTrue);
      });
    });

    group('Phase 3: GettingStartedCard Timing', () {
      test('does NOT show before first script interaction', () async {
        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final shouldShowGuide = await progressService.shouldShowGuide();

        final shouldShowCard = shouldShowGuide && hasInteraction;

        expect(shouldShowCard, isFalse,
            reason:
                'GettingStartedCard should NOT show without script interaction');
      });

      test('shows AFTER first script interaction', () async {
        await progressService.recordFirstScriptInteraction();

        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final shouldShowGuide = await progressService.shouldShowGuide();

        final shouldShowCard = shouldShowGuide && hasInteraction;

        expect(shouldShowCard, isTrue,
            reason:
                'GettingStartedCard should show after first script interaction');
      });
    });

    group('Phase 4: SpotlightTour is Opt-In', () {
      test('does NOT auto-start even for brand new users', () async {
        final shouldShow = await spotlightService.shouldShowTour();

        expect(shouldShow, isFalse,
            reason:
                'SpotlightTour should never auto-start. Only opt-in via Settings.');
      });

      test('starts ONLY when explicitly triggered from Settings', () async {
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
    });

    group('Phase 5: Deferred Profile Creation', () {
      test('profile not needed for browsing', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.browseMarketplace,
          hasProfile: false,
        );

        expect(needsProfile, isFalse);
      });

      test('profile not needed for downloading scripts', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.downloadScript,
          hasProfile: false,
        );

        expect(needsProfile, isFalse);
      });

      test('profile not needed for creating scripts', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.createScript,
          hasProfile: false,
        );

        expect(needsProfile, isFalse);
      });

      test('profile IS needed for publishing scripts', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.publishScript,
          hasProfile: false,
        );

        expect(needsProfile, isTrue, reason: 'Publishing requires a profile');
      });

      test('profile IS needed for saving preferences', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.savePreferences,
          hasProfile: false,
        );

        expect(needsProfile, isTrue,
            reason: 'Saving preferences requires a profile');
      });
    });

    group('No Overlapping Onboarding', () {
      test('no onboarding UI on first launch', () async {
        final hasScriptInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightReady = await spotlightService.shouldShowTour();
        final shouldShowOnboarding =
            await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(shouldShowOnboarding, isFalse, reason: 'No upfront onboarding');
        expect(spotlightReady, isFalse,
            reason: 'SpotlightTour should not auto-start');
        expect(hasScriptInteraction, isFalse,
            reason: 'No script interaction yet');
      });

      test('only GettingStartedCard shows after script interaction', () async {
        await progressService.recordFirstScriptInteraction();

        final hasScriptInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightReady = await spotlightService.shouldShowTour();

        expect(spotlightReady, isFalse,
            reason: 'SpotlightTour should never auto-start');
        expect(hasScriptInteraction, isTrue,
            reason: 'Script interaction should be recorded');
      });
    });

    group('Reset Functionality', () {
      test('resetOnboarding clears all onboarding state', () async {
        // Set up some state
        await onboardingService.markOnboardingShown();
        await progressService.recordFirstScriptInteraction();
        await spotlightService.completeTour();
        await tipService.markTipSeen(ContextualTipFeature.scriptsView);

        // Reset
        await onboardingService.resetOnboarding();
        await progressService.reset();
        await spotlightService.reset();
        await tipService.reset();

        // Verify all reset
        final hasInteraction =
            await progressService.hasHadFirstScriptInteraction();
        final spotlightCompleted = await spotlightService.isCompleted();
        final tipShown =
            await tipService.shouldShowTip(ContextualTipFeature.scriptsView);

        // Note: shouldShowOnboarding still returns false (no upfront onboarding)
        // but other states should be reset
        expect(hasInteraction, isFalse);
        expect(spotlightCompleted, isFalse);
        expect(tipShown, isTrue, reason: 'Tips should show again after reset');
      });
    });
  });
}
