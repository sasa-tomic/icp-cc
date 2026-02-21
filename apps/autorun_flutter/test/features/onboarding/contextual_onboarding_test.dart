import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';
import 'package:icp_autorun/services/contextual_tip_service.dart';

/// Contextual Onboarding Tests
///
/// These tests verify the new contextual onboarding behavior:
/// 1. App opens directly to main screen (no immediate dialog)
/// 2. In-context tips appear when user reaches each feature
/// 3. Tips can be dismissed and don't reappear
/// 4. Profile creation is deferred until needed (e.g., publishing)
void main() {
  group('Contextual Onboarding', () {
    late OnboardingService onboardingService;
    late ContextualTipService tipService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onboardingService = OnboardingService();
      tipService = ContextualTipService();
    });

    group('No Upfront Onboarding', () {
      test('app opens directly to main screen - no dialog shown', () async {
        // Even for brand new users with no profiles/scripts,
        // should NOT show upfront onboarding
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(shouldShow, isFalse,
            reason: 'App should open directly to main screen without '
                'showing "What\'s your name?" dialog');
      });

      test('app opens directly for existing users', () async {
        // Users with existing profiles should also not see dialog
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: true,
          hasScripts: false,
        );

        expect(shouldShow, isFalse,
            reason: 'Users with profiles should open directly to main screen');
      });

      test('app opens directly for users with scripts', () async {
        // Users with existing scripts should also not see dialog
        final shouldShow = await onboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: true,
        );

        expect(shouldShow, isFalse,
            reason: 'Users with scripts should open directly to main screen');
      });
    });

    group('Contextual Tips - First-Time Feature Discovery', () {
      test('shows tip when viewing scripts for the first time', () async {
        final shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.scriptsView,
        );

        expect(shouldShow, isTrue,
            reason: 'First time in scripts view should show tip');
      });

      test('shows tip when entering script editor for the first time',
          () async {
        final shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.scriptEditor,
        );

        expect(shouldShow, isTrue,
            reason: 'First time in script editor should show tip');
      });

      test('shows tip when entering explore/canisters for the first time',
          () async {
        final shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.exploreView,
        );

        expect(shouldShow, isTrue,
            reason: 'First time in explore view should show tip');
      });

      test('shows tip when opening marketplace for the first time', () async {
        final shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.marketplace,
        );

        expect(shouldShow, isTrue,
            reason: 'First time in marketplace should show tip');
      });

      test('shows tip when profile creation is needed', () async {
        final shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.profileCreation,
        );

        expect(shouldShow, isTrue,
            reason: 'First time needing profile should show tip');
      });
    });

    group('Contextual Tips - Dismissal and Persistence', () {
      test('tip is not shown again after dismissal', () async {
        // First time should show
        var shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.scriptsView,
        );
        expect(shouldShow, isTrue);

        // Dismiss it
        await tipService.markTipSeen(ContextualTipFeature.scriptsView);

        // Should not show again
        shouldShow = await tipService.shouldShowTip(
          ContextualTipFeature.scriptsView,
        );
        expect(shouldShow, isFalse,
            reason: 'Tip should not show after being dismissed');
      });

      test('dismissal persists across app restarts', () async {
        // Dismiss tip
        await tipService.markTipSeen(ContextualTipFeature.scriptEditor);

        // Create new service instance (simulating app restart)
        final newService = ContextualTipService();
        final shouldShow =
            await newService.shouldShowTip(ContextualTipFeature.scriptEditor);

        expect(shouldShow, isFalse,
            reason: 'Dismissed tips should not show after app restart');
      });

      test('each feature tip is tracked independently', () async {
        // Dismiss one tip
        await tipService.markTipSeen(ContextualTipFeature.scriptsView);

        // That tip should not show
        var shouldShow =
            await tipService.shouldShowTip(ContextualTipFeature.scriptsView);
        expect(shouldShow, isFalse);

        // Other tips should still show
        shouldShow =
            await tipService.shouldShowTip(ContextualTipFeature.scriptEditor);
        expect(shouldShow, isTrue,
            reason: 'Dismissal of one tip should not affect others');

        shouldShow =
            await tipService.shouldShowTip(ContextualTipFeature.exploreView);
        expect(shouldShow, isTrue,
            reason: 'Dismissal of one tip should not affect others');
      });

      test('all tips can be dismissed', () async {
        // Dismiss all tips
        for (final feature in ContextualTipFeature.values) {
          await tipService.markTipSeen(feature);
        }

        // None should show
        for (final feature in ContextualTipFeature.values) {
          final shouldShow = await tipService.shouldShowTip(feature);
          expect(shouldShow, isFalse,
              reason: 'Tip $feature should not show after dismissal');
        }
      });
    });

    group('Deferred Profile Creation', () {
      test('profile creation is not forced on app launch', () async {
        // The app should work without a profile
        // User can browse marketplace, view scripts, etc.
        // without being forced to create a profile

        // Verify no profile-related blocking happens
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.browseMarketplace,
          hasProfile: false,
        );

        expect(needsProfile, isFalse,
            reason: 'Browsing marketplace should not require a profile');
      });

      test('profile is needed for publishing scripts', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.publishScript,
          hasProfile: false,
        );

        expect(needsProfile, isTrue,
            reason: 'Publishing a script should require a profile');
      });

      test('profile is needed for saving preferences', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.savePreferences,
          hasProfile: false,
        );

        expect(needsProfile, isTrue,
            reason: 'Saving preferences should require a profile');
      });

      test('profile is NOT needed if already exists', () async {
        final needsProfile = await onboardingService.needsProfileForAction(
          action: AppAction.publishScript,
          hasProfile: true,
        );

        expect(needsProfile, isFalse,
            reason: 'No prompt needed if profile already exists');
      });
    });

    group('Tip Content', () {
      test('each feature has appropriate tip content', () async {
        for (final feature in ContextualTipFeature.values) {
          final content = tipService.getTipContent(feature);

          expect(content.title, isNotEmpty,
              reason: 'Tip for $feature should have a title');
          expect(content.description, isNotEmpty,
              reason: 'Tip for $feature should have a description');
        }
      });

      test('tip content is user-friendly', () async {
        final scriptsTip =
            tipService.getTipContent(ContextualTipFeature.scriptsView);
        expect(scriptsTip.title, contains('Script'),
            reason: 'Scripts tip should mention scripts');

        final editorTip =
            tipService.getTipContent(ContextualTipFeature.scriptEditor);
        final editorTitleLower = editorTip.title.toLowerCase();
        expect(
            editorTitleLower.contains('run') ||
                editorTitleLower.contains('edit'),
            isTrue,
            reason: 'Editor tip should mention running or editing');

        final exploreTip =
            tipService.getTipContent(ContextualTipFeature.exploreView);
        final exploreTitleLower = exploreTip.title.toLowerCase();
        expect(
            exploreTitleLower.contains('canister') ||
                exploreTitleLower.contains('explore'),
            isTrue,
            reason: 'Explore tip should mention canisters or exploring');
      });
    });

    group('Reset Functionality', () {
      test('reset allows all tips to show again', () async {
        // Dismiss all tips
        for (final feature in ContextualTipFeature.values) {
          await tipService.markTipSeen(feature);
        }

        // Reset
        await tipService.reset();

        // All tips should show again
        for (final feature in ContextualTipFeature.values) {
          final shouldShow = await tipService.shouldShowTip(feature);
          expect(shouldShow, isTrue,
              reason: 'Tip $feature should show after reset');
        }
      });
    });

    group('Migration from Old Onboarding', () {
      test('users with old onboarding flag still get contextual tips',
          () async {
        // Simulate user who went through old onboarding
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 1,
        });

        final newOnboardingService = OnboardingService();
        final newTipService = ContextualTipService();

        // Should NOT show old-style onboarding
        final shouldShowOld = await newOnboardingService.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );
        expect(shouldShowOld, isFalse);

        // BUT should still see contextual tips (first time features)
        final shouldShowTip = await newTipService.shouldShowTip(
          ContextualTipFeature.scriptsView,
        );
        expect(shouldShowTip, isTrue,
            reason:
                'Existing users should see contextual tips for new features');
      });

      test('users who dismissed old GettingStartedCard get contextual tips',
          () async {
        // Simulate user who dismissed old guide
        SharedPreferences.setMockInitialValues({
          'onboarding_guide_dismissed': true,
        });

        final tipService = ContextualTipService();

        // Should still see contextual tips
        final shouldShowTip =
            await tipService.shouldShowTip(ContextualTipFeature.marketplace);
        expect(shouldShowTip, isTrue,
            reason: 'Users who dismissed old card should see contextual tips');
      });
    });
  });
}
