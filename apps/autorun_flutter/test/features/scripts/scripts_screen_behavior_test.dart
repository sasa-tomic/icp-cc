import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '_scripts_test_harness.dart';

/// Real [ScriptsScreen] behaviours driven through the shared harness.
///
/// These replace the deleted `one_tap_execution_test.dart` /
/// `simplified_actions_test.dart`, which pumped test-local row-widget *copies*
/// (stand-ins that are not shipped). The tests here exercise the actual screen
/// wiring: the controller, the row menus, and the tap → run dispatch.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'ONE-TAP: tapping a local script row opens the execution sheet',
      (tester) async {
    final repo = MockScriptRepository()
      ..addScript(aLocalScript(id: 'tap-1', title: 'Tap Me'));
    await pumpScriptsScreen(tester, controller: ScriptController(repo));

    expect(find.text('Tap Me'), findsOneWidget);

    await tester.tap(find.text('Tap Me'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ScriptExecutionBottomSheet), findsOneWidget);
  });

  testWidgets('search filters local scripts by title (case-insensitive)',
      (tester) async {
    final repo = MockScriptRepository()
      ..addScript(aLocalScript(id: 'a', title: 'Alpha Reader'))
      ..addScript(aLocalScript(id: 'b', title: 'Beta Engine'));
    await pumpScriptsScreen(tester, controller: ScriptController(repo));

    expect(find.text('Alpha Reader'), findsOneWidget);
    expect(find.text('Beta Engine'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Alpha Reader'), findsOneWidget);
    expect(find.text('Beta Engine'), findsNothing);
  });
}
