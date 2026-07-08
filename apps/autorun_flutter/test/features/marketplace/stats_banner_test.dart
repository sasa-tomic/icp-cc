import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/marketplace_stats_banner.dart';

import '_marketplace_test_harness.dart';

/// Unit and widget tests for the Marketplace Stats Banner
///
/// This test covers:
/// 1. Stats display shows key numbers (scripts, downloads at minimum)
/// 2. Loading state is handled (shimmer or placeholder)
/// 3. Error state doesn't break UI
void main() {
  group('MarketplaceStatsBanner', () {
    testWidgets('displays stats when data is available', (tester) async {
      final stats = MarketplaceStats(
        totalScripts: 1234,
        totalAuthors: 567,
        totalDownloads: 10000,
        averageRating: 4.5,
      );

      await pumpMarketplaceWidget(
        tester,
        MarketplaceStatsBanner(stats: stats),
      );

      // Verify stats are displayed
      // 1234 scripts -> 1.2K (rounded to 1 decimal)
      // 567 authors -> 567 (not large enough to format)
      // 10000 downloads -> 10K
      expect(find.textContaining('1.2K'), findsOneWidget);
      expect(find.textContaining('scripts'), findsOneWidget);
      expect(find.textContaining('10K'), findsOneWidget);
      expect(find.textContaining('downloads'), findsOneWidget);
    });

    testWidgets('shows loading shimmer when isLoading is true', (tester) async {
      await pumpMarketplaceWidget(
        tester,
        const MarketplaceStatsBanner(isLoading: true),
      );

      // Should show shimmer/placeholder containers, not actual stats
      expect(find.byType(MarketplaceStatsBanner), findsOneWidget);
      expect(find.textContaining('scripts'), findsNothing);
    });

    testWidgets('hides all stat content on error (graceful degradation)',
        (tester) async {
      await pumpMarketplaceWidget(
        tester,
        const MarketplaceStatsBanner(hasError: true),
      );

      // On error the banner returns SizedBox.shrink — NO stat labels render.
      // This is the actual "graceful degradation" behaviour the widget promises
      // (build → SizedBox.shrink when hasError), not just the flag echoing back.
      expect(find.textContaining('scripts'), findsNothing);
      expect(find.textContaining('authors'), findsNothing);
      expect(find.textContaining('downloads'), findsNothing);
    });

    testWidgets('formats large numbers correctly', (tester) async {
      final stats = MarketplaceStats(
        totalScripts: 1500000,
        totalAuthors: 2500,
        totalDownloads: 5000000,
        averageRating: 4.8,
      );

      await pumpMarketplaceWidget(
        tester,
        MarketplaceStatsBanner(stats: stats),
      );

      // Large numbers should be formatted (1.5M, 5M, etc.)
      // 1.5M scripts, 2.5K authors, 5M downloads
      expect(find.text('1.5M'), findsOneWidget); // 1.5M scripts
      expect(find.text('5M'), findsOneWidget); // 5M downloads
    });

    testWidgets('displays minimal stats (scripts and downloads)',
        (tester) async {
      final stats = MarketplaceStats(
        totalScripts: 42,
        totalAuthors: 10,
        totalDownloads: 100,
        averageRating: 4.0,
      );

      await pumpMarketplaceWidget(
        tester,
        MarketplaceStatsBanner(stats: stats),
      );

      // At minimum, scripts and downloads should be shown
      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('100'), findsOneWidget);
    });

    testWidgets('displays authors count', (tester) async {
      final stats = MarketplaceStats(
        totalScripts: 100,
        totalAuthors: 25,
        totalDownloads: 1000,
        averageRating: 4.2,
      );

      await pumpMarketplaceWidget(
        tester,
        MarketplaceStatsBanner(stats: stats),
      );

      // Authors count should be displayed
      expect(find.textContaining('25'), findsOneWidget);
      expect(find.textContaining('authors'), findsOneWidget);
    });
  });

  group('MarketplaceStats model', () {
    test('parses from JSON with snake_case keys', () {
      final json = {
        'total_scripts': 100,
        'total_authors': 50,
        'total_downloads': 1000,
        'average_rating': 4.5,
      };

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(100));
      expect(stats.totalAuthors, equals(50));
      expect(stats.totalDownloads, equals(1000));
      expect(stats.averageRating, equals(4.5));
    });

    test('parses from JSON with camelCase keys', () {
      final json = {
        'totalScripts': 200,
        'totalAuthors': 75,
        'totalDownloads': 2000,
        'averageRating': 4.8,
      };

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(200));
      expect(stats.totalAuthors, equals(75));
      expect(stats.totalDownloads, equals(2000));
      expect(stats.averageRating, equals(4.8));
    });

    test('handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final stats = MarketplaceStats.fromJson(json);

      expect(stats.totalScripts, equals(0));
      expect(stats.totalAuthors, equals(0));
      expect(stats.totalDownloads, equals(0));
      expect(stats.averageRating, equals(0.0));
    });
  });
}
