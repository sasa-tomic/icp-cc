import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_scripts_test_harness.dart';

/// AppBar overflow-menu behaviour that a user can actually drive. The previous
/// file additionally asserted "an overflow button renders" (setup, not
/// behaviour) and "no TabBar exists" (a stale removal guard); both dropped.
void main() {
  testWidgets('overflow menu exposes Download History', (tester) async {
    await pumpScriptsScreen(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();

    expect(find.text('Download History'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
  });
}
