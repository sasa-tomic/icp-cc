import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/keyboard_shortcuts.dart';

/// `defaultTargetPlatform` is `android` inside `flutter_test`, which would
/// leave [DesktopShortcuts.isDesktop] false and the shortcut layer inert.
///
/// `desktopTest` forces a desktop platform for the test and — critically —
/// restores it before the test body returns, because the binding's
/// `_verifyInvariants` (which asserts foundation debug vars are unset) runs
/// before both file-level `tearDown` and `addTearDown` callbacks.
void desktopTest(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  TargetPlatform platform = TargetPlatform.linux,
}) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  /// The platform "modify" key (⌘ on macOS, Ctrl elsewhere) used by the
  /// `mod+F` search shortcut.
  LogicalKeyboardKey modKey() => defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;

  group('DesktopShortcuts', () {
    desktopTest('renders child', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(body: Text('Test Content')),
          ),
        ),
      );
      expect(find.text('Test Content'), findsOneWidget);
    });

    desktopTest('N creates a new script', (tester) async {
      bool createScriptCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () => createScriptCalled = true,
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(createScriptCalled, isTrue);
    });

    desktopTest('N does NOT fire while a text field is focused', (tester) async {
      bool createScriptCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () => createScriptCalled = true,
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TextField(autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'n');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(createScriptCalled, isFalse,
          reason: 'Plain N must be inert while editing text.');
      expect(find.widgetWithText(TextField, 'n'), findsOneWidget);
    });

    desktopTest('/ focuses the search bar', (tester) async {
      bool focusSearchCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () => focusSearchCalled = true,
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await tester.pump();
      expect(focusSearchCalled, isTrue);
    });

    desktopTest('/ does NOT focus search while a text field is focused',
        (tester) async {
      bool focusSearchCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () => focusSearchCalled = true,
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TextField(autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await tester.pump();
      expect(focusSearchCalled, isFalse,
          reason: 'A literal "/" must be typeable into a text field.');
    });

    desktopTest('Ctrl/Cmd+F focuses the search bar', (tester) async {
      bool focusSearchCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () => focusSearchCalled = true,
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(modKey());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modKey());
      await tester.pump();
      expect(focusSearchCalled, isTrue);
    });

    desktopTest('Ctrl/Cmd+F does NOT fire while a text field is focused',
        (tester) async {
      bool focusSearchCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () => focusSearchCalled = true,
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TextField(autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(modKey());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modKey());
      await tester.pump();
      expect(focusSearchCalled, isFalse,
          reason: 'Ctrl/Cmd+F must not steal focus while editing text.');
    });

    desktopTest('R refreshes', (tester) async {
      bool refreshCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () => refreshCalled = true,
            onNavigateToTab: (_) {},
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(refreshCalled, isTrue);
    });

    desktopTest('Alt+1 / Alt+2 switch tabs', (tester) async {
      int? navigatedTabIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (index) => navigatedTabIndex = index,
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.pump();
      expect(navigatedTabIndex, equals(0));

      navigatedTabIndex = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.pump();
      expect(navigatedTabIndex, equals(1));
    });

    desktopTest('Alt+2 does NOT switch tabs while a text field is focused',
        (tester) async {
      int? navigatedTabIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (index) => navigatedTabIndex = index,
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TextField(autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.pump();
      expect(navigatedTabIndex, isNull,
          reason: 'Alt+digit must be inert while editing text.');
    });

    desktopTest('Alt+3 is not bound (no 3rd tab)', (tester) async {
      int? navigatedTabIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (index) => navigatedTabIndex = index,
            onShowShortcuts: () {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.pump();
      expect(navigatedTabIndex, isNull,
          reason: 'Alt+3 must not navigate — there is no third tab.');
    });

    desktopTest('? opens the shortcuts help', (tester) async {
      bool helpShown = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () => helpShown = true,
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('Test Content')),
            ),
          ),
        ),
      );
      await tester.pump();
      // `?` is Shift+/. Shift must be held so SingleActivator(slash) — which
      // requires shift=false — does not intercept it first.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(helpShown, isTrue);
    });

    desktopTest('? does NOT open help while a text field is focused',
        (tester) async {
      bool helpShown = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            onShowShortcuts: () => helpShown = true,
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: TextField(autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(helpShown, isFalse,
          reason: 'Typing ? into a text field must not open the help overlay.');
    });

    desktopTest(
      'shortcuts are inert on mobile (pass-through)',
      (tester) async {
        bool focusSearchCalled = false;
        bool helpShown = false;
        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShortcuts(
              onCreateScript: () {},
              onFocusSearch: () => focusSearchCalled = true,
              onRefresh: () {},
              onNavigateToTab: (_) {},
              onShowShortcuts: () => helpShown = true,
              child: const Scaffold(
                body: Focus(autofocus: true, child: Text('Test Content')),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(DesktopShortcuts.isDesktop, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.pump();
        expect(focusSearchCalled, isFalse);
        expect(helpShown, isFalse);
      },
      platform: TargetPlatform.android,
    );

    test('isDesktop returns a bool', () {
      expect(DesktopShortcuts.isDesktop, isA<bool>());
    });

    test('getShortcutLabel returns the live binding tokens', () {
      expect(DesktopShortcuts.getShortcutLabel('new'), equals('N'));
      expect(DesktopShortcuts.getShortcutLabel('search'), equals('/'));
      expect(DesktopShortcuts.getShortcutLabel('refresh'), equals('R'));
      expect(DesktopShortcuts.getShortcutLabel('tab1'), equals('Alt+1'));
      expect(DesktopShortcuts.getShortcutLabel('tab2'), equals('Alt+2'));
      expect(DesktopShortcuts.getShortcutLabel('help'), equals('?'));
      // Dead/unknown actions carry no label.
      expect(DesktopShortcuts.getShortcutLabel('tab3'), isEmpty);
      expect(DesktopShortcuts.getShortcutLabel('save'), isEmpty);
      expect(DesktopShortcuts.getShortcutLabel('unknown'), isEmpty);
    });

    test('formatShortcutToken renders the platform modifier', () {
      expect(DesktopShortcuts.formatShortcutToken('mod+N'), contains('N'));
      expect(DesktopShortcuts.formatShortcutToken('/'), equals('/'));
      expect(DesktopShortcuts.formatShortcutToken('Alt+1'), equals('Alt+1'));
      expect(DesktopShortcuts.formatShortcutToken('R'), equals('R'));
      expect(DesktopShortcuts.formatShortcutToken('?'), equals('?'));
    });
  });

  group('EscapeHandler', () {
    desktopTest('renders child', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            onEscape: () {},
            child: const Scaffold(body: Text('Test Content')),
          ),
        ),
      );
      expect(find.text('Test Content'), findsOneWidget);
    });

    desktopTest('calls onEscape when Escape is pressed', (tester) async {
      bool escapeCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            onEscape: () => escapeCalled = true,
            child: const Scaffold(body: Text('Test Content')),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(escapeCalled, isTrue);
    });

    desktopTest('works without onEscape callback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            child: const Scaffold(body: Text('Test Content')),
          ),
        ),
      );
      expect(find.text('Test Content'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Test Content'), findsOneWidget);
    });
  });

  group('ShortcutTooltip', () {
    desktopTest('shows shortcut hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShortcutTooltip(
              label: 'New Script',
              shortcut: 'N',
              child: const Text('Button'),
            ),
          ),
        ),
      );
      final tooltipWidget = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltipWidget.message, equals('New Script (N)'));
    });
  });
}
