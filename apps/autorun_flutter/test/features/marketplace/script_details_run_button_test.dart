// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

/// Phase 4 — Run button replaces the dead "Downloaded ✓" indicator when a
/// downloaded marketplace script's details are re-opened, and **Enter**
/// triggers the dialog's primary action (Download or Run).
void main() {
  group('ScriptDetailsDialog Run button (Phase 4)', () {
    late MarketplaceOpenApiService service;
    late MarketplaceScript testScript;

    setUp(() {
      suppressDebugOutput = true;
      service = MarketplaceOpenApiService();
      AppConfig.setTestEndpoint('https://mock.api');

      testScript = MarketplaceScript(
        id: 'mk-run-test',
        title: 'Run Test',
        description: 'Script for Run-button coverage.',
        category: 'Utilities',
        authorName: 'Tester',
        price: 0,
        bundle: 'print("hi")',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );
    });

    tearDown(() {
      suppressDebugOutput = false;
      service.resetHttpClient();
    });

    MockClient stubClient() {
      return MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/preview')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': testScript.id,
                'description': testScript.description,
                'version': '1.0.0',
                'price': 0,
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

    Future<void> pumpDialog(
      WidgetTester tester, {
      VoidCallback? onDownload,
      VoidCallback? onRun,
      bool isDownloaded = false,
    }) async {
      service.overrideHttpClient(stubClient());
      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(
          script: testScript,
          onDownload: onDownload,
          onRun: onRun,
          isDownloaded: isDownloaded,
        ),
      );
    }

    testWidgets(
        'downloaded script with onRun shows a Run button (not Downloaded ✓)',
        (tester) async {
      await pumpDialog(tester, onRun: () {}, isDownloaded: true);

      expect(find.text('Run'), findsOneWidget,
          reason: 'downloaded script should show Run, not Downloaded ✓');
      expect(find.text('Downloaded ✓'), findsNothing);
    });

    testWidgets(
        'downloaded script WITHOUT onRun falls back to Downloaded ✓ (backward compat)',
        (tester) async {
      await pumpDialog(tester, onDownload: () {}, isDownloaded: true);

      expect(find.text('Downloaded ✓'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
    });

    testWidgets('not-downloaded script still shows Download (Run hidden)',
        (tester) async {
      await pumpDialog(tester, onDownload: () {}, onRun: () {}, isDownloaded: false);

      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
    });

    testWidgets('tapping Run calls the onRun callback', (tester) async {
      var runCalled = 0;
      await pumpDialog(
        tester,
        onRun: () => runCalled++,
        isDownloaded: true,
      );

      await tester.tap(find.text('Run'));
      await tester.pump();

      expect(runCalled, 1);
    });

    testWidgets('Enter triggers Run when the script is downloaded', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        var runCalled = 0;
        await pumpDialog(
          tester,
          onRun: () => runCalled++,
          isDownloaded: true,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(runCalled, 1, reason: 'Enter should trigger Run for a downloaded script');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Enter triggers Download when the script is not downloaded',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        var downloadCalled = 0;
        await pumpDialog(
          tester,
          onDownload: () => downloadCalled++,
          isDownloaded: false,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(downloadCalled, 1,
            reason: 'Enter should trigger Download for a not-downloaded script');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Enter is inert on mobile (pass-through)', (tester) async {
      var runCalled = 0;
      await pumpDialog(
        tester,
        onRun: () => runCalled++,
        isDownloaded: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(runCalled, 0, reason: 'Enter must be a no-op on mobile');
    });
  });
}
