// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/script_template.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';

/// CR-5: the template selector (a 200x180 card grid) was expanded by default on
/// the Script Creation screen, pushing the code editor + Create button below
/// the fold. It now defaults to collapsed; the user can still tap to expand.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'CR-5: template grid is collapsed by default and expands on tap',
      (tester) async {
    final controller = ScriptController(MockScriptRepository());

    await tester.pumpWidget(
      MaterialApp(home: ScriptCreationScreen(controller: controller)),
    );
    await tester.pump();

    // The selector header is always visible.
    expect(find.text('Choose a Template'), findsOneWidget);

    // The default-selected template card is NOT in the tree (collapsed).
    expect(find.byKey(const Key('template_card_hello_world')), findsNothing,
        reason: 'template grid must be collapsed by default so the editor + '
            'Create button land above the fold');

    // Expand via the header toggle.
    await tester.tap(find.text('Choose a Template'));
    await tester.pumpAndSettle();

    // Now the grid (and the default-selected card) is visible.
    expect(find.byKey(const Key('template_card_hello_world')), findsOneWidget);
  });
}
