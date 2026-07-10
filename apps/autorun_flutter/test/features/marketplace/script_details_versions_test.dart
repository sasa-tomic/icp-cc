import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

import '_marketplace_test_harness.dart';

void main() {
  group('ScriptDetailsDialog Versions', () {
    late MarketplaceOpenApiService service;
    late MarketplaceScript testScript;

    setUp(() {
      suppressDebugOutput = true;
      service = MarketplaceOpenApiService();
      AppConfig.setTestEndpoint('https://mock.api');

      testScript = MarketplaceScript(
        id: 'script-123',
        title: 'Test Script',
        description: 'A test script for versions',
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

    Future<void> pumpDialog(
      WidgetTester tester, {
      MarketplaceScript? script,
      List<ScriptVersion>? versions,
      int? versionsStatusCode,
      String? installedVersion,
      void Function(String version)? onInstallVersion,
    }) async {
      final effectiveScript = script ?? testScript;
      final effectiveVersions = versions ?? [];
      final effectiveStatusCode = versionsStatusCode ?? 200;

      final client = MockClient((request) async {
        // Lightweight preview (UX-6) — the eager Details-tab fetch.
        if (request.url.path.contains('/preview')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': effectiveScript.id,
                'description': effectiveScript.description,
                'version': '1.0.0',
                'price': effectiveScript.price,
                'language': 'typescript',
                'preview': '// preview line 1',
                'previewTruncated': false,
                'totalLines': 1,
              },
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }

        if (request.url.path.contains('/versions') &&
            !request.url.path.contains('/versions/')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': effectiveVersions
                  .map((v) => {
                        'version': v.version,
                        'changelog': v.changelog,
                        'createdAt': v.createdAt.toIso8601String(),
                        'downloads': v.downloads,
                        'isLatest': v.isLatest,
                      })
                  .toList(),
            }),
            effectiveStatusCode,
            headers: {'Content-Type': 'application/json'},
          );
        }

        if (request.url.path.contains('/reviews')) {
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
              'id': effectiveScript.id,
              'title': effectiveScript.title,
              'description': effectiveScript.description,
              'category': effectiveScript.category,
              'tags': effectiveScript.tags,
              'author_id': effectiveScript.authorId,
              'author_name': effectiveScript.authorName,
              'bundle': effectiveScript.bundle,
              'price': effectiveScript.price,
              'downloads': effectiveScript.downloads,
              'rating': effectiveScript.rating,
              'review_count': effectiveScript.reviewCount,
              'created_at': effectiveScript.createdAt.toIso8601String(),
              'updated_at': effectiveScript.updatedAt.toIso8601String(),
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      service.overrideHttpClient(client);
      addTearDown(client.close);

      await pumpDetailsDialog(
        tester,
        dialogBuilder: (_) => ScriptDetailsDialog(
          script: effectiveScript,
          installedVersion: installedVersion,
          onInstallVersion: onInstallVersion,
        ),
      );
    }

    testWidgets('shows Versions tab alongside Details and Reviews',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Reviews'), findsOneWidget);
      expect(find.text('Versions'), findsOneWidget);
    });

    testWidgets('tapping Versions tab shows version history',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Version History'), findsOneWidget);
    });

    testWidgets('loads and displays versions from service',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          changelog: 'Major update with new features',
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
          downloads: 150,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          changelog: 'Initial release',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(tester, versions: versions);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('v2.0.0'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.text('Major update with new features'), findsOneWidget);
    });

    testWidgets('shows Latest badge on most recent version',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(tester, versions: versions);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Latest'), findsOneWidget);
    });

    testWidgets('shows Installed badge on currently installed version',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(
        tester,
        versions: versions,
        installedVersion: '1.0.0',
      );

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Installed'), findsOneWidget);
    });

    testWidgets(
        'shows Install button for non-latest versions when callback provided',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(
        tester,
        versions: versions,
        onInstallVersion: (_) {},
      );

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Install'), findsOneWidget);
    });

    testWidgets('Install button is not shown for latest version',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(
        tester,
        versions: versions,
        onInstallVersion: (_) {},
      );

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      final installButtons = find.text('Install');
      expect(installButtons, findsOneWidget);
    });

    testWidgets('Install button callback is triggered on tap',
        (WidgetTester tester) async {
      String? installedVersion;
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
        ScriptVersion(
          version: '1.0.0',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          downloads: 500,
          isLatest: false,
        ),
      ];

      await pumpDialog(
        tester,
        versions: versions,
        onInstallVersion: (version) {
          installedVersion = version;
        },
      );

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();

      expect(installedVersion, equals('1.0.0'));
    });

    testWidgets('shows empty state when no versions exist',
        (WidgetTester tester) async {
      await pumpDialog(tester, versions: []);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('No version history'), findsOneWidget);
      expect(find.text('Only one version available'), findsOneWidget);
    });

    // W6-6: the REAL backend currently answers GET /scripts/:id/versions with
    // 404 (endpoint not deployed). `getScriptVersions` maps that to `[]`
    // (contract preserved — do NOT change), so the Versions tab MUST fall into
    // its empty-state branch and render the heading + "No version history"
    // message — NOT a blank panel. This pins the 404 path explicitly (the
    // sibling test above only covers 200 + empty `data`, which is the same `[]`
    // downstream but a different wire shape).
    testWidgets(
        'shows heading + empty state when the versions endpoint returns 404 '
        '(W6-6)', (WidgetTester tester) async {
      await pumpDialog(tester, versions: [], versionsStatusCode: 404);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Version History'), findsOneWidget,
          reason: 'heading must render even when the backend 404s');
      expect(find.text('No version history'), findsOneWidget,
          reason: '404 → [] → empty-state branch must render');
      expect(find.text('Only one version available'), findsOneWidget);
    });

    testWidgets('displays version download count', (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          createdAt: DateTime.now(),
          downloads: 150,
          isLatest: true,
        ),
      ];

      await pumpDialog(tester, versions: versions);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('150'), findsOneWidget);
    });

    testWidgets('displays changelog when available',
        (WidgetTester tester) async {
      final versions = [
        ScriptVersion(
          version: '2.0.0',
          changelog: 'Fixed bugs and improved performance',
          createdAt: DateTime.now(),
          downloads: 100,
          isLatest: true,
        ),
      ];

      await pumpDialog(tester, versions: versions);

      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('Fixed bugs and improved performance'), findsOneWidget);
    });

    group('View Changes button', () {
      testWidgets('shows View Changes button when installed version differs',
          (WidgetTester tester) async {
        final versions = [
          ScriptVersion(
            version: '2.0.0',
            createdAt: DateTime.now(),
            downloads: 100,
            isLatest: true,
          ),
          ScriptVersion(
            version: '1.0.0',
            createdAt: DateTime.now().subtract(const Duration(days: 30)),
            downloads: 500,
            isLatest: false,
          ),
        ];

        await pumpDialog(
          tester,
          versions: versions,
          installedVersion: '1.0.0',
        );

        await tester.tap(find.text('Versions'));
        await tester.pumpAndSettle();

        expect(find.text('View Changes'), findsWidgets);
      });

      testWidgets('does not show View Changes for currently installed version',
          (WidgetTester tester) async {
        final versions = [
          ScriptVersion(
            version: '2.0.0',
            createdAt: DateTime.now(),
            downloads: 100,
            isLatest: true,
          ),
          ScriptVersion(
            version: '1.0.0',
            createdAt: DateTime.now().subtract(const Duration(days: 30)),
            downloads: 500,
            isLatest: false,
          ),
        ];

        await pumpDialog(
          tester,
          versions: versions,
          installedVersion: '1.0.0',
        );

        await tester.tap(find.text('Versions'));
        await tester.pumpAndSettle();

        final viewChangesButtons = find.text('View Changes');
        expect(viewChangesButtons, findsOneWidget);
      });

      testWidgets('shows first install message when no version installed',
          (WidgetTester tester) async {
        final versions = [
          ScriptVersion(
            version: '1.0.0',
            createdAt: DateTime.now(),
            downloads: 100,
            isLatest: true,
          ),
        ];

        await pumpDialog(tester, versions: versions);

        await tester.tap(find.text('Versions'));
        await tester.pumpAndSettle();

        expect(find.text('View Changes'), findsOneWidget);
      });
    });
  });
}
