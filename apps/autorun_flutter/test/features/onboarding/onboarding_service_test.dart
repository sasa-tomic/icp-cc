import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';

void main() {
  group('OnboardingService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('shouldShowOnboarding', () {
      test('always returns false - no upfront onboarding', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(result, isFalse,
            reason: 'App now opens directly without upfront onboarding');
      });

      test('returns false when profiles exist', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: true,
          hasScripts: false,
        );

        expect(result, isFalse);
      });

      test('returns false when scripts exist', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: true,
        );

        expect(result, isFalse);
      });

      test('returns false when both profiles and scripts exist', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: true,
          hasScripts: true,
        );

        expect(result, isFalse);
      });

      test('returns false even when onboarding was never shown', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(result, isFalse,
            reason: 'No upfront onboarding, even for brand new users');
      });

      test('auto-marks onboarding as shown when called', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(prefs.getBool('onboarding_shown'), isTrue,
            reason: 'Should auto-mark onboarding as shown for migration');
        expect(prefs.getInt('onboarding_version'), equals(2),
            reason: 'Should set version to current (2)');
      });
    });

    group('needsProfileForAction', () {
      test('browsing marketplace does not require profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.browseMarketplace,
          hasProfile: false,
        );

        expect(result, isFalse,
            reason: 'Browsing marketplace should work without a profile');
      });

      test('downloading script does not require profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.downloadScript,
          hasProfile: false,
        );

        expect(result, isFalse,
            reason: 'Downloading scripts should work without a profile');
      });

      test('creating script does not require profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.createScript,
          hasProfile: false,
        );

        expect(result, isFalse,
            reason: 'Creating scripts should work without a profile');
      });

      test('running script does not require profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.runScript,
          hasProfile: false,
        );

        expect(result, isFalse,
            reason: 'Running scripts should work without a profile');
      });

      test('publishing script requires profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.publishScript,
          hasProfile: false,
        );

        expect(result, isTrue,
            reason: 'Publishing scripts should require a profile');
      });

      test('saving preferences requires profile', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.savePreferences,
          hasProfile: false,
        );

        expect(result, isTrue,
            reason: 'Saving preferences should require a profile');
      });

      test('no profile prompt needed if profile already exists', () async {
        final service = OnboardingService();

        final result = await service.needsProfileForAction(
          action: AppAction.publishScript,
          hasProfile: true,
        );

        expect(result, isFalse,
            reason: 'No profile prompt needed if profile exists');
      });
    });

    group('markOnboardingShown', () {
      test('sets onboarding_shown to true', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.markOnboardingShown();

        expect(prefs.getBool('onboarding_shown'), isTrue);
      });

      test('sets onboarding_version to current version (2)', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.markOnboardingShown();

        expect(prefs.getInt('onboarding_version'), equals(2));
      });
    });

    group('resetOnboarding', () {
      test('removes onboarding_shown', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 2,
        });
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.resetOnboarding();

        expect(prefs.containsKey('onboarding_shown'), isFalse);
      });

      test('removes onboarding_version', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 2,
        });
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.resetOnboarding();

        expect(prefs.containsKey('onboarding_version'), isFalse);
      });

      test('still returns false after reset (no upfront onboarding)', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 2,
        });
        final service = OnboardingService();

        await service.resetOnboarding();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );
        expect(result, isFalse,
            reason: 'Even after reset, no upfront onboarding');
      });
    });
  });
}
