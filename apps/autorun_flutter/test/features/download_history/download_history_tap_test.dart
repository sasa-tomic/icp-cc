import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/screens/download_history_screen.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '../scripts/_scripts_test_harness.dart';

/// QS-4: the download-library item tap was a dead stub (it only popped back
/// and left a stale `TODO`). These tests pin the real behaviour: tapping a
/// downloaded script opens it in the shared execution bottom sheet.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The service caches history in-memory on a singleton; clear it so each
    // test starts from a clean slate.
    await DownloadHistoryService().clearHistory();
  });

  testWidgets(
      'QS-4: tapping a downloaded script opens the execution bottom sheet',
      (tester) async {
    await DownloadHistoryService().addToHistory(
      marketplaceScriptId: 'mp-1',
      title: 'Downloaded Script',
      authorName: 'Author',
      localScriptId: 'local-1',
    );

    final controller =
        ScriptController(MockScriptRepository()
          ..addScript(aLocalScript(id: 'local-1', title: 'Downloaded Script')));
    await controller.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(home: DownloadHistoryScreen(scriptController: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Downloaded Script'), findsOneWidget);

    await tester.tap(find.text('Downloaded Script'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The script actually opens — the same execution sheet the scripts list
    // uses — instead of the old dead pop.
    expect(find.byType(ScriptExecutionBottomSheet), findsOneWidget);
  });

  testWidgets(
      'QS-4: tapping a download whose local script is missing shows a '
      'not-found snackbar and stays on the library screen', (tester) async {
    await DownloadHistoryService().addToHistory(
      marketplaceScriptId: 'mp-2',
      title: 'Ghost Script',
      authorName: 'Author',
      localScriptId: 'missing-id',
    );

    final controller = ScriptController(MockScriptRepository());
    await controller.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(home: DownloadHistoryScreen(scriptController: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Still on the Download Library screen before tapping.
    expect(find.text('Download Library'), findsOneWidget);

    await tester.tap(find.text('Ghost Script'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Script not found. It may have been deleted.'),
        findsOneWidget);
    // Old behaviour popped back; the new behaviour keeps the user on the
    // library screen (no execution sheet, no navigation away).
    expect(find.text('Download Library'), findsOneWidget);
    expect(find.byType(ScriptExecutionBottomSheet), findsNothing);
  });
}
