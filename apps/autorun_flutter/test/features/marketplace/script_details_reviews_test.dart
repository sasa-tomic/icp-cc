import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/purchase_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

void main() {
  group('ScriptDetailsDialog Reviews', () {
    late MarketplaceOpenApiService service;
    late MarketplaceScript testScript;

    setUp(() {
      suppressDebugOutput = true;
      service = MarketplaceOpenApiService();
      AppConfig.setTestEndpoint('https://mock.api');

      testScript = MarketplaceScript(
        id: 'script-123',
        title: 'Test Script',
        description: 'A test script for reviews',
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

    Future<void> pumpDialog(
      WidgetTester tester, {
      MarketplaceScript? script,
      List<ScriptReview>? reviews,
      int? reviewsStatusCode,
    }) async {
      final effectiveScript = script ?? testScript;
      final effectiveReviews = reviews ?? [];
      final effectiveStatusCode = reviewsStatusCode ?? 200;

      final client = MockClient((request) async {
        if (request.url.path.contains('/reviews')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': effectiveReviews
                  .map((r) => {
                        'id': r.id,
                        'userId': r.userId,
                        'scriptId': r.scriptId,
                        'rating': r.rating,
                        'comment': r.comment,
                        'isVerifiedPurchase': r.isVerifiedPurchase,
                        'status': r.status,
                        'createdAt': r.createdAt.toIso8601String(),
                        'updatedAt': r.updatedAt.toIso8601String(),
                      })
                  .toList(),
            }),
            effectiveStatusCode,
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Lightweight preview (UX-6) — the eager Details-tab fetch.
        if (request.url.path.contains('/preview')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': effectiveScript.id,
                'description': effectiveScript.description,
                'version': '1.0.0',
                'price': effectiveScript.price,
                'language': 'typescript',
                'preview': '// preview line 1',
                'previewTruncated': false,
                'totalLines': 1,
              },
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }

        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': effectiveScript.id,
              'title': effectiveScript.title,
              'description': effectiveScript.description,
              'category': effectiveScript.category,
              'tags': effectiveScript.tags,
              'author_id': effectiveScript.authorId,
              'author_name': effectiveScript.authorName,
              'bundle': effectiveScript.bundle,
              'price': effectiveScript.price,
              'downloads': effectiveScript.downloads,
              'rating': effectiveScript.rating,
              'review_count': effectiveScript.reviewCount,
              'created_at': effectiveScript.createdAt.toIso8601String(),
              'updated_at': effectiveScript.updatedAt.toIso8601String(),
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: effectiveScript),
      );
    }

    testWidgets('displays rating summary with average and count',
        (WidgetTester tester) async {
      final script = testScript.copyWith(rating: 4.2, reviewCount: 15);
      await pumpDialog(tester, script: script);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('4.2'), findsWidgets);
      expect(find.text('15 reviews'), findsOneWidget);
    });

    testWidgets('loads and displays reviews from service',
        (WidgetTester tester) async {
      final reviews = [
        ScriptReview(
          id: 'review-1',
          userId: 'user-1',
          scriptId: 'script-123',
          rating: 5,
          comment: 'Excellent script!',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
          updatedAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        ScriptReview(
          id: 'review-2',
          userId: 'user-2',
          scriptId: 'script-123',
          rating: 4,
          comment: 'Good but could be better',
          isVerifiedPurchase: false,
          status: 'approved',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
          updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];

      await pumpDialog(tester, reviews: reviews);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Excellent script!'), findsOneWidget);
      expect(find.text('Good but could be better'), findsOneWidget);
    });

    testWidgets('displays star rating for each review',
        (WidgetTester tester) async {
      final reviews = [
        ScriptReview(
          id: 'review-1',
          userId: 'user-1',
          scriptId: 'script-123',
          rating: 5,
          comment: 'Five stars!',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await pumpDialog(tester, reviews: reviews);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      final starIcons = find.byIcon(Icons.star);
      expect(starIcons, findsWidgets);
    });

    testWidgets('shows verified purchase badge for verified reviews',
        (WidgetTester tester) async {
      final reviews = [
        ScriptReview(
          id: 'review-1',
          userId: 'user-1',
          scriptId: 'script-123',
          rating: 5,
          comment: 'Verified purchase review',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await pumpDialog(tester, reviews: reviews);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('shows empty state when no reviews exist',
        (WidgetTester tester) async {
      await pumpDialog(tester, reviews: []);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
    });

    testWidgets('displays review date in relative format',
        (WidgetTester tester) async {
      final reviews = [
        ScriptReview(
          id: 'review-1',
          userId: 'user-1',
          scriptId: 'script-123',
          rating: 5,
          comment: 'Recent review',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

      await pumpDialog(tester, reviews: reviews);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      // The shared `formatDate` helper renders a relative "N days ago" string;
      // pin the exact formatted value (not just a digit that could appear
      // anywhere in the tree).
      expect(find.text('3 days ago'), findsOneWidget);
    });

    testWidgets('shows rating distribution breakdown',
        (WidgetTester tester) async {
      final reviews = [
        ScriptReview(
          id: 'review-1',
          userId: 'user-1',
          scriptId: 'script-123',
          rating: 5,
          comment: '5 star review',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptReview(
          id: 'review-2',
          userId: 'user-2',
          scriptId: 'script-123',
          rating: 4,
          comment: '4 star review',
          isVerifiedPurchase: true,
          status: 'approved',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptReview(
          id: 'review-3',
          userId: 'user-3',
          scriptId: 'script-123',
          rating: 5,
          comment: 'Another 5 star',
          isVerifiedPurchase: false,
          status: 'approved',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await pumpDialog(tester, reviews: reviews);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      // The distribution renders one LinearProgressIndicator bar per tier
      // [5,4,3,2,1] (in that order). Asserting the bar count proves the section
      // rendered; asserting the 5-star bar is fuller than the 4-star bar proves
      // the bars are data-driven (2 of 3 vs 1 of 3), not all-zero placeholders.
      final bars = find.byType(LinearProgressIndicator);
      expect(bars, findsNWidgets(5));
      final fiveStarValue =
          tester.widget<LinearProgressIndicator>(bars.at(0)).value!;
      final fourStarValue =
          tester.widget<LinearProgressIndicator>(bars.at(1)).value!;
      expect(fiveStarValue, greaterThan(fourStarValue),
          reason: 'two 5-star reviews vs one 4-star → 5-star bar must be fuller');
      // Empty tiers (3,2,1) are zeroed.
      expect(
          tester.widget<LinearProgressIndicator>(bars.at(2)).value!, equals(0.0));
    });
  });
}
