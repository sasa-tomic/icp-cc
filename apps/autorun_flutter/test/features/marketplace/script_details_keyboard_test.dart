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

import '_marketplace_test_harness.dart';

/// UX-9 part B — keyboard-shortcut coverage for the Script Details dialog.
///
/// Asserts the three bindings the dialog exposes:
///  1. **Esc** closes the dialog. This is Flutter's dialog-route default
///     (Escape → DismissIntent → maybePop), NOT a custom handler — the test
///     pins the behaviour so a future refactor cannot silently regress it.
///  2. **→ / ←** switch tabs (Details ↔ Reviews), going through the dialog's
///     `_selectTab` so lazy-load (UX-5) fires exactly as it does for a mouse
///     tap on the tab. (W7-8: the Versions tab was removed — the strip is now
///     Details (0) + Reviews (1).)
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
    /// serves the lightweight `/preview` payload for the eager Details-tab
    /// preview load (UX-6). Reused here so the arrow-key tests can assert
    /// lazy-load integration (→ triggers the Reviews fetch exactly once).
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
        // Lightweight preview (UX-6) — the eager Details-tab fetch.
        if (path.contains('/preview')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': testScript.id,
                'description': testScript.description,
                'version': '1.0.0',
                'price': testScript.price,
                'language': 'typescript',
                'preview': '// preview line 1\n// preview line 2',
                'previewTruncated': false,
                'totalLines': 2,
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
        '→ traverses Details → Reviews, lazy-loading Reviews once (W7-8: '
        'Versions tab removed)', (tester) async {
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

        // Start: Details tab (Reviews not mounted or fetched).
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);
        expect(reviewsFetches, 0);
        expect(versionsFetches, 0);

        // → : Details → Reviews (lazy-loads Reviews once).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsOneWidget,
            reason: '→ must move from Details to Reviews');
        expect(reviewsFetches, 1,
            reason: 'selecting Reviews via → must lazy-load it (UX-5)');

        // → at the last tab is a no-op (clamp): stays on Reviews, no re-fetch.
        // (W7-8: with Versions gone, Reviews is now the right edge.)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsOneWidget);
        expect(reviewsFetches, 1, reason: '→ at Reviews must clamp (no wrap)');
        expect(versionsFetches, 0,
            reason: 'no /versions fetch — Versions tab is hidden (W7-8)');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('← traverses back Reviews → Details (W7-8: 2-tab strip)',
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

        // Walk to Reviews first (→), then walk back with ←.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsOneWidget);

        // ← : Reviews → Details.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing,
            reason: '← must move from Reviews back to Details');

        // ← at the first tab is a no-op (clamp): stays on Details.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ScriptDetailsReviewsTab), findsNothing);

        // No re-fetches from the back-tour (cache holds, per UX-5). And no
        // /versions fetch ever (W7-8: Versions tab is hidden).
        expect(reviewsFetches, 1);
        expect(versionsFetches, 0);
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
        // it, so the guarded arrow action must refuse to fire). A `tester.tap`
        // is unreliable here: with rich script data the dialog grows tall and
        // the SelectableText is off-screen, so the tap misses its target and
        // focus never moves. Drive focus directly via EditableTextState.
        final selectable = find.byType(SelectableText);
        expect(selectable, findsWidgets,
            reason: 'the Details tab renders a code preview SelectableText');
        final editable = find.descendant(
          of: selectable.first,
          matching: find.byType(EditableText),
        );
        expect(editable, findsOneWidget);
        final editableState =
            tester.state(editable.first) as EditableTextState;
        editableState.requestKeyboard();
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
        expect(versionsFetches, 0,
            reason: 'no /versions fetch — Versions tab is hidden (W7-8)');
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
