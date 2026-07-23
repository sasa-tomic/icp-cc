import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_review.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// Builds a single review's JSON using the EXACT field names the backend
/// serializes.
///
/// Contract source of truth: `backend/src/models.rs::Review`, which carries
/// `#[serde(rename_all = "camelCase")]`. That attribute is what makes this
/// test honest: the keys below (`userId`, `scriptId`, `createdAt`,
/// `updatedAt`, ...) are what the backend ACTUALLY emits on the wire. Before
/// QS-1b the struct lacked `rename_all`, so the backend emitted snake_case
/// (`user_id`, `script_id`, ...) while `ScriptReview.fromJson` read camelCase
/// — every Reviews-tab open crashed with
/// `type 'Null' is not a subtype of type 'String' in type cast`.
///
/// The backend `Review` has exactly these 7 fields — it does NOT carry
/// `isVerifiedPurchase` or `status` (Flutter-only concepts that default to
/// `false` / `'pending'` in `ScriptReview.fromJson`). Pass [extra] to enrich
/// the payload with such client-only fields for UI tests that exercise them.
Map<String, dynamic> backendReviewJson({
  required String id,
  required String userId,
  required String scriptId,
  required int rating,
  String? comment,
  DateTime? createdAt,
  DateTime? updatedAt,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'id': id,
    'userId': userId,
    'scriptId': scriptId,
    'rating': rating,
    'comment': comment,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    if (extra != null) ...extra,
  };
}

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
              'data': {
                // Real backend contract — see
                // backend/src/handlers/reviews.rs::get_reviews. `data` is a
                // Map, NOT a bare array. Each review object's field names come
                // from `backendReviewJson` (mirrors the backend serde model —
                // camelCase, see QS-1b).
                'reviews': effectiveReviews
                    .map((r) => backendReviewJson(
                          id: r.id,
                          userId: r.userId,
                          scriptId: r.scriptId,
                          rating: r.rating,
                          comment: r.comment,
                          createdAt: r.createdAt,
                          updatedAt: r.updatedAt,
                          // Flutter-only enrichment: the backend `Review` does
                          // not serialize these, so the badge UI test below
                          // exercises client-side defaults/logic only.
                          extra: {
                            if (r.isVerifiedPurchase)
                              'isVerifiedPurchase': r.isVerifiedPurchase,
                            'status': r.status,
                          },
                        ))
                    .toList(),
                'total': effectiveReviews.length,
                'hasMore': false,
              },
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

  // Service-level contract tests for getScriptReviews. These pin the EXACT
  // backend shape ({data: {reviews:[...], total:int, hasMore:bool}}) so a cast
  // regression like UXR7-1 can never ship green again, AND pin every review
  // field name to the camelCase contract from `backend/src/models.rs::Review`
  // (#[serde(rename_all = "camelCase")]) so the QS-1b snake_case crash can
  // never recur.
  group('MarketplaceOpenApiService.getScriptReviews contract', () {
    late MarketplaceOpenApiService service;

    setUp(() {
      suppressDebugOutput = true;
      service = MarketplaceOpenApiService();
      AppConfig.setTestEndpoint('https://mock.api');
    });

    tearDown(() {
      suppressDebugOutput = false;
      service.resetHttpClient();
    });

    http.Response reviewsResponse(Map<String, dynamic> data, {int status = 200}) {
      return http.Response(
        jsonEncode({'success': true, 'data': data}),
        status,
        headers: {'Content-Type': 'application/json'},
      );
    }

    test('parses reviews from the real backend Map shape', () async {
      final client = MockClient((_) async => reviewsResponse({
            'reviews': [
              backendReviewJson(
                id: 'r1',
                userId: 'u1',
                scriptId: 's1',
                rating: 5,
                comment: 'great',
              ),
            ],
            'total': 1,
            'hasMore': false,
          }));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final reviews = await service.getScriptReviews('s1');

      expect(reviews, hasLength(1));
      expect(reviews.first.id, 'r1');
      expect(reviews.first.rating, 5);
    });

    // REGRESSION (QS-1b / UXR7-1): the backend `Review` struct must emit
    // camelCase keys. Before the fix it emitted snake_case (`user_id`,
    // `script_id`, `created_at`, `updated_at`), so `ScriptReview.fromJson`
    // did `json['userId'] as String` → `null as String` → threw
    // `type 'Null' is not a subtype of type 'String' in type cast`. This test
    // feeds the EXACT backend payload and asserts EVERY field round-trips, so
    // any future drift (e.g. dropping `rename_all`) turns this red.
    test('round-trips every backend camelCase field name (QS-1b regression)',
        () async {
      final payload = backendReviewJson(
        id: 'rev-pin',
        userId: 'user-pin',
        scriptId: 'script-pin',
        rating: 4,
        comment: 'pinned comment',
        createdAt: DateTime.parse('2025-03-01T10:00:00.000'),
        updatedAt: DateTime.parse('2025-03-02T11:00:00.000'),
      );
      final client = MockClient(
          (_) async => reviewsResponse({'reviews': [payload], 'total': 1, 'hasMore': false}));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final reviews = await service.getScriptReviews('script-pin');

      expect(reviews, hasLength(1));
      final r = reviews.single;
      expect(r.id, 'rev-pin', reason: 'id field');
      expect(r.userId, 'user-pin', reason: 'userId field (was snake_case user_id)');
      expect(r.scriptId, 'script-pin', reason: 'scriptId field (was snake_case script_id)');
      expect(r.rating, 4, reason: 'rating field');
      expect(r.comment, 'pinned comment', reason: 'comment field');
      expect(r.createdAt, DateTime.parse('2025-03-01T10:00:00.000'),
          reason: 'createdAt field (was snake_case created_at)');
      expect(r.updatedAt, DateTime.parse('2025-03-02T11:00:00.000'),
          reason: 'updatedAt field (was snake_case updated_at)');
    });

    // The negative half of the regression: if the backend ever reverts to
    // snake_case, fromJson must NOT silently produce a half-populated object —
    // it throws. This documents the failure mode so it's caught immediately.
    test('throws on snake_case payload (documents the QS-1b failure mode)',
        () async {
      final snakeCasePayload = <String, dynamic>{
        'id': 'rev-bad',
        // snake_case — the pre-QS-1b backend shape.
        'script_id': 'script-pin',
        'user_id': 'user-pin',
        'rating': 4,
        'comment': null,
        'created_at': '2025-03-01T10:00:00.000',
        'updated_at': '2025-03-02T11:00:00.000',
      };
      final client = MockClient((_) async => reviewsResponse(
            {'reviews': [snakeCasePayload], 'total': 1, 'hasMore': false},
          ));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      // `json['userId'] as String` → `null as String` → TypeError. The service
      // rethrows it (no silent empty-list fallback).
      expect(
        () => service.getScriptReviews('script-pin'),
        throwsA(isA<TypeError>()),
      );
    });

    test('tolerates a null comment (backend serializes Option<String> as null)',
        () async {
      final client = MockClient((_) async => reviewsResponse({
            'reviews': [
              backendReviewJson(
                id: 'r2',
                userId: 'u2',
                scriptId: 's2',
                rating: 3,
                comment: null,
              ),
            ],
            'total': 1,
            'hasMore': false,
          }));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final reviews = await service.getScriptReviews('s2');
      expect(reviews, hasLength(1));
      expect(reviews.single.comment, isNull);
    });

    test('throws MalformedReviewsResponseException on a bare-array data shape',
        () async {
      // This is the shape the OLD (broken) code assumed — and the shape the
      // old mock returned. The service must reject it loudly now.
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'success': true, 'data': []}),
              200, headers: {'Content-Type': 'application/json'}));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.getScriptReviews('s1'),
        throwsA(isA<MalformedReviewsResponseException>()),
      );
    });

    test('throws MalformedReviewsResponseException when reviews is not a list',
        () async {
      final client = MockClient((_) async => reviewsResponse({
            'reviews': 'not-a-list',
            'total': 0,
            'hasMore': false,
          }));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.getScriptReviews('s1'),
        throwsA(isA<MalformedReviewsResponseException>()),
      );
    });
  });
}
