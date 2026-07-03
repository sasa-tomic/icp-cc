import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/search_history_service.dart';

import '_scripts_test_harness.dart';

void main() {
  group('Search History UI', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('search field is present on ScriptsScreen', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search scripts...'), findsOneWidget);
    });

    testWidgets('search field has search icon', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('clear search history option is in menu', (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('test query');

      await pumpScriptsScreen(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Clear Search History'), findsOneWidget);

      await service.clearHistory();
    });

    testWidgets('recent searches dropdown appears when search field is focused',
        (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('previous search');

      await pumpScriptsScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('previous search'), findsOneWidget);

      await service.clearHistory();
    });

    testWidgets('clicking recent search fills search field', (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('lua script');

      await pumpScriptsScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('lua script'));
      await tester.pump(const Duration(milliseconds: 500));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals('lua script'));

      await service.clearHistory();
    });

    testWidgets('typing in search field shows clear button', (tester) async {
      await pumpScriptsScreen(tester);

      await tester.enterText(find.byType(TextField), 'test search');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clear button clears search field', (tester) async {
      await pumpScriptsScreen(tester);

      await tester.enterText(find.byType(TextField), 'test search');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });
  });
}
