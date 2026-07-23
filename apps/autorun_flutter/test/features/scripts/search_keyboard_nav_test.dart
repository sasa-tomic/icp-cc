import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/search_history_service.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Search keyboard navigation (CR-7)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> focusSearchWithHistory(
      WidgetTester tester,
      List<String> queries,
    ) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      for (final q in queries) {
        await service.addSearchQuery(q);
      }

      await pumpScriptsScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('ArrowDown highlights the first recent search',
        (tester) async {
      await focusSearchWithHistory(tester, ['alpha', 'beta', 'gamma']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // First ListTile should have a non-null tileColor (highlighted).
      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(3));

      final firstTile = tester.widget<ListTile>(tiles.at(0));
      expect(firstTile.tileColor, isNotNull);

      await SearchHistoryService().clearHistory();
    });

    testWidgets('ArrowDown twice highlights the second item',
        (tester) async {
      await focusSearchWithHistory(tester, ['alpha', 'beta']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final tiles = find.byType(ListTile);
      final secondTile = tester.widget<ListTile>(tiles.at(1));
      expect(secondTile.tileColor, isNotNull);

      // First should no longer be highlighted.
      final firstTile = tester.widget<ListTile>(tiles.at(0));
      expect(firstTile.tileColor, isNull);

      await SearchHistoryService().clearHistory();
    });

    testWidgets('ArrowUp wraps from first to last', (tester) async {
      await focusSearchWithHistory(tester, ['alpha', 'beta', 'gamma']);

      // Press Down once to highlight first (index 0).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // Press Up — should wrap to last (index 2).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      final tiles = find.byType(ListTile);
      final lastTile = tester.widget<ListTile>(tiles.at(2));
      expect(lastTile.tileColor, isNotNull);

      await SearchHistoryService().clearHistory();
    });

    testWidgets('Enter selects highlighted search and fills field',
        (tester) async {
      await focusSearchWithHistory(tester, ['alpha', 'beta']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 500));

      // SearchHistoryService stores most-recent-first: index 0 = 'beta'.
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals('beta'));

      await SearchHistoryService().clearHistory();
    });

    testWidgets('Escape resets the highlight', (tester) async {
      await focusSearchWithHistory(tester, ['alpha', 'beta']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      final tiles = find.byType(ListTile);
      final firstTile = tester.widget<ListTile>(tiles.at(0));
      expect(firstTile.tileColor, isNull);

      await SearchHistoryService().clearHistory();
    });

    testWidgets('typing in search resets the highlight', (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('alpha');
      await service.addSearchQuery('beta');

      await pumpScriptsScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // Type a character — highlight should reset.
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 500));

      final tiles = find.byType(ListTile);
      if (tiles.evaluate().isNotEmpty) {
        final firstTile = tester.widget<ListTile>(tiles.at(0));
        expect(firstTile.tileColor, isNull);
      }

      await service.clearHistory();
    });
  });
}
