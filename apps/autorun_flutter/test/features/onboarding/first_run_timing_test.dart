import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_service.dart';

void main() {
  group('First Run Dialog Timing', () {
    late OnboardingService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = OnboardingService();
    });

    group('PostSetupGuide timing', () {
      test('should NOT be ready immediately after profile creation', () async {
        // A user who just created a profile should NOT see PostSetupGuide yet
        // They haven't even seen the app!
        final ready = await service.isPostSetupGuideReady();
        expect(ready, isFalse,
            reason:
                'PostSetupGuide should not be ready immediately after profile creation');
      });

      test('should be ready after first meaningful action', () async {
        // After user performs a meaningful action (view script, explore canister, etc.)
        // PostSetupGuide can be shown
        await service.recordFirstMeaningfulAction();

        final ready = await service.isPostSetupGuideReady();
        expect(ready, isTrue,
            reason:
                'PostSetupGuide should be ready after first meaningful action');
      });

      test('should be ready after minimum delay has passed', () async {
        // Alternative: after a minimum delay, show the guide even without action
        // This simulates: markOnboardingShown(), wait 5 seconds, then check

        // Mark the app as "usable" (profile created)
        await service.markAppUsable();

        // Before delay: not ready
        final beforeDelay = await service.isPostSetupGuideReady();
        expect(beforeDelay, isFalse);

        // Simulate 5+ seconds passing by directly setting the timestamp
        final prefs = await SharedPreferences.getInstance();
        final fiveSecondsAgo = DateTime.now()
            .subtract(const Duration(seconds: 5))
            .millisecondsSinceEpoch;
        await prefs.setInt('app_usable_since', fiveSecondsAgo);

        // After delay: ready
        final afterDelay = await service.isPostSetupGuideReady();
        expect(afterDelay, isTrue,
            reason: 'PostSetupGuide should be ready after minimum delay');
      });

      test('should be ready when either action OR delay condition is met',
          () async {
        // Case 1: Action recorded, no delay - should be ready
        SharedPreferences.setMockInitialValues({});
        service = OnboardingService();
        await service.recordFirstMeaningfulAction();
        expect(await service.isPostSetupGuideReady(), isTrue);

        // Case 2: Delay passed, no action - should be ready
        SharedPreferences.setMockInitialValues({});
        service = OnboardingService();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            'app_usable_since',
            DateTime.now()
                .subtract(const Duration(seconds: 5))
                .millisecondsSinceEpoch);
        expect(await service.isPostSetupGuideReady(), isTrue);
      });
    });

    group('recordFirstMeaningfulAction', () {
      test('persists meaningful action state', () async {
        await service.recordFirstMeaningfulAction();

        // Create new service instance to verify persistence
        final newService = OnboardingService();
        expect(await newService.isPostSetupGuideReady(), isTrue);
      });

      test('is idempotent', () async {
        await service.recordFirstMeaningfulAction();
        await service.recordFirstMeaningfulAction();
        await service.recordFirstMeaningfulAction();

        // Should still be ready, no errors
        expect(await service.isPostSetupGuideReady(), isTrue);
      });
    });

    group('markAppUsable', () {
      test('records timestamp when app became usable', () async {
        await service.markAppUsable();

        final prefs = await SharedPreferences.getInstance();
        final timestamp = prefs.getInt('app_usable_since');

        expect(timestamp, isNotNull);
        expect(timestamp,
            lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
      });

      test('does not overwrite existing timestamp', () async {
        await service.markAppUsable();
        final prefs = await SharedPreferences.getInstance();
        final firstTimestamp = prefs.getInt('app_usable_since');

        // Wait a tiny bit and try again
        await Future.delayed(const Duration(milliseconds: 10));
        await service.markAppUsable();

        final secondTimestamp = prefs.getInt('app_usable_since');
        expect(secondTimestamp, equals(firstTimestamp),
            reason: 'Should not overwrite existing app_usable_since timestamp');
      });
    });

    group('resetOnboarding resets first action state', () {
      test('clears meaningful action flag', () async {
        await service.recordFirstMeaningfulAction();
        await service.resetOnboarding();

        // After reset, guide should not be ready (no action, no delay)
        final ready = await service.isPostSetupGuideReady();
        expect(ready, isFalse);
      });

      test('clears app usable timestamp', () async {
        await service.markAppUsable();
        await service.resetOnboarding();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('app_usable_since'), isFalse);
        expect(prefs.containsKey('first_meaningful_action'), isFalse);
      });
    });
  });
}
