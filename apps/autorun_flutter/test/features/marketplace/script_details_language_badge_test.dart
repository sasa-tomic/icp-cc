import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// UXR5-2 — the Script Details dialog language badge must reflect the bundle's
/// REAL content (as detected by the backend), never a hardcoded "TypeScript".
///
/// The badge is driven by `ScriptPreview.language` returned from
/// `GET /scripts/:id/preview`:
///  - `"typescript"` → renders "TypeScript".
///  - `"lua"` → renders "Legacy Lua" (stale; cannot run in the TS/QuickJS
///    runtime). MUST NOT render "TypeScript".
///  - `"unknown"` / absent → renders NO badge (honest silence over a wrong
///    claim).
///
/// The acceptance gate (the bug this fixes): a Lua bundle's badge must NOT
/// say "TypeScript".
void main() {
  group('ScriptDetailsDialog language badge (UXR5-2)', () {
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

    MarketplaceScript script() => MarketplaceScript(
          id: 'script-lang',
          title: 'Language Badge Script',
          description: 'A script whose badge is under test',
          category: 'Development',
          tags: const ['test'],
          authorName: 'Test Author',
          price: 0,
          downloads: 1,
          rating: 4.0,
          reviewCount: 1,
          bundle: '// bundle content',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
        );

    /// Builds the `/preview` JSON response with a given `language` value — the
    /// field the backend now populates via content-based detection.
    String previewJson(String language) => jsonEncode({
          'success': true,
          'data': {
            'id': 'script-lang',
            'description': 'A script whose badge is under test',
            'version': '1.0.0',
            'price': 0.0,
            'language': language,
            'preview': '// preview line 1\n// preview line 2',
            'previewTruncated': false,
            'totalLines': 2,
          },
        });

    http.Response ok(String body) => http.Response(
          body,
          200,
          headers: {'Content-Type': 'application/json'},
        );

    Future<void> openDialog(WidgetTester tester) {
      return pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(script: script()),
      );
    }

    testWidgets(
        'TypeScript content: badge renders "TypeScript"', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/preview')) {
          return ok(previewJson('typescript'));
        }
        return ok(jsonEncode({'success': true, 'data': []}));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester);

      expect(find.text('TypeScript'), findsOneWidget);
    });

    testWidgets(
        'Lua content: badge renders "Legacy Lua", NOT "TypeScript" '
        '(acceptance gate)', (tester) async {
      // THE BUG: before UXR5-2 the badge was a hardcoded "TypeScript" literal,
      // so a stale Lua bundle was mislabeled as TypeScript. This test pins the
      // fix: a Lua-detected preview shows the honest "Legacy Lua" badge.
      final client = MockClient((request) async {
        if (request.url.path.contains('/preview')) {
          return ok(previewJson('lua'));
        }
        return ok(jsonEncode({'success': true, 'data': []}));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester);

      // The honest badge for stale Lua content:
      expect(find.text('Legacy Lua'), findsOneWidget);
      // And the badge MUST NOT lie:
      expect(find.text('TypeScript'), findsNothing,
          reason: 'a Lua bundle must never be badged "TypeScript"');
    });

    testWidgets(
        'Unknown content: no language badge renders (honest silence)',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/preview')) {
          return ok(previewJson('unknown'));
        }
        return ok(jsonEncode({'success': true, 'data': []}));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await openDialog(tester);

      // Unknown → no badge at all (prefer silence over a wrong claim).
      expect(find.text('TypeScript'), findsNothing);
      expect(find.text('Legacy Lua'), findsNothing);
    });
  });
}
