// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// W6-8: "Compatible Canisters" used to truncate ids as
/// `• ryjl3-tyaaa-aaaaa-aa…` with NO way to read or copy the full id. The fix
/// shows the FULL id in a monospace font and makes each row tappable to copy
/// (with a "Copied" SnackBar). These tests pin that behaviour for BOTH the wide
/// and narrow layouts.

/// Clipboard mock helpers that use the non-deprecated
/// `defaultBinaryMessenger` API.
void testerBindingDefaultMessengerSetMockHandler() {
  TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      _lastCopiedText =
          (call.arguments as Map?)?['text'] as String? ?? _lastCopiedText;
    }
    return null;
  });
}

void testerBindingDefaultMessengerClearMockHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}

void main() {
  late MarketplaceOpenApiService service;

  setUp(() {
    suppressDebugOutput = true;
    service = MarketplaceOpenApiService();
    AppConfig.setTestEndpoint('https://mock.api');
    // Stub the clipboard platform channel so tap-to-copy can be verified
    // deterministically without a real platform clipboard.
    testerBindingDefaultMessengerSetMockHandler();
  });

  tearDown(() {
    suppressDebugOutput = false;
    service.resetHttpClient();
    testerBindingDefaultMessengerClearMockHandler();
    _lastCopiedText = null;
  });

  /// The id we expect to be fully visible + copyable. Longer than 20 chars so
  /// the OLD `substring(0,20)+'...'` truncation would have clipped it.
  const canisterId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';

  MarketplaceScript buildScript() => MarketplaceScript(
        id: 'w6-8',
        title: 'W6-8 Canister Copy',
        description: 'desc',
        category: 'Tools',
        price: 0,
        canisterIds: const [canisterId],
        bundle: 'print(1)',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

  /// Mocks `/preview` to succeed + empty reviews/versions so the dialog
  /// renders without network.
  MockClient successClient() {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/preview')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'w6-8',
              'description': 'desc',
              'version': '1.0.0',
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
      return http.Response(
        jsonEncode({'success': true, 'data': []}),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });
  }

  Future<void> openDialog(WidgetTester tester, MarketplaceScript script) {
    service.overrideHttpClient(successClient());
    return pumpDetailsDialog(
      tester,
      dialogBuilder: (_) =>
          ScriptDetailsDialog(script: script, onDownload: () {}),
    );
  }

  testWidgets(
      'W6-8 (wide): the FULL canister id is visible (not truncated with …) and '
      'tapping it copies the id with a SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openDialog(tester, buildScript());

    // The FULL id must be findable as text — the OLD code truncated it.
    expect(find.text(canisterId), findsOneWidget,
        reason: 'the full canister id must be visible, not clipped to '
            '"ryjl3-tyaaa-aaaaa-aa…"');
    // No "…" ellipsis hack remains for this id.
    expect(find.textContaining('…'), findsNothing);

    // Tap the canister-id row to copy. Ensure it's scrolled into view first
    // (it lives at the bottom of the panel's scroll view).
    final row = find.byKey(const ValueKey('canister_id_$canisterId'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(_lastCopiedText, canisterId,
        reason: 'tapping the canister id should copy the full id');
    // A "Copied" affordance appears.
    expect(find.textContaining('copied'), findsOneWidget);
  });

  testWidgets(
      'W6-8 (narrow): the FULL canister id is visible and tappable to copy',
      (tester) async {
    // Narrow surface (< 600px wide) forces the narrow layout.
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The narrow dialog header previously had a RenderFlex overflow on the
    // badges Row at mobile widths. That was fixed (badges Row → Wrap), so the
    // narrow layout must now render with NO layout errors at all. Capture any
    // FlutterErrors and fail loudly on all of them.
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    await openDialog(tester, buildScript());

    expect(find.text(canisterId), findsOneWidget);
    final row = find.byKey(const ValueKey('canister_id_$canisterId'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(_lastCopiedText, canisterId);
    expect(find.textContaining('copied'), findsOneWidget);

    // Flush any deferred layout errors before asserting.
    await tester.pump();
    FlutterError.onError = originalOnError;
    expect(errors, isEmpty,
        reason: 'the narrow dialog must render with no layout errors; got: '
            '${errors.map((e) => e.exceptionAsString()).join('\n')}');
  });
}

String? _lastCopiedText;
