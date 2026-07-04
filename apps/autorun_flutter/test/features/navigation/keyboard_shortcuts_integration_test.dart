// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/keyboard_shortcuts.dart';
import 'package:icp_autorun/widgets/shortcuts_help_sheet.dart';

/// UX-9 integration coverage for the keyboard-shortcut layer.
///
/// Pumps a faithful mini-shell of `MainHomePage` (a `DesktopShortcuts` wrapper
/// driving a real tab index, a real search `TextField` with its own
/// `FocusNode`, and the real `showShortcutsHelpSheet` overlay) and exercises
/// the four behaviours the task requires:
///   1. `Alt+2` switches the active tab.
///   2. `/` focuses the search field.
///   3. Shortcuts stay inert while a text field is being edited.
///   4. `?` opens the shortcuts help overlay with its content visible.
///
/// The full `MainHomePage` is intentionally not pumped here: it launches the
/// first-run wizard and a networked `ScriptsScreen`, which would make the
/// keyboard assertions flaky and offline-hostile. The shortcut/focus/sheet
/// primitives exercised below are the real production widgets.

/// Forces a desktop platform for the test and restores it before the body
/// returns — the binding's `_verifyInvariants` (which asserts foundation
/// debug vars are unset) runs before `tearDown`/`addTearDown`, so the reset
/// must happen inside the body.
void desktopTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  desktopTest('Alt+2 switches the active tab', (tester) async {
    await _pumpShell(tester);

    expect(find.text('tab:0'), findsOneWidget);
    expect(find.text('Scripts page'), findsOneWidget);

    await _pressAlt(tester, LogicalKeyboardKey.digit2);

    expect(find.text('tab:1'), findsOneWidget,
        reason: 'Alt+2 should switch to the Canisters tab.');
    expect(find.text('Canisters page'), findsOneWidget);
  });

  desktopTest('/ focuses the search field', (tester) async {
    await _pumpShell(tester);

    final fieldBefore =
        tester.widget<TextField>(find.byKey(const Key('scriptSearch')));
    expect(fieldBefore.focusNode!.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();

    final fieldAfter =
        tester.widget<TextField>(find.byKey(const Key('scriptSearch')));
    expect(fieldAfter.focusNode!.hasFocus, isTrue,
        reason: '`/` should move focus to the search field.');
    expect(find.byType(EditableText), findsOneWidget);
  });

  desktopTest('Alt+2 does NOT switch tabs while editing a text field',
      (tester) async {
    await _pumpShell(tester);

    // Start editing the search field.
    await tester.enterText(find.byKey(const Key('scriptSearch')), 'foo');
    await tester.pump();
    final field =
        tester.widget<TextField>(find.byKey(const Key('scriptSearch')));
    expect(field.focusNode!.hasFocus, isTrue);

    await _pressAlt(tester, LogicalKeyboardKey.digit2);
    await tester.pump();

    // No navigation, no focus theft, typed text preserved.
    expect(find.text('tab:0'), findsOneWidget,
        reason: 'Tab switch must stay inert while the user is typing.');
    expect(find.widgetWithText(TextField, 'foo'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('scriptSearch')))
            .focusNode!
            .hasFocus,
        isTrue);
  });

  desktopTest('? opens the shortcuts help overlay', (tester) async {
    await _pumpShell(tester);

    expect(find.text('Keyboard Shortcuts'), findsNothing);

    // `?` is Shift+/.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    // The help overlay is on screen with its title + grouped content.
    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('NAVIGATION'), findsOneWidget);
    expect(find.text('SCRIPTS'), findsOneWidget);
    expect(find.text('HELP'), findsOneWidget);
    // A representative description row is rendered.
    expect(find.text('Focus the search bar'), findsOneWidget);
  });
}

Future<void> _pressAlt(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await tester.pump();
}

Future<void> _pumpShell(WidgetTester tester) async {
  // The shortcuts help sheet (with the UX-9 Dapps/Account/Details groups) is
  // taller than the default 800x600 test surface. Because the sheet scrolls,
  // bottom groups like 'HELP' get lazy-clipped out of the widget tree and
  // `find.text('HELP')` returns 0. Use a desktop-realistic viewport so the
  // whole sheet lays out — mirrors test/widgets/shortcuts_help_sheet_test.dart.
  // The other three tests in this file are viewport-insensitive (they assert
  // on tab text / focus state), so the bump is harmless to them.
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      home: _Shell(navKey: navKey),
    ),
  );
  await tester.pump();
}

/// Mini reproduction of `MainHomePage`'s shortcut-driven shell.
class _Shell extends StatefulWidget {
  const _Shell({required this.navKey});
  final GlobalKey<NavigatorState> navKey;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _currentIndex = 0;
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    // Mirrors MainHomePage: only the Scripts tab owns a search field.
    if (_currentIndex == 0) _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopShortcuts(
      onCreateScript: () {},
      onFocusSearch: _focusSearch,
      onRefresh: () {},
      onNavigateToTab: (index) => setState(() => _currentIndex = index),
      onShowShortcuts: () => showShortcutsHelpSheet(widget.navKey.currentContext!),
      child: Scaffold(
        body: Column(
          children: [
            // A non-editable, auto-focused node so global key events reach the
            // shortcut layer without a text field grabbing focus first.
            Focus(
              autofocus: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('tab:$_currentIndex'),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          key: const Key('scriptSearch'),
                          focusNode: _searchFocus,
                          decoration: const InputDecoration(
                              hintText: 'Search scripts'),
                        ),
                      ),
                      const Expanded(child: Center(child: Text('Scripts page'))),
                    ],
                  ),
                  const Center(child: Text('Canisters page')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
