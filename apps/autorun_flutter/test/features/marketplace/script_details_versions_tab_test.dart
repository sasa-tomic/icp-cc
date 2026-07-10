import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/script_details_versions_tab.dart';

import '_marketplace_test_harness.dart';

/// W6-6 — isolation tests for [ScriptDetailsVersionsTab].
///
/// The sibling `script_details_versions_test.dart` drives the tab THROUGH the
/// full `ScriptDetailsDialog` (open dialog → tap "Versions" → assert). These
/// tests instead pump the tab widget DIRECTLY, decoupled from the dialog
/// lifecycle, to pin that it renders its heading + body on its own — i.e. the
/// "blank panel" regression (UX W6-4) can never recur from a layout collapse
/// local to this widget, regardless of how the dialog mounts it.
///
/// Every test asserts the "Version History" heading is present AND the
/// relevant body (empty-state / entries / spinner / error) is visible, because
/// the reported bug was that BOTH vanished — a bare `findsOneWidget` on the
/// heading alone would not catch a body collapse.
void main() {
  late MarketplaceScript script;

  setUp(() {
    script = MarketplaceScript(
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

  Future<void> pumpTab(
    WidgetTester tester, {
    List<ScriptVersion> versions = const [],
    bool isLoading = false,
    String? error,
  }) async {
    await pumpMarketplaceWidget(
      tester,
      ScriptDetailsVersionsTab(
        script: script,
        versions: versions,
        isLoadingVersions: isLoading,
        versionsError: error,
      ),
    );
  }

  testWidgets(
      'empty versions list renders BOTH the heading and the empty-state '
      '(W6-6 blank-panel regression)', (WidgetTester tester) async {
    await pumpTab(tester, versions: []);

    // Heading — must render even when the backend 404s / returns no versions.
    expect(find.text('Version History'), findsOneWidget);
    // Empty-state — the whole point: a labelled tab must show SOMETHING.
    expect(find.text('No version history'), findsOneWidget);
    expect(find.text('Only one version available'), findsOneWidget);
  });

  testWidgets('populated versions list renders the heading and the entries',
      (WidgetTester tester) async {
    await pumpTab(
      tester,
      versions: [
        ScriptVersion(
          version: '2.0.0',
          changelog: 'Major update',
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
      ],
    );

    expect(find.text('Version History'), findsOneWidget);
    expect(find.text('v2.0.0'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('Major update'), findsOneWidget);
  });

  testWidgets('loading state renders the heading and a progress indicator',
      (WidgetTester tester) async {
    await pumpTab(tester, versions: [], isLoading: true);

    expect(find.text('Version History'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error state renders the heading and the error message',
      (WidgetTester tester) async {
    await pumpTab(
      tester,
      versions: [],
      error: 'Failed to load versions: network down',
    );

    expect(find.text('Version History'), findsOneWidget);
    expect(find.text('Failed to load versions: network down'), findsOneWidget);
  });
}
