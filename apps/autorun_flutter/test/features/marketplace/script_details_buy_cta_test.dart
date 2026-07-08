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

/// Buy-CTA coverage for `ScriptDetailsDialog`:
/// - PAID + NOT purchased → "Buy for $X" CTA present, no Download affordance.
/// - PAID + purchased → Download present, no Buy CTA.
/// - FREE → Download present, no Buy CTA.
/// - The preview-gate pane ALSO renders the Buy CTA when onBuy is provided
///   (so the user can purchase directly from the gated preview).
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

  /// Renders the dialog on a realistic desktop surface so the wide layout's
  /// right panel (Buy button + stats column) doesn't overflow the default
  /// 800×600 widget-test surface.
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  MarketplaceScript buildScript({
    required double price,
    bool? purchased,
  }) {
    return MarketplaceScript(
      id: 'script-$price-$purchased',
      title: 'S',
      description: 'desc',
      category: 'C',
      price: price,
      purchased: purchased,
      bundle: 'print(1)',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
  }

  /// Mocks /preview to SUCCEED so the gate pane does NOT render — isolates
  /// the primary action button. Reviews/versions return [].
  MockClient successPreviewClient() {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/preview')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 's',
              'preview': '// teaser line 1',
              'previewTruncated': true,
              'totalLines': 100,
              'price': 9.99,
              'version': '1.0.0',
            },
          }),
          200,
        );
      }
      if (path.contains('/reviews') || path.contains('/versions')) {
        return http.Response(
          jsonEncode({'success': true, 'data': []}),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
      );
    });
  }

  /// Mocks /preview to FAIL so the paid-gate pane renders (mirrors the
  /// existing script_details_preview_test harness). Used for the gate-pane
  /// Buy-CTA test.
  MockClient gatingClient() {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/preview')) {
        return http.Response(
          jsonEncode({'success': false, 'error': 'unavailable'}),
          500,
        );
      }
      if (path.contains('/reviews') || path.contains('/versions')) {
        return http.Response(
          jsonEncode({'success': true, 'data': []}),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
      );
    });
  }

  Future<void> openDialog(
    WidgetTester tester,
    MarketplaceScript script, {
    VoidCallback? onDownload,
    VoidCallback? onBuy,
  }) {
    return pumpDetailsDialog(
      tester,
      dialogBuilder: (_) => ScriptDetailsDialog(
        script: script,
        onDownload: onDownload,
        onBuy: onBuy,
      ),
    );
  }

  testWidgets(
      'PAID + NOT purchased: shows "Buy for \$X" as the primary action, '
      'does NOT show Download', (tester) async {
    useDesktopSurface(tester);
    service.overrideHttpClient(successPreviewClient());
    final script = buildScript(price: 9.99, purchased: false);
    var buyTaps = 0;
    var downloadTaps = 0;

    await openDialog(
      tester,
      script,
      onBuy: () => buyTaps++,
      onDownload: () => downloadTaps++,
    );

    // Preview succeeded → only the primary action Buy button renders (1).
    expect(find.text('Buy for \$9.99'), findsOneWidget);
    // No Download affordance for a paid, un-purchased script.
    expect(find.text('Download'), findsNothing);
    expect(find.text('Download FREE'), findsNothing);

    await tester.tap(find.text('Buy for \$9.99'));
    await tester.pumpAndSettle();
    expect(buyTaps, 1);
    expect(downloadTaps, 0,
        reason: 'Buy CTA must not side-effect a download');
  });

  testWidgets(
      'PAID + purchased: shows Download as the primary action, no Buy CTA',
      (tester) async {
    useDesktopSurface(tester);
    service.overrideHttpClient(successPreviewClient());
    final script = buildScript(price: 9.99, purchased: true);
    var buyTaps = 0;
    var downloadTaps = 0;

    await openDialog(
      tester,
      script,
      onBuy: () => buyTaps++,
      onDownload: () => downloadTaps++,
    );

    expect(find.text('Buy for \$9.99'), findsNothing,
        reason: 'a purchased script must not re-offer Buy');
    expect(find.text('Download'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(downloadTaps, 1);
    expect(buyTaps, 0);
  });

  testWidgets('FREE: shows Download FREE as the primary action, no Buy CTA',
      (tester) async {
    useDesktopSurface(tester);
    service.overrideHttpClient(successPreviewClient());
    final script = buildScript(price: 0, purchased: true);
    var buyTaps = 0;
    var downloadTaps = 0;

    await openDialog(
      tester,
      script,
      onBuy: () => buyTaps++,
      onDownload: () => downloadTaps++,
    );

    expect(find.text('Buy for \$0.00'), findsNothing);
    expect(find.text('Download FREE'), findsOneWidget);

    await tester.tap(find.text('Download FREE'));
    await tester.pumpAndSettle();
    expect(downloadTaps, 1);
    expect(buyTaps, 0);
  });

  testWidgets(
      'PAID + NOT purchased + preview gate: Buy CTA ALSO appears in the gated '
      'preview pane (so the user can purchase from the locked preview)',
      (tester) async {
    useDesktopSurface(tester);
    service.overrideHttpClient(gatingClient());
    final script = buildScript(price: 4.50, purchased: false);
    var buyTaps = 0;

    await openDialog(
      tester,
      script,
      onBuy: () => buyTaps++,
      onDownload: null, // no download affordance — must be gated
    );

    // Gate message renders (preview endpoint is mocked to fail).
    expect(find.text('Purchase to view source'), findsOneWidget);
    // Buy CTA appears in BOTH the primary action area AND the gated preview
    // pane (>= 2 occurrences) — the gate augments the message with the CTA
    // so the user can purchase without scrolling to the primary action.
    expect(find.text('Buy for \$4.50'), findsNWidgets(2));
  });

  testWidgets(
      'PAID + NOT purchased with NO onBuy: no primary action renders '
      '(deep-link context that intentionally offers no in-place purchase)',
      (tester) async {
    useDesktopSurface(tester);
    service.overrideHttpClient(successPreviewClient());
    final script = buildScript(price: 9.99, purchased: false);

    await openDialog(tester, script);

    expect(find.text('Buy for \$9.99'), findsNothing,
        reason: 'no onBuy callback → no Buy CTA');
    expect(find.text('Download'), findsNothing);
    expect(find.text('Download FREE'), findsNothing);
  });
}
