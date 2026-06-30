import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/onboarding_progress_service.dart';

void main() {
  group('OnboardingProgressService', () {
    late OnboardingProgressService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = OnboardingProgressService();
    });

    group('getIncompleteItems', () {
      test('returns all items for new user', () async {
        final items = await service.getIncompleteItems();

        expect(items, contains(OnboardingItem.browseMarketplace));
        expect(items, contains(OnboardingItem.downloadScript));
        expect(items, contains(OnboardingItem.createScript));
        expect(items, contains(OnboardingItem.tryCanisterClient));
        expect(items, contains(OnboardingItem.setUpPasskey));
      });

      test('excludes completed items', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);
        await service.markComplete(OnboardingItem.downloadScript);

        final items = await service.getIncompleteItems();

        expect(items, isNot(contains(OnboardingItem.browseMarketplace)));
        expect(items, isNot(contains(OnboardingItem.downloadScript)));
        expect(items, contains(OnboardingItem.createScript));
      });
    });

    group('markComplete', () {
      test('marks item as completed', () async {
        final wasComplete =
            await service.markComplete(OnboardingItem.browseMarketplace);

        expect(wasComplete, isTrue);
        expect(
            await service.isComplete(OnboardingItem.browseMarketplace), isTrue);
      });

      test('returns false if already completed', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);
        final wasComplete =
            await service.markComplete(OnboardingItem.browseMarketplace);

        expect(wasComplete, isFalse);
      });
    });

    group('isComplete', () {
      test('returns false for incomplete item', () async {
        expect(await service.isComplete(OnboardingItem.browseMarketplace),
            isFalse);
      });

      test('returns true for completed item', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);

        expect(
            await service.isComplete(OnboardingItem.browseMarketplace), isTrue);
      });
    });

    group('getCompletionProgress', () {
      test('returns 0 for new user', () async {
        final progress = await service.getCompletionProgress();

        expect(progress.completed, equals(0));
        expect(progress.total, equals(5));
      });

      test('returns correct count after completions', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);
        await service.markComplete(OnboardingItem.downloadScript);

        final progress = await service.getCompletionProgress();

        expect(progress.completed, equals(2));
        expect(progress.total, equals(5));
      });

      test('returns all completed', () async {
        for (final item in OnboardingItem.values) {
          await service.markComplete(item);
        }

        final progress = await service.getCompletionProgress();

        expect(progress.completed, equals(progress.total));
        expect(progress.isComplete, isTrue);
      });
    });

    group('shouldShowGuide', () {
      test('returns true for new user', () async {
        expect(await service.shouldShowGuide(), isTrue);
      });

      test('returns false when permanently dismissed', () async {
        await service.dismissPermanently();

        expect(await service.shouldShowGuide(), isFalse);
      });

      test('returns false when all items completed', () async {
        for (final item in OnboardingItem.values) {
          await service.markComplete(item);
        }

        expect(await service.shouldShowGuide(), isFalse);
      });

      test('returns true when some items incomplete', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);

        expect(await service.shouldShowGuide(), isTrue);
      });
    });

    group('dismissPermanently', () {
      test('prevents guide from showing', () async {
        await service.dismissPermanently();

        expect(await service.shouldShowGuide(), isFalse);
      });
    });

    group('snooze', () {
      test('prevents guide from showing temporarily', () async {
        await service.snooze();

        expect(await service.shouldShowGuide(), isFalse);
      });

      test('allows guide after snooze expires', () async {
        final expiredSnoozeKey = 'onboarding_snoozed_until';
        final pastTime = DateTime.now()
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          expiredSnoozeKey: pastTime,
        });
        service = OnboardingProgressService();

        expect(await service.shouldShowGuide(), isTrue);
      });
    });

    group('reset', () {
      test('clears all progress', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);
        await service.dismissPermanently();

        await service.reset();

        expect(await service.isComplete(OnboardingItem.browseMarketplace),
            isFalse);
        expect(await service.shouldShowGuide(), isTrue);
      });
    });

    group('persistence', () {
      test('progress persists across service instances', () async {
        await service.markComplete(OnboardingItem.browseMarketplace);
        await service.markComplete(OnboardingItem.downloadScript);

        final newService = OnboardingProgressService();
        final progress = await newService.getCompletionProgress();

        expect(progress.completed, equals(2));
      });

      test('dismissal persists across service instances', () async {
        await service.dismissPermanently();

        final newService = OnboardingProgressService();
        expect(await newService.shouldShowGuide(), isFalse);
      });
    });

    group('firstScriptInteraction', () {
      test('returns false for new user', () async {
        expect(await service.hasHadFirstScriptInteraction(), isFalse);
      });

      test('returns true after recording interaction', () async {
        await service.recordFirstScriptInteraction();
        expect(await service.hasHadFirstScriptInteraction(), isTrue);
      });

      test('persists across service instances', () async {
        await service.recordFirstScriptInteraction();

        final newService = OnboardingProgressService();
        expect(await newService.hasHadFirstScriptInteraction(), isTrue);
      });

      test('is cleared by reset', () async {
        await service.recordFirstScriptInteraction();
        await service.reset();

        expect(await service.hasHadFirstScriptInteraction(), isFalse);
      });
    });
  });

  group('OnboardingItem', () {
    test('all items have labels', () {
      for (final item in OnboardingItem.values) {
        expect(item.label, isNotEmpty);
      }
    });

    test('all items have icons', () {
      for (final item in OnboardingItem.values) {
        expect(item.icon, isNotNull);
      }
    });
  });
}
