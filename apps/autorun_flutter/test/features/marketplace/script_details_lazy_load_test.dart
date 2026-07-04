import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// UX-5 — lazy-load contract for the Script Details dialog.
///
/// Asserts the two promises the lazy-load change makes:
///  1. Opening the dialog fetches ONLY the Details/preview payload — Reviews
///     and Versions are NOT fetched until their tab is selected.
///  2. Selecting a tab fetches its payload exactly once; subsequent
///     re-selections reuse the cached result (no re-fetch).
///
/// The MockClient counts requests by URL pattern; the assertions read those
/// counters after each interaction. Real keypairs aren't relevant here (the
/// dialog's fetches are unauthenticated HTTP), so we use the same plain
/// `MarketplaceScript` the other marketplace tests use.
void main() {
  group('ScriptDetailsDialog lazy-load (UX-5)', () {
    late MarketplaceOpenApiService service;
    late MarketplaceScript testScript;

    setUp(() {
      suppressDebugOutput = true;
      service = MarketplaceOpenApiService();
      AppConfig.setTestEndpoint('https://mock.api');

      testScript = MarketplaceScript(
        id: 'script-123',
        title: 'Test Script',
        description: 'A test script',
        category: 'Development',
        tags: const ['test'],
        authorId: 'author-1',
        authorName: 'Test Author',
        price: 0,
        downloads: 100,
        rating: 4.2,
        reviewCount: 15,
        bundle: 'print("hello")',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      );
    });

    tearDown(() {
      suppressDebugOutput = false;
      service.resetHttpClient();
    });

    /// Builds a counting MockClient that records every review / version
    /// request, returns empty arrays for both, and serves the script body for
    /// everything else (covers the preview download's `getScriptDetails`).
    MockClient countingClient({
      required void Function() onReview,
      required void Function() onVersion,
    }) {
      return MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/reviews')) {
          onReview();
          return http.Response(
            jsonEncode({'success': true, 'data': []}),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        // Versions LIST endpoint — excludes `/versions/{v}` (single-version
        // download) which is also matched by `/versions/`.
        if (path.contains('/versions') && !path.contains('/versions/')) {
          onVersion();
          return http.Response(
            jsonEncode({'success': true, 'data': []}),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        // Default: script details body (used by `_loadScriptPreview` →
        // `downloadScript` → `getScriptDetails`).
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': testScript.id,
              'title': testScript.title,
              'description': testScript.description,
              'category': testScript.category,
              'tags': testScript.tags,
              'author_id': testScript.authorId,
              'author_name': testScript.authorName,
              'bundle': testScript.bundle,
              'price': testScript.price,
              'downloads': testScript.downloads,
              'rating': testScript.rating,
              'review_count': testScript.reviewCount,
              'created_at': testScript.createdAt.toIso8601String(),
              'updated_at': testScript.updatedAt.toIso8601String(),
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });
    }

    testWidgets(
        'opening the dialog does NOT fetch Reviews or Versions (only Details/preview)',
        (WidgetTester tester) async {
      int reviewsFetches = 0;
      int versionsFetches = 0;

      final client = countingClient(
        onReview: () => reviewsFetches++,
        onVersion: () => versionsFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
      );

      // The dialog is open with the Details tab visible. Neither Reviews nor
      // Versions should have been requested.
      expect(reviewsFetches, 0,
          reason: 'Reviews must not load until the Reviews tab is selected');
      expect(versionsFetches, 0,
          reason: 'Versions must not load until the Versions tab is selected');
    });

    testWidgets(
        'selecting Reviews fetches once; re-selecting Reviews reuses the cache',
        (WidgetTester tester) async {
      int reviewsFetches = 0;
      int versionsFetches = 0;

      final client = countingClient(
        onReview: () => reviewsFetches++,
        onVersion: () => versionsFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
      );

      // First selection → fetch.
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      expect(reviewsFetches, 1);
      expect(versionsFetches, 0);

      // Switch away to Details, then back to Reviews → no new fetch (cached).
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      expect(reviewsFetches, 1,
          reason: 'Re-selecting Reviews must reuse the cached payload');
    });

    testWidgets(
        'selecting Versions fetches once; re-selecting Versions reuses the cache',
        (WidgetTester tester) async {
      int reviewsFetches = 0;
      int versionsFetches = 0;

      final client = countingClient(
        onReview: () => reviewsFetches++,
        onVersion: () => versionsFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
      );

      // First selection → fetch.
      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();
      expect(versionsFetches, 1);
      expect(reviewsFetches, 0);

      // Switch away to Details, then back to Versions → no new fetch (cached).
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();
      expect(versionsFetches, 1,
          reason: 'Re-selecting Versions must reuse the cached payload');
    });

    testWidgets('each tab fetches at most once across a full tour',
        (WidgetTester tester) async {
      int reviewsFetches = 0;
      int versionsFetches = 0;

      final client = countingClient(
        onReview: () => reviewsFetches++,
        onVersion: () => versionsFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
      );

      // Tour every tab twice. Each fetch endpoint should have been hit once.
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.text('Reviews'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Versions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
      }

      expect(reviewsFetches, 1);
      expect(versionsFetches, 1);
    });
  });
}
