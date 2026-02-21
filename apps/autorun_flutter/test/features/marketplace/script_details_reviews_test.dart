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
        luaSource: 'print("hello")',
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
              'lua_source': effectiveScript.luaSource,
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

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => ScriptDetailsDialog(
                        script: effectiveScript,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows reviews section for marketplace scripts',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      expect(find.text('Reviews'), findsOneWidget);
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
    });

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

      expect(find.textContaining('3'), findsWidgets);
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

      expect(find.text('5'), findsWidgets);
      expect(find.text('4'), findsWidgets);
    });
  });
}
