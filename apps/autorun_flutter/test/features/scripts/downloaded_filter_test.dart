import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Downloaded filter chip', () {
    testWidgets('appears in filter bottom sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilterChip, 'Downloaded'),
        ),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('is not selected by default', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump(const Duration(seconds: 1));

      final downloadedChip = tester.widget<FilterChip>(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilterChip, 'Downloaded'),
        ),
      );
      expect(downloadedChip.selected, isFalse);

      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Downloaded filter empty state', () {
    testWidgets('generic empty state does not show downloaded-specific text',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await pumpScriptsScreen(tester, settle: const Duration(seconds: 4));

      // The downloaded-specific empty state must NOT show when the Downloaded
      // filter is inactive.
      expect(find.text("You haven't downloaded any scripts yet"), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
