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

/// NF-1 — Round-6 UX review found that the Script Details dialog's wide
/// layout clipped its right-panel `Statistics` `Column` by up to ~92px at
/// small window heights (probe `A_details_interactive-counter` logged
/// `RenderFlex overflowed by 92 pixels on the bottom`; probe `H` at
/// 1440×900 logged `overflow_count=0`). The wide layout's right panel was a
/// non-flex `Column` with a `Spacer()` and no scroll view, so it clipped
/// instead of scrolling when it didn't fit.
///
/// The fix wraps that panel in `SingleChildScrollView` +
/// `ConstrainedBox(minHeight)` + `IntrinsicHeight` (the standard
/// "scroll when too big, fill when too small" pattern). This test pins the
/// acceptance gate: at a small window height (800×600) the panel emits NO
/// `FlutterError` overflow AND is wrapped in a scroll view, while all the
/// Statistics content remains reachable.
void main() {
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

  /// Pumps the dialog at the SMALL default widget-test surface (800×600).
  /// The dialog claims `MediaQuery.size.height * 0.85` ≈ 510 px tall, which
  /// is short enough to make the wide layout's right Statistics panel
  /// overflow before NF-1's fix (the same condition the buy_cta_test
  /// explicitly avoids by raising the surface to 1280×900).
  void useSmallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A script whose right-panel content is dense enough to overflow a small
  /// dialog: every stat item present (Downloads, Rating, Version, Updated)
  /// plus a 4-canister "Compatible Canisters" block (> 3, so the "... and N
  /// more" line also renders).
  MarketplaceScript buildScript() => MarketplaceScript(
        id: 'nf-1',
        title: 'NF-1 Overflow Probe',
        description: 'desc',
        category: 'Development',
        authorName: 'Tester',
        price: 0,
        downloads: 1234,
        rating: 4.5,
        reviewCount: 7,
        version: '1.4.2',
        canisterIds: const [
          // 4 canisters → forces the "... and 1 more" line in addition to
          // the 3 rendered bullets, maximizing right-panel height.
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'cccccccccccccccccccccccccccccccccccccccc',
          'dddddddddddddddddddddddddddddddddddddddd',
        ],
        bundle: 'print(1)',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 6, 1),
      );

  /// Mocks `/preview` to succeed (so the preview pane renders, not the gate)
  /// and Reviews/Versions to empty arrays (lazy-loaded, never selected here).
  MockClient successClient() {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/preview')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'nf-1',
              'description': 'desc',
              'version': '1.4.2',
              'price': 0.0,
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
      if (path.contains('/reviews') || path.contains('/versions')) {
        return http.Response(
          jsonEncode({'success': true, 'data': []}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });
  }

  Future<void> openDialog(WidgetTester tester, MarketplaceScript script) {
    return pumpDetailsDialog(
      tester,
      dialogBuilder: (_) => ScriptDetailsDialog(
        script: script,
        onDownload: () {},
      ),
    );
  }

  testWidgets(
      'NF-1: at a small window height the wide layout\'s right Statistics '
      'panel does NOT overflow and is wrapped in a scroll view',
      (tester) async {
    useSmallSurface(tester);
    service.overrideHttpClient(successClient());
    final script = buildScript();

    // Capture every FlutterError the framework reports during the pump so we
    // can assert NO RenderFlex overflow slipped through (the default test
    // binding would turn any such error into a test failure anyway; doing it
    // explicitly yields a clearer assertion message).
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    await openDialog(tester, script);

    // ACCEPTANCE GATE: no RenderFlex overflow (or any other FlutterError).
    expect(
      errors,
      isEmpty,
      reason: 'Statistics panel must scroll instead of clipping at small '
          'window heights (NF-1). Captured errors:\n'
          '${errors.map((e) => e.exceptionAsString()).join('\n')}',
    );

    // The wide layout is in force (the right panel exists). The dialog
    // switches to the narrow layout below maxWidth < 600; 800px wide with
    // default padding keeps the wide layout visible.
    expect(find.text('Statistics'), findsOneWidget);

    // Every stat item is present in the tree (not clipped out of existence).
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Compatible Canisters'), findsOneWidget);

    // The right panel is now wrapped in a SingleChildScrollView (the fix).
    final statisticsScroll = find.ancestor(
      of: find.text('Statistics'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      statisticsScroll,
      findsWidgets,
      reason: 'the wide-layout Statistics panel must be inside a '
          'SingleChildScrollView so it scrolls instead of clipping',
    );
  });

  testWidgets(
      'NF-1: at a normal desktop height the right panel still renders '
      'identically (Spacer pushes Compatible Canisters below Statistics)',
      (tester) async {
    // 1280×900 is the surface the buy_cta_test uses; at the dialog's 0.85
    // height factor it gives the right panel enough room that no overflow
    // occurs even pre-NF-1. The post-fix layout must remain visually
    // identical: Statistics present, Compatible Canisters present, no error.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    service.overrideHttpClient(successClient());
    final script = buildScript();

    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    await openDialog(tester, script);

    expect(errors, isEmpty, reason: 'no FlutterError at normal height');
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Compatible Canisters'), findsOneWidget);
  });
}
