// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// W7-8 — the Versions tab is HIDDEN from the Script Details dialog.
///
/// Root cause (empirically verified 2026-07-14): the backend ships NO
/// `GET /api/v1/scripts/:id/versions` route
/// (`grep "scripts/:id" backend/src/main.rs` lists every route — `/versions`
/// is absent; `curl /api/v1/scripts/interactive-counter/versions` → 404 "not
/// found" for every script). The dialog's `_loadVersions()` maps that 404 to
/// `[]` (`marketplace_open_api_service.dart` `getScriptVersions`), so the
/// Versions tab was PERMANENTLY in its "No version history" empty-state — a
/// labelled tab that can never hold content. Live (Wave-7 UX audit) the tab
/// rendered completely blank in the real dialog (the Wave-6 "fix" only
/// regression-tested the tab widget in isolation, bypassing the dialog's real
/// layout/lazy-load path; the dialog-mounted test was added but a residual
/// blank-panel survived in production).
///
/// Honest fix (YAGNI): don't ship a tab that's permanently empty. The tab
/// widget + service plumbing (`getScriptVersions`, `ScriptVersion`,
/// `DiffViewerDialog`, `ScriptDetailsVersionsTab`) are removed in the same
/// commit (no other callers — `main.dart` / `scripts_screen.dart` never passed
/// `installedVersion` / `onInstallVersion`, so the tab's CTAs were also
/// permanently dead). Restore the whole stack together when a `/versions`
/// backend route lands.
///
/// This is the test Wave-6 SHOULD have written: it mounts the tab VIA THE
/// DIALOG (the real layout path) and asserts the dead tab is GONE — not just
/// that the widget renders its empty-state in isolation.
void main() {
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

  /// A mock that faithfully mirrors the LIVE backend: `/preview` 200, `/reviews`
  /// 200, and `/versions` 404 with a PLAIN-TEXT body (exactly what the running
  /// backend returns — `curl …/versions` → `404 not found`). Counts `/versions`
  /// hits so the test can prove hiding the tab also kills the dead fetch.
  MockClient liveLikeClient({required void Function() onVersionFetch}) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/versions') && !path.contains('/versions/')) {
        onVersionFetch();
        // Mirror the real backend's 404 body verbatim — `getScriptVersions`
        // short-circuits on the status code, but faithful mocks catch any
        // future regression where the short-circuit drifts.
        return http.Response('not found', 404);
      }
      if (path.contains('/reviews')) {
        return http.Response(
          jsonEncode({'success': true, 'data': <dynamic>[]}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }
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
              'preview': '// preview',
              'previewTruncated': false,
              'totalLines': 1,
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'data': <String, dynamic>{}}),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });
  }

  Future<void> pumpDialog(WidgetTester tester) async {
    await pumpDetailsDialog(
      tester,
      dialogBuilder: (_) => ScriptDetailsDialog(script: testScript),
    );
  }

  testWidgets(
      'W7-8: the dialog advertises only Details + Reviews — no "Versions" tab '
      '(no /versions backend route; the tab was permanently empty)', (tester) async {
    int versionFetches = 0;
    final client = liveLikeClient(onVersionFetch: () => versionFetches++);
    service.overrideHttpClient(client);
    addTearDown(client.close);

    await pumpDialog(tester);

    // The two tabs that have a real backend route are present.
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    // The dead tab is GONE — the headline W7-8 assertion.
    expect(find.text('Versions'), findsNothing,
        reason: 'Versions tab is hidden: backend has no /versions route, so '
            'the tab was permanently in its empty-state. YAGNI — restore the '
            'tab together with a /versions backend route.');
  });

  testWidgets(
      'W7-8: no /versions network call is ever issued from the dialog '
      '(no tab → no lazy fetch)', (tester) async {
    int versionFetches = 0;
    final client = liveLikeClient(onVersionFetch: () => versionFetches++);
    service.overrideHttpClient(client);
    addTearDown(client.close);

    await pumpDialog(tester);

    // Tour every remaining tab — none should trigger a /versions fetch.
    await tester.tap(find.text('Reviews'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(versionFetches, 0,
        reason: 'with the Versions tab hidden, the dialog must never issue a '
            '/versions request (the route 404s on the backend anyway)');
  });
}
