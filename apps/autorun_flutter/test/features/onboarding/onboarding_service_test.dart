import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';

void main() {
  group('OnboardingService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('shouldShowOnboarding', () {
      test('returns true when no profiles, no scripts, and not shown before',
          () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(result, isTrue);
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

      test('returns false when onboarding was already shown', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 1,
        });
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(result, isFalse);
      });

      test('returns true when onboarding shown but version is outdated',
          () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 0,
        });
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );

        expect(result, isTrue);
      });

      test('returns false when profiles exist even if version is outdated',
          () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 0,
        });
        final service = OnboardingService();

        final result = await service.shouldShowOnboarding(
          hasProfiles: true,
          hasScripts: false,
        );

        expect(result, isFalse);
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

      test('sets onboarding_version to current version', () async {
        SharedPreferences.setMockInitialValues({});
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.markOnboardingShown();

        expect(prefs.getInt('onboarding_version'), equals(1));
      });
    });

    group('resetOnboarding', () {
      test('removes onboarding_shown', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 1,
        });
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.resetOnboarding();

        expect(prefs.containsKey('onboarding_shown'), isFalse);
      });

      test('removes onboarding_version', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 1,
        });
        final service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();

        await service.resetOnboarding();

        expect(prefs.containsKey('onboarding_version'), isFalse);
      });

      test('allows onboarding to be shown again', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_shown': true,
          'onboarding_version': 1,
        });
        final service = OnboardingService();

        await service.resetOnboarding();

        final result = await service.shouldShowOnboarding(
          hasProfiles: false,
          hasScripts: false,
        );
        expect(result, isTrue);
      });
    });
  });
}
