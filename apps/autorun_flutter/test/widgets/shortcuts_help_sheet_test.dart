import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/keyboard_shortcuts.dart';
import 'package:icp_autorun/widgets/shortcuts_help_sheet.dart';

void main() {
  group('ShortcutsHelpSheet', () {
    testWidgets('renders every shortcut from the single source of truth',
        (tester) async {
      // The sheet is a scrollable bottom sheet; on the default 800x600 test
      // surface the six groups (added UX-9 Details group) overflow and the
      // bottom groups get lazy-clipped out of the widget tree. Use a
      // desktop-realistic viewport so every row is built and discoverable by
      // `find.text` — the production sheet itself scrolls correctly on any
      // window too short to fit all groups at once.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelpSheet(context),
              child: const Text('open'),
            ),
          );
        })),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Title and all descriptions are present.
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      for (final spec in kShortcutSpecs.values) {
        expect(find.text(spec.description), findsOneWidget,
            reason: '${spec.description} should be listed');
      }

      // Groups are rendered.
      expect(find.text('NAVIGATION'), findsOneWidget);
      expect(find.text('SCRIPTS'), findsOneWidget);
      expect(find.text('DETAILS'), findsOneWidget,
          reason: 'UX-9 part B added a Details group');
      expect(find.text('HELP'), findsOneWidget);

      // The ? affordance (both as a key chip and as a help entry) is shown on
      // desktop where the shortcut is active.
      if (DesktopShortcuts.isDesktop) {
        expect(find.text('?'), findsWidgets);
      }
    });

    testWidgets('closes when the scrim is tapped', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelpSheet(context),
              child: const Text('open'),
            ),
          );
        })),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);

      // Tap outside the sheet (top-left of the screen) dismisses it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Keyboard Shortcuts'), findsNothing);
    });

    testWidgets('closes on drag down', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelpSheet(context),
              child: const Text('open'),
            ),
          );
        })),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);

      // Drag from the non-scrollable header (the title) downward to dismiss.
      await tester.fling(
        find.text('Keyboard Shortcuts'),
        const Offset(0, 600),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Keyboard Shortcuts'), findsNothing);
    });
  });

  group('ShortcutsHelpButton', () {
    testWidgets('tapping opens the help sheet', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: ShortcutsHelpButton())),
      ));

      await tester.tap(find.byType(ShortcutsHelpButton));
      await tester.pumpAndSettle();

      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    });
  });
}
