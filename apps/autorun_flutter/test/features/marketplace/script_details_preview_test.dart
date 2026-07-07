import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// UX-6 — the Script Details dialog must render its code preview from the
/// lightweight `GET /scripts/:id/preview` endpoint instead of downloading the
/// full bundle, and it must NEVER full-download a paid script for preview.
///
/// Four branches are pinned here, one per test:
///  1. FREE script, preview OK → hits `/preview`, does NOT hit the full
///     `/scripts/:id` download; renders the lightweight preview text.
///  2. FREE script, preview FAILS → falls back to the legacy full download
///     (`GET /scripts/:id`); renders `take(50)` of the bundle.
///  3. PAID script, preview OK → hits `/preview` only; never hits the full
///     download (the teaser cap is enforced server-side, so this is the path
///     that must run for paid scripts in practice).
///  4. PAID script, preview FAILS → NEVER falls back to full download; shows
///     the "Purchase to view source" gate message.
void main() {
  group('ScriptDetailsDialog preview (UX-6)', () {
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

    MarketplaceScript freeScript() => MarketplaceScript(
          id: 'script-free',
          title: 'Free Script',
          description: 'A free script description',
          category: 'Development',
          tags: const ['test'],
          authorName: 'Test Author',
          price: 0,
          downloads: 10,
          rating: 4.0,
          reviewCount: 3,
          bundle:
              List.generate(100, (i) => 'free bundle line ${i + 1}').join('\n'),
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
        );

    MarketplaceScript paidScript() => MarketplaceScript(
          id: 'script-paid',
          title: 'Paid Script',
          description: 'A paid script description',
          category: 'Development',
          tags: const ['test'],
          authorName: 'Test Author',
          price: 9.99,
          downloads: 5,
          rating: 4.5,
          reviewCount: 2,
          bundle:
              List.generate(100, (i) => 'paid bundle line ${i + 1}').join('\n'),
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
        );

    /// The lightweight preview payload the backend returns for a free script
    /// (server-side cap = 50 lines). Uses a distinctive sentinel so the test
    /// can prove the pane renders THIS text (not the full bundle).
    String freePreviewJson() => jsonEncode({
          'success': true,
          'data': {
            'id': 'script-free',
            'description': 'A free script description',
            'version': '1.2.0',
            'price': 0.0,
            'language': 'typescript',
            'preview':
                List.generate(50, (i) => '// preview line ${i + 1}').join('\n'),
            'previewTruncated': true,
            'totalLines': 100,
          },
        });

    String paidPreviewJson() => jsonEncode({
          'success': true,
          'data': {
            'id': 'script-paid',
            'description': 'A paid script description',
            'version': '1.2.0',
            'price': 9.99,
            'language': 'typescript',
            'preview':
                List.generate(20, (i) => '// teaser line ${i + 1}').join('\n'),
            'previewTruncated': true,
            'totalLines': 100,
          },
        });

    /// Full-script JSON used by the legacy download fallback
    /// (`downloadScript` → `getScriptDetails`).
    String fullScriptJson(MarketplaceScript script) => jsonEncode({
          'success': true,
          'data': {
            'id': script.id,
            'title': script.title,
            'description': script.description,
            'category': script.category,
            'tags': script.tags,
            'author_name': script.authorName,
            'bundle': script.bundle,
            'price': script.price,
            'downloads': script.downloads,
            'rating': script.rating,
            'review_count': script.reviewCount,
            'created_at': script.createdAt.toIso8601String(),
            'updated_at': script.updatedAt.toIso8601String(),
          },
        });

    http.Response ok(String body) => http.Response(
          body,
          200,
          headers: {'Content-Type': 'application/json'},
        );

    http.Response serverError() => http.Response(
          jsonEncode({'success': false, 'error': 'preview unavailable'}),
          500,
          headers: {'Content-Type': 'application/json'},
        );

    /// Asserts the lazy-load invariants the preview path must respect too:
    /// Reviews / Versions must not be fetched on dialog open. The mock routes
    /// those to empty arrays so the dialog never throws mid-build.
    MockClient buildClient({
      required MarketplaceScript script,
      required http.Response Function() previewResponse,
      required http.Response Function() fullDetailsResponse,
      required void Function() onPreview,
      required void Function() onFullDetails,
    }) {
      return MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/preview')) {
          onPreview();
          return previewResponse();
        }
        // Exact full-details fetch (the legacy `downloadScript` →
        // `getScriptDetails` path). Match `/scripts/<id>` with no trailing
        // segment, NOT `/scripts/<id>/preview`.
        final detailsPath = '/api/v1/scripts/${script.id}';
        if (path == detailsPath) {
          onFullDetails();
          return fullDetailsResponse();
        }
        if (path.contains('/reviews') || path.contains('/versions')) {
          return ok(jsonEncode({'success': true, 'data': []}));
        }
        return ok(fullScriptJson(script));
      });
    }

    Future<void> openDialog(WidgetTester tester, MarketplaceScript script) {
      return pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: script),
      );
    }

    testWidgets(
        'FREE script: dialog renders the lightweight preview and does NOT '
        'full-download', (tester) async {
      final script = freeScript();
      int previewFetches = 0;
      int fullFetches = 0;

      final client = buildClient(
        script: script,
        previewResponse: () => ok(freePreviewJson()),
        fullDetailsResponse: () => ok(fullScriptJson(script)),
        onPreview: () => previewFetches++,
        onFullDetails: () => fullFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester, script);

      expect(previewFetches, 1, reason: 'free preview must call /preview');
      expect(fullFetches, 0,
          reason: 'free script must NOT full-download when /preview succeeds');
      // Renders the lightweight payload (inside a SelectableText, so use
      // textContaining — the widget holds the whole multi-line preview
      // string), not the bundle.
      expect(find.textContaining('// preview line 1'), findsOneWidget);
      expect(find.textContaining('free bundle line'), findsNothing,
          reason: 'the full bundle must not be rendered on the preview path');
    });

    testWidgets(
        'FREE script: when /preview fails, falls back to the full download '
        'and renders take(50) of the bundle', (tester) async {
      final script = freeScript();
      int previewFetches = 0;
      int fullFetches = 0;

      final client = buildClient(
        script: script,
        previewResponse: serverError,
        fullDetailsResponse: () => ok(fullScriptJson(script)),
        onPreview: () => previewFetches++,
        onFullDetails: () => fullFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester, script);

      expect(previewFetches, 1, reason: 'preview endpoint must be attempted');
      expect(fullFetches, 1,
          reason: 'free script must fall back to the full download');
      // take(50) of the bundle: first line is present, line 51 is not.
      expect(find.textContaining('free bundle line 1'), findsOneWidget);
      expect(find.textContaining('free bundle line 51'), findsNothing);
    });

    testWidgets(
        'PAID script: dialog renders the capped teaser via /preview and does '
        'NOT full-download', (tester) async {
      final script = paidScript();
      int previewFetches = 0;
      int fullFetches = 0;

      final client = buildClient(
        script: script,
        previewResponse: () => ok(paidPreviewJson()),
        fullDetailsResponse: () => ok(fullScriptJson(script)),
        onPreview: () => previewFetches++,
        onFullDetails: () => fullFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester, script);

      expect(previewFetches, 1, reason: 'paid preview must call /preview');
      expect(fullFetches, 0,
          reason: 'paid script must NEVER full-download for preview');
      // Renders the server-capped teaser (inside a SelectableText), never the
      // bundle.
      expect(find.textContaining('// teaser line 1'), findsOneWidget);
      expect(find.textContaining('paid bundle line'), findsNothing,
          reason: 'the paid bundle must not be rendered');
    });

    testWidgets(
        'PAID script: when /preview fails, NEVER full-downloads — shows the '
        'purchase gate instead', (tester) async {
      final script = paidScript();
      int previewFetches = 0;
      int fullFetches = 0;

      final client = buildClient(
        script: script,
        previewResponse: serverError,
        fullDetailsResponse: () => ok(fullScriptJson(script)),
        onPreview: () => previewFetches++,
        onFullDetails: () => fullFetches++,
      );
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester, script);

      expect(previewFetches, 1, reason: 'preview endpoint must be attempted');
      expect(fullFetches, 0,
          reason: 'paid script must NEVER fall back to full download — '
              'that would ship paid source the user has not purchased');
      // Purchase gate renders (this is expected UX, not an error string).
      expect(find.text('Purchase to view source'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // The description (already on `widget.script`) is still shown.
      expect(find.text('A paid script description'), findsWidgets);
      // The paid bundle must never appear.
      expect(find.textContaining('paid bundle line'), findsNothing);
      // And no red error string for the gate (it is not an error).
      expect(find.textContaining('Failed to load preview'), findsNothing);
    });
  });
}
