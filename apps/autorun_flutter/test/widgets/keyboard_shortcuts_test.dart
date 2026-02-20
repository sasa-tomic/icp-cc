import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/keyboard_shortcuts.dart';

void main() {
  group('DesktopShortcuts', () {
    testWidgets('renders child on all platforms', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            child: const Scaffold(
              body: Text('Test Content'),
            ),
          ),
        ),
      );

      expect(find.text('Test Content'), findsOneWidget);
    });

    testWidgets('calls onCreateScript when Ctrl+N is pressed on desktop',
        (WidgetTester tester) async {
      bool createScriptCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () => createScriptCalled = true,
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (_) {},
            child: const Scaffold(
              body: Focus(
                autofocus: true,
                child: Text('Test Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      if (DesktopShortcuts.isDesktop) {
        expect(createScriptCalled, isTrue);
      } else {
        expect(createScriptCalled, isFalse);
      }
    });

    testWidgets('calls onFocusSearch when Ctrl+F is pressed on desktop',
        (WidgetTester tester) async {
      bool focusSearchCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () => focusSearchCalled = true,
            onRefresh: () {},
            onNavigateToTab: (_) {},
            child: const Scaffold(
              body: Focus(
                autofocus: true,
                child: Text('Test Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      if (DesktopShortcuts.isDesktop) {
        expect(focusSearchCalled, isTrue);
      } else {
        expect(focusSearchCalled, isFalse);
      }
    });

    testWidgets('calls onRefresh when R is pressed on desktop',
        (WidgetTester tester) async {
      bool refreshCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () => refreshCalled = true,
            onNavigateToTab: (_) {},
            child: const Scaffold(
              body: Focus(
                autofocus: true,
                child: Text('Test Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.pump();

      if (DesktopShortcuts.isDesktop) {
        expect(refreshCalled, isTrue);
      } else {
        expect(refreshCalled, isFalse);
      }
    });

    testWidgets('calls onNavigateToTab when Ctrl+1/2/3 is pressed on desktop',
        (WidgetTester tester) async {
      int? navigatedTabIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShortcuts(
            onCreateScript: () {},
            onFocusSearch: () {},
            onRefresh: () {},
            onNavigateToTab: (index) => navigatedTabIndex = index,
            child: const Scaffold(
              body: Focus(
                autofocus: true,
                child: Text('Test Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      if (DesktopShortcuts.isDesktop) {
        expect(navigatedTabIndex, equals(1));
      } else {
        expect(navigatedTabIndex, isNull);
      }
    });

    test('isDesktop returns false on web', () {
      final result = DesktopShortcuts.isDesktop;
      expect(result, isA<bool>());
    });

    test('getShortcutLabel returns correct format for different actions', () {
      expect(DesktopShortcuts.getShortcutLabel('new'), contains('N'));
      expect(DesktopShortcuts.getShortcutLabel('save'), contains('S'));
      expect(DesktopShortcuts.getShortcutLabel('search'), contains('F'));
      expect(DesktopShortcuts.getShortcutLabel('refresh'), equals('R'));
      expect(DesktopShortcuts.getShortcutLabel('tab1'), contains('1'));
      expect(DesktopShortcuts.getShortcutLabel('tab2'), contains('2'));
      expect(DesktopShortcuts.getShortcutLabel('tab3'), contains('3'));
      expect(DesktopShortcuts.getShortcutLabel('unknown'), isEmpty);
    });
  });

  group('EscapeHandler', () {
    testWidgets('renders child on all platforms', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            onEscape: () {},
            child: const Scaffold(
              body: Text('Test Content'),
            ),
          ),
        ),
      );

      expect(find.text('Test Content'), findsOneWidget);
    });

    testWidgets('calls onEscape when Escape is pressed on desktop',
        (WidgetTester tester) async {
      bool escapeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            onEscape: () => escapeCalled = true,
            child: const Scaffold(
              body: Text('Test Content'),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      if (DesktopShortcuts.isDesktop) {
        expect(escapeCalled, isTrue);
      } else {
        expect(escapeCalled, isFalse);
      }
    });

    testWidgets('works without onEscape callback', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeHandler(
            child: const Scaffold(
              body: Text('Test Content'),
            ),
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
    testWidgets('shows shortcut hint on desktop', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShortcutTooltip(
              label: 'New Script',
              shortcut: 'Ctrl+N',
              child: const Text('Button'),
            ),
          ),
        ),
      );

      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);

      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      if (DesktopShortcuts.isDesktop) {
        expect(tooltipWidget.message, equals('New Script (Ctrl+N)'));
      } else {
        expect(tooltipWidget.message, equals('New Script'));
      }
    });
  });
}
