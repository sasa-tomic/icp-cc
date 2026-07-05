// Flow I — marketplace browse → details → download, driven as ONE user chain
// through a real app boot.
//
// This closes the MEDIUM test gap between the individual widget tests
// (script_details_* cover the dialog in isolation; b_download_test covers the
// WU-2 download SnackBar) by exercising the multi-screen CHAIN end-to-end:
// the marketplace list populates → tapping a tile opens the details dialog →
// Download completes and surfaces the success SnackBar. The UX-5 lazy-load
// contract (Reviews/Versions are NOT fetched until their tab is selected) is
// verified THROUGH the real dialog, not just the dialog widget alone.
//
// == DATA PATH — option (b): mock the HTTP transport with real-shape data. ==
// `just test-ux-probe` runs PASS 1 / PASS 2 with NO backend process, so option
// (a) (real `api-dev-up` + a seeded listing) would couple this probe to a live
// server the recipe never starts — fragile and non-hermetic. Instead we inject
// a counting MockClient into the MarketplaceOpenApiService singleton BEFORE
// app.main() (the established `overrideHttpClient` pattern from
// script_details_lazy_load_test.dart). The REAL widget tree — ScriptsScreen →
// ScriptsListItemTile → ScriptDetailsDialog → ScriptsScreenState._downloadScript
// → success SnackBar — runs completely unchanged; only the HTTP wire is
// deterministic. The Reviews/Versions request counters on the mock prove the
// UX-5 lazy-load timing through the real dialog.
//
// No profile / keyring required: marketplace browse + download are local-only
// (download persists via ScriptRepository; no signing, no secure storage), so
// this probe belongs in PASS 1 (keyring-less).
//
// Run: DISPLAY=:99 flutter test \
//        integration_test/ux_probe/i_marketplace_download_flow_test.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // --- Real-shape seed data (same JSON fields the production parser reads) ---
  const scriptId = 'script-uxprobe-chain';
  const scriptTitle = 'UX Probe Chain Script';
  const scriptBundle = '// deterministic seed bundle for the chain probe\n'
      'export function init() {\n'
      '  return { count: 0 };\n'
      '}\n'
      'export function view(state) {\n'
      '  return { type: "text", text: "hello" };\n'
      '}\n';
  final scriptJson = <String, dynamic>{
    'id': scriptId,
    'title': scriptTitle,
    'description': 'Seed listing for the browse -> details -> download chain.',
    'category': 'Utilities',
    'tags': const ['probe', 'utilities'],
    'author_id': 'author-uxprobe',
    'author_name': 'Probe Author',
    'price': 0,
    'downloads': 42,
    'rating': 4.5,
    'review_count': 3,
    'bundle': scriptBundle,
    'is_public': true,
    'created_at': DateTime(2024, 1, 1).toIso8601String(),
    'updated_at': DateTime(2024, 1, 2).toIso8601String(),
  };

  // Counters mutated by the mock closure to prove UX-5 lazy-load timing.
  int searchFetches = 0;
  int detailsFetches = 0;
  int reviewsFetches = 0;
  int versionsFetches = 0;
  int unexpectedFetches = 0;

  http.Client buildMockClient() {
    return MockClient((request) async {
      final method = request.method;
      final path = request.url.path;
      // Browse: POST /api/v1/scripts/search
      if (method == 'POST' && path.endsWith('/scripts/search')) {
        searchFetches++;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'scripts': [scriptJson],
              'total': 1,
              'hasMore': false,
            },
          }),
          200,
          headers: const {'Content-Type': 'application/json'},
        );
      }
      // Reviews tab: GET /api/v1/scripts/{id}/reviews
      if (method == 'GET' && path.contains('/reviews')) {
        reviewsFetches++;
        return http.Response(
          jsonEncode({'success': true, 'data': []}),
          200,
          headers: const {'Content-Type': 'application/json'},
        );
      }
      // Versions LIST: GET /api/v1/scripts/{id}/versions
      // (excludes single-version `/versions/{v}`, which the probe never hits.)
      if (method == 'GET' &&
          path.contains('/versions') &&
          !path.contains('/versions/')) {
        versionsFetches++;
        return http.Response(
          jsonEncode({'success': true, 'data': []}),
          200,
          headers: const {'Content-Type': 'application/json'},
        );
      }
      // Script details: GET /api/v1/scripts/{id}
      // (fired eagerly by the Details preview AND again by the download path.)
      if (method == 'GET' && RegExp(r'/scripts/[^/]+$').hasMatch(path)) {
        detailsFetches++;
        return http.Response(
          jsonEncode({'success': true, 'data': scriptJson}),
          200,
          headers: const {'Content-Type': 'application/json'},
        );
      }
      // Fail-loud: any other request means the chain touched something we
      // didn't intend — surface it instead of silently faking a response.
      unexpectedFetches++;
      // ignore: avoid_print
      print('I_MARKETPLACE: UNEXPECTED $method $path');
      return http.Response(
        jsonEncode({'success': false, 'error': 'unexpected $method $path'}),
        200,
        headers: const {'Content-Type': 'application/json'},
      );
    });
  }

  // Bounded wizard dismissal (pumpAndSettle never returns: the Scripts screen
  // kicks off marketplace fetches; same approach as the other round-2 probes).
  Future<void> dismissWizard(WidgetTester tester) async {
    int guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    if (present(find.byIcon(Icons.close), tester)) {
      await tester.tap(find.byIcon(Icons.close).first);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('I: browse -> details -> download chain through real app boot',
      (tester) async {
    // ---- Mock transport setup (option b) --------------------------------
    suppressDebugOutput = true;
    AppConfig.setTestEndpoint('https://uxprobe.mock');
    final service = MarketplaceOpenApiService();
    final client = buildMockClient();
    service.overrideHttpClient(client);
    addTearDown(() {
      client.close();
      service.resetHttpClient();
      suppressDebugOutput = false;
    });

    // ---- Launch the REAL app --------------------------------------------
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    // ====================================================================
    // STEP 1 — BROWSE: the marketplace list populates with the seed script.
    // ====================================================================
    bool listed = false;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (present(find.text(scriptTitle), tester)) {
        listed = true;
        break;
      }
    }
    // ignore: avoid_print
    print('I_MARKETPLACE: STEP1 browse listed=$listed '
        'searchFetches=$searchFetches');
    expect(listed, isTrue,
        reason: 'BROWSE: the marketplace tile must render after boot. '
            'searchFetches=$searchFetches');
    expect(searchFetches, greaterThanOrEqualTo(1),
        reason: 'BROWSE: /scripts/search must have been called at least once');

    // ====================================================================
    // STEP 2 — DETAILS: tap the tile -> dialog opens. UX-5 lazy-load must
    // hold: Reviews/Versions are NOT fetched until their tab is selected.
    // ====================================================================
    // Pre-condition: nothing lazy has been fetched yet.
    expect(reviewsFetches, 0,
        reason: 'UX-5: Reviews must not fetch before the dialog is opened');
    expect(versionsFetches, 0,
        reason: 'UX-5: Versions must not fetch before the dialog is opened');

    await tester.ensureVisible(find.text(scriptTitle).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(scriptTitle).first);

    // The transition under test: list tile -> ScriptDetailsDialog.
    // "Code Preview" exists only inside the dialog's Details tab.
    bool dialogOpen = false;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (present(find.text('Code Preview'), tester)) {
        dialogOpen = true;
        break;
      }
    }
    // ignore: avoid_print
    print('I_MARKETPLACE: STEP2 details dialogOpen=$dialogOpen '
        'detailsFetches=$detailsFetches reviewsFetches=$reviewsFetches '
        'versionsFetches=$versionsFetches');
    expect(dialogOpen, isTrue,
        reason: 'DETAILS: tapping a marketplace tile must open the '
            'ScriptDetailsDialog with the Details tab (Code Preview) visible.');
    expect(detailsFetches, greaterThanOrEqualTo(1),
        reason: 'DETAILS: the eager Details/preview fetch (getScriptDetails) '
            'must fire when the dialog opens');
    // UX-5 payoff through the real dialog: still no lazy fetches.
    expect(reviewsFetches, 0,
        reason: 'UX-5: opening the dialog fetches Details only — Reviews '
            'must stay deferred until the Reviews tab is selected');
    expect(versionsFetches, 0,
        reason: 'UX-5: opening the dialog fetches Details only — Versions '
            'must stay deferred until the Versions tab is selected');

    // ====================================================================
    // STEP 3 — DOWNLOAD: tap Download FREE -> the success SnackBar appears.
    // (This probe asserts the CHAIN completed browse -> details -> download;
    //  it intentionally does NOT re-assert WU-2's Run-action shape — that is
    //  b_download_test.dart's concern.)
    // ====================================================================
    final downloadBtn = find.text('Download FREE');
    expect(present(downloadBtn, tester), isTrue,
        reason: 'DOWNLOAD: the "Download FREE" action must be present for a '
            'free script inside the details dialog.');
    await tester.ensureVisible(downloadBtn.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(downloadBtn.first);

    // _downloadScript performs REAL file IO (ScriptController.createScript ->
    // ScriptRepository.persistScripts -> writeAsString). flutter_test's FakeAsync
    // clock (driven by tester.pump) does not service dart:io native ops, so we
    // interleave runAsync (drains the real event loop, letting the write
    // complete) with pump (fires _downloadScript's Future.delayed progress
    // timers + renders the resulting SnackBar).
    bool snackbarShown = false;
    String? failureText;
    for (int i = 0; i < 60; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));
      if (present(find.textContaining('added to your library'), tester)) {
        snackbarShown = true;
        break;
      }
      if (present(find.textContaining('Download failed'), tester)) {
        // Capture the full error message embedded in the SnackBar for diagnosis.
        final matches =
            tester.widgetList<Text>(find.textContaining('Download failed'));
        failureText = matches.isEmpty
            ? 'Download failed SnackBar shown (no Text node)'
            : matches.first.data ?? matches.first.toString();
        break;
      }
    }
    // ignore: avoid_print
    print('I_MARKETPLACE: STEP3 download snackbarShown=$snackbarShown '
        'failureText=$failureText detailsFetches=$detailsFetches');
    expect(snackbarShown, isTrue,
        reason: 'DOWNLOAD: tapping Download must surface the "added to your '
            'library" success SnackBar — proving the full chain (browse -> '
            'details -> download -> local ScriptRepository) completed. '
            'failureText=$failureText');

    // ====================================================================
    // STEP 4 — UX-5 lazy-load payoff: Reviews / Versions fetch ONLY when
    // their tab is selected (each exactly once on first selection).
    // ====================================================================
    await tester.tap(find.text('Reviews').first);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (reviewsFetches > 0) break;
    }
    await tester.tap(find.text('Versions').first);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (versionsFetches > 0) break;
    }
    // ignore: avoid_print
    print('I_MARKETPLACE: STEP4 lazy-load reviewsFetches=$reviewsFetches '
        'versionsFetches=$versionsFetches unexpectedFetches=$unexpectedFetches');
    expect(reviewsFetches, greaterThanOrEqualTo(1),
        reason: 'UX-5: selecting the Reviews tab must lazy-load reviews');
    expect(versionsFetches, greaterThanOrEqualTo(1),
        reason: 'UX-5: selecting the Versions tab must lazy-load versions');
    expect(unexpectedFetches, 0,
        reason: 'No unexpected HTTP calls should reach the mock transport');

    await shot(binding, 'i_marketplace_download_flow', tester);
  });
}
