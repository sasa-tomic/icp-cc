import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/screens/download_history_screen.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';

/// UXR7-6: the "Browse Marketplace" empty-state CTA used to be a dead end — it
/// popped the screen and told the user to "Select the Marketplace tab"
/// manually. These tests pin the real behaviour: the CTA pops back to the
/// Scripts tab AND fires the production-wired browse callback (which refreshes
/// the marketplace browse view).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The service caches history in-memory on a singleton; clear it so each
    // test starts from an empty download history (empty-state is shown).
    await DownloadHistoryService().clearHistory();
  });

  Future<void> pumpHistoryRoute(WidgetTester tester, VoidCallback onBrowse) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DownloadHistoryScreen(
                        scriptController:
                            ScriptController(MockScriptRepository()),
                        onBrowseMarketplace: onBrowse,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'UXR7-6: empty state offers a Browse Marketplace CTA that navigates',
      (tester) async {
    var browseCalled = false;
    await pumpHistoryRoute(tester, () => browseCalled = true);

    // Empty state is shown with the CTA.
    expect(find.text('No Download History'), findsOneWidget);
    expect(find.text('Browse Marketplace'), findsOneWidget);
    expect(find.byType(DownloadHistoryScreen), findsOneWidget);

    await tester.tap(find.text('Browse Marketplace'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The history route was popped (back on the home root)...
    expect(find.byType(DownloadHistoryScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    // ...and the production browse callback actually fired (instead of the old
    // "Select the Marketplace tab" manual hand-off snackbar).
    expect(browseCalled, isTrue);
    expect(find.text('Select the Marketplace tab to browse scripts'),
        findsNothing);
  });

  testWidgets('UXR7-6: without a browse callback the CTA still pops the route',
      (tester) async {
    await pumpHistoryRoute(tester, () {});

    expect(find.text('Browse Marketplace'), findsOneWidget);
    expect(find.byType(DownloadHistoryScreen), findsOneWidget);

    await tester.tap(find.text('Browse Marketplace'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(DownloadHistoryScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
