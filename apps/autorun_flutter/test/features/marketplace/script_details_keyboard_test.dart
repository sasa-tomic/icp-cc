// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';
import 'package:icp_autorun/widgets/script_details_reviews_tab.dart';
import 'package:icp_autorun/widgets/script_details_versions_tab.dart';

import '_marketplace_test_harness.dart';

/// UX-9 part B — keyboard-shortcut coverage for the Script Details dialog.
///
/// Asserts the three bindings the dialog exposes:
///  1. **Esc** closes the dialog. This is Flutter's dialog-route default
///     (Escape → DismissIntent → maybePop), NOT a custom handler — the test
///     pins the behaviour so a future refactor cannot silently regress it.
///  2. **→ / ←** switch tabs (Details → Reviews → Versions and back), going
///     through the dialog's `_selectTab` so lazy-load (UX-5) fires exactly as
///     it does for a mouse tap on the tab.
///  3. **←/→ stay inert** while the code-preview `SelectableText` has focus,
///     so the user can move the selection cursor without hijacking tabs.
///
/// `defaultTargetPlatform` is `android` inside `flutter_test`, which would
/// leave `DetailsDialogShortcuts` as a no-op pass-through. Each test forces a
/// desktop platform and restores it before the binding's invariant assertions
/// run (mirrors the `desktopTest` helper in
/// `test/widgets/keyboard_shortcuts_test.dart`).
void main() {
  group('ScriptDetailsDialog keyboard shortcuts (UX-9 part B)', () {
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

    /// The same counting MockClient used by `script_details_lazy_load_test` —
    /// counts review / version requests, returns empty arrays for both, and
    /// serves the script body for the eager preview download. Reused here so
    /// the arrow-key tests can assert lazy-load integration (→ triggers the
    /// Reviews fetch exactly once).
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
        if (path.contains('/versions') && !path.contains('/versions/')) {
          onVersion();
          return http.Response(
            jsonEncode({'success': true, 'data': []}),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
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

    Future<void> pumpDialog(
      WidgetTester tester, {
      required MockClient client,
    }) async {
      service.overrideHttpClient(client);
      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
      );
    }

    testWidgets(
        '→ traverses Details → Reviews → Versions, lazy-loading each tab once',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        int reviewsFetches = 0;
        int versionsFetches = 0;
        final client = countingClient(
          onReview: () => reviewsFetches++,
          onVersion: () => versionsFetches++,
        );
        addTearDown(client.close);
        await pumpDialog(tester, client: client);

        // Start: Details tab (neither Reviews nor Versions mounted or fetched).
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);
        expect(find.byType(ScriptDetailsVersionsTab), findsNothing);
        expect(reviewsFetches, 0);
        expect(versionsFetches, 0);

        // → : Details → Reviews (lazy-loads Reviews once).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsOneWidget,
            reason: '→ must move from Details to Reviews');
        expect(reviewsFetches, 1,
            reason: 'selecting Reviews via → must lazy-load it (UX-5)');

        // → : Reviews → Versions (lazy-loads Versions once).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsVersionsTab), findsOneWidget,
            reason: '→ must move from Reviews to Versions');
        expect(versionsFetches, 1,
            reason: 'selecting Versions via → must lazy-load it (UX-5)');

        // → at the last tab is a no-op (clamp): stays on Versions, no re-fetch.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsVersionsTab), findsOneWidget);
        expect(versionsFetches, 1, reason: '→ at Versions must clamp (no wrap)');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('← traverses back Versions → Reviews → Details',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        int reviewsFetches = 0;
        int versionsFetches = 0;
        final client = countingClient(
          onReview: () => reviewsFetches++,
          onVersion: () => versionsFetches++,
        );
        addTearDown(client.close);
        await pumpDialog(tester, client: client);

        // Walk to Versions first (→ →), then walk back with ←.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsVersionsTab), findsOneWidget);

        // ← : Versions → Reviews.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsOneWidget,
            reason: '← must move from Versions back to Reviews');

        // ← : Reviews → Details (neither tab widget mounted on Details).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);
        expect(find.byType(ScriptDetailsVersionsTab), findsNothing,
            reason: '← must move from Reviews back to Details');

        // ← at the first tab is a no-op (clamp): stays on Details.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);

        // No re-fetches from the back-tour (cache holds, per UX-5).
        expect(reviewsFetches, 1);
        expect(versionsFetches, 1);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Esc closes the dialog (framework dialog-route default)',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        int reviewsFetches = 0;
        int versionsFetches = 0;
        final client = countingClient(
          onReview: () => reviewsFetches++,
          onVersion: () => versionsFetches++,
        );
        addTearDown(client.close);
        await pumpDialog(tester, client: client);

        expect(find.byType(ScriptDetailsDialog), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(ScriptDetailsDialog), findsNothing,
            reason: 'Esc must dismiss the dialog');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets(
        '←/→ stay inert while the code-preview SelectableText is focused',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        int reviewsFetches = 0;
        int versionsFetches = 0;
        final client = countingClient(
          onReview: () => reviewsFetches++,
          onVersion: () => versionsFetches++,
        );
        addTearDown(client.close);
        await pumpDialog(tester, client: client);

        // Focus the code-preview SelectableText (an EditableText lives inside
        // it, so the guarded arrow action must refuse to fire).
        final selectable = find.byType(SelectableText);
        expect(selectable, findsWidgets,
            reason: 'the Details tab renders a code preview SelectableText');
        await tester.tap(selectable.first);
        await tester.pump();

        // → while the preview is focused: must NOT switch tabs / fetch.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing,
            reason: '→ must stay inert while the preview holds focus');
        expect(reviewsFetches, 0);

        // ← while the preview is focused: must NOT switch either.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);
        expect(find.byType(ScriptDetailsVersionsTab), findsNothing);
        expect(versionsFetches, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('surfaces the Esc + ←/→ bindings as discoverable tooltips',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        int reviewsFetches = 0;
        int versionsFetches = 0;
        final client = countingClient(
          onReview: () => reviewsFetches++,
          onVersion: () => versionsFetches++,
        );
        addTearDown(client.close);
        await pumpDialog(tester, client: client);

        // Close button tooltip names the Esc binding.
        expect(find.byTooltip('Close (Esc)'), findsOneWidget);
        // Tab bar tooltip surfaces the ←/→ traversal binding.
        expect(find.byTooltip('Switch tabs with ← / → arrows'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('←/→ are inert on mobile (pass-through, no fetch, no switch)',
        (tester) async {
      // defaultTargetPlatform stays android → DetailsDialogShortcuts is a
      // pass-through. Arrow keys must do nothing (no tab switch, no fetch).
      int reviewsFetches = 0;
      int versionsFetches = 0;
      final client = countingClient(
        onReview: () => reviewsFetches++,
        onVersion: () => versionsFetches++,
      );
      addTearDown(client.close);
      await pumpDialog(tester, client: client);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(find.byType(ScriptDetailsReviewsTab), findsNothing);
      expect(reviewsFetches, 0);
      expect(versionsFetches, 0);
    });
  });
}
