// Flow B / WU-3 — create a LOCAL script and verify the "created" SnackBar has
// NO "Share"/"Publish" action (and returns to the list). createScript() is
// purely local (no keypair/backend needed), so this flow is NOT blocked by
// NEW-2 and can be driven end-to-end.
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/b_create_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> dismissWizard(WidgetTester tester) async {
    int guard = 0;
    while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
      await tester.pump(const Duration(milliseconds: 200));
      guard++;
    }
    if (present(find.byIcon(Icons.close), tester)) {
      await tester.tap(find.byIcon(Icons.close).first);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('WU-3: create-script SnackBar has NO Share action', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    // Open the create-script sheet via the "New Script" FAB.
    expect(present(find.text('New Script'), tester), isTrue);
    await tester.tap(find.text('New Script').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // ScriptCreationScreen: fill the title field (first TextFormField).
    expect(present(find.text('Enter a descriptive title'), tester), isTrue);
    await tester.enterText(find.byType(TextFormField).first, 'UX Probe Script');

    // Drive code into the ScriptEditor's CodeField. The form has 3
    // TextFormField (title/emoji/imageUrl); the CodeField adds a 4th
    // EditableText — it is the LAST one in the tree.
    final codeField = find.byType(EditableText).last;
    await tester.ensureVisible(codeField);
    await tester.enterText(codeField, 'export function main(): void { return; }');
    await tester.pump();

    // Tap "Create Script".
    final createBtn = find.widgetWithText(FilledButton, 'Create Script');
    expect(present(createBtn, tester), isTrue);
    await tester.tap(createBtn);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot(binding, '06_create_snackbar', tester);

    final snackbarShown = present(find.text('Script created successfully!'), tester);
    final hasActionOnBar = present(find.byType(SnackBarAction), tester);
    // ignore: avoid_print
    print('WU3_CREATE: snackbarShown=$snackbarShown hasShareAction=$hasActionOnBar');

    // We may be slightly off the snackbar's 4s window; the decisive assertion
    // is structural: the create SnackBar (scripts_screen.dart:551) declares NO
    // SnackBarAction. We verify that at runtime.
    expect(snackbarShown, isTrue,
        reason: 'Create-script success SnackBar appears.');
    expect(hasActionOnBar, isFalse,
        reason: 'WU-3: create SnackBar has NO "Share"/"Publish" action; user is '
            'returned to the list with no path to publish.');
  });
}
