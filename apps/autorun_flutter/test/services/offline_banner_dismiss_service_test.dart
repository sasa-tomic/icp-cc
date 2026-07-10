import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/offline_banner_dismiss_service.dart';

/// TQ-5 — direct coverage for [OfflineBannerDismissService].
///
/// The service gates the user-visible "you're offline" banner: once dismissed
/// it stays hidden for [OfflineBannerDismissService.reappearDuration], then
/// reappears. The window compares a stored ISO timestamp against `DateTime.now`
/// — a raw VM call, NOT the `clock` package — so `fakeAsync` cannot advance the
/// service's notion of "now". The expired cases therefore seed the persisted
/// dismiss timestamp to a computed moment in the past (the storage-contract
/// key), giving a deterministic outcome with no real `Future.delayed`. Second-
/// and minute-wide margins absorb the microseconds between the fixture's
/// `DateTime.now()` and the service's, so the boundary is never racy.
void main() {
  // SharedPreferences key the service persists the dismiss time under. Mirrored
  // here ONLY to set up "dismissed long ago" fixtures; the public API
  // (dismissBanner / clearDismissState / shouldShowBanner) drives everything
  // else.
  const String dismissedAtKey = 'offline_banner_dismissed_at';

  group('OfflineBannerDismissService', () {
    setUp(() {
      // Fresh, isolated SharedPreferences store per test.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    group('shouldShowBanner', () {
      test('shows when never dismissed', () async {
        expect(
            await OfflineBannerDismissService().shouldShowBanner(), isTrue);
      });

      test('is hidden immediately after a fresh dismiss', () async {
        final service = OfflineBannerDismissService();
        await service.dismissBanner();
        expect(await service.shouldShowBanner(), isFalse);
      });

      test('stays hidden well within the window', () async {
        await seedDismissedAt(dismissedAtKey,
            DateTime.now().subtract(const Duration(minutes: 30)));
        expect(await OfflineBannerDismissService().shouldShowBanner(), isFalse);
      });

      test('stays hidden until just before the window expires', () async {
        await seedDismissedAt(
            dismissedAtKey,
            DateTime.now().subtract(
                OfflineBannerDismissService.reappearDuration -
                    const Duration(seconds: 2)));
        expect(await OfflineBannerDismissService().shouldShowBanner(), isFalse);
      });

      test('reappears once the window has elapsed', () async {
        await seedDismissedAt(
            dismissedAtKey,
            DateTime.now().subtract(
                OfflineBannerDismissService.reappearDuration +
                    const Duration(minutes: 5)));
        expect(await OfflineBannerDismissService().shouldShowBanner(), isTrue);
      });
    });

    group('dismissBanner', () {
      test('records a timestamp so the banner is hidden', () async {
        final service = OfflineBannerDismissService();
        expect(await service.shouldShowBanner(), isTrue);

        await service.dismissBanner();

        expect(await service.shouldShowBanner(), isFalse);
      });
    });

    group('clearDismissState', () {
      test('clears a prior dismiss so the banner shows again immediately',
          () async {
        final service = OfflineBannerDismissService();
        await service.dismissBanner();
        expect(await service.shouldShowBanner(), isFalse);

        await service.clearDismissState();

        expect(await service.shouldShowBanner(), isTrue);
      });

      test('is a no-op when there was nothing to clear', () async {
        final service = OfflineBannerDismissService();
        await service.clearDismissState();
        expect(await service.shouldShowBanner(), isTrue);
      });
    });

    group('persistence', () {
      test('a fresh instance reads the same dismiss state from prefs',
          () async {
        // Dismissing on one instance hides the banner on a brand-new instance
        // — proving the state is SharedPreferences-backed, not in-memory.
        await OfflineBannerDismissService().dismissBanner();

        expect(await OfflineBannerDismissService().shouldShowBanner(), isFalse);
      });
    });
  });
}

/// Seeds the dismiss timestamp directly into SharedPreferences so an
/// "already-dismissed-ago" scenario can be exercised deterministically.
Future<void> seedDismissedAt(String key, DateTime when) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, when.toIso8601String());
}
