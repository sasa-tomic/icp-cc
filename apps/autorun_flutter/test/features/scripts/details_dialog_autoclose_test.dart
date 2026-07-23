// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';
import 'package:icp_autorun/widgets/scripts_list_item_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '_scripts_test_harness.dart';

/// CR-1: when a download is initiated from the Script Details dialog, the
/// dialog must auto-close on success so the "Run" SnackBar action is
/// immediately reachable (instead of being hidden behind the still-open
/// dialog). 5 -> 4 interactions on the dialog download path.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'CR-1: details dialog auto-closes on download success and the Run '
      'SnackBar action is shown', (tester) async {
    final mpScript = aMarketplaceScript(
      id: 'mp-cr1',
      title: 'CR1 Script',
      bundle: 'print("cr1")',
    );
    final repo = MockScriptRepository();
    final controller = ScriptController(repo);
    final marketplace = FakeMarketplaceOpenApi(scripts: [mpScript]);

    await pumpScriptsScreen(
      tester,
      controller: controller,
      marketplaceService: marketplace,
    );

    expect(find.text('CR1 Script'), findsOneWidget);

    // Tap the marketplace tile -> opens the details dialog.
    await tester.tap(find.byType(ScriptsListItemTile));
    await tester.pumpAndSettle();

    expect(find.byType(ScriptDetailsDialog), findsOneWidget,
        reason: 'details dialog should be open after tapping the tile');

    // Tap Download inside the dialog.
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.byType(ScriptDetailsDialog), findsNothing,
        reason: 'details dialog must auto-close on download success');
    expect(find.text('Run'), findsOneWidget,
        reason: 'the Run SnackBar action must be visible after the dialog '
            'closes');
  });
}
