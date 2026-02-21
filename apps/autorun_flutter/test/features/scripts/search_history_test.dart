import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/search_history_service.dart';

void main() {
  group('Search History UI', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('search field is present on ScriptsScreen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search scripts...'), findsOneWidget);
    });

    testWidgets('search field has search icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('clear search history option is in menu', (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('test query');

      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

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

      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('previous search'), findsOneWidget);

      await service.clearHistory();
    });

    testWidgets('clicking recent search fills search field', (tester) async {
      final service = SearchHistoryService();
      await service.clearHistory();
      await service.addSearchQuery('lua script');

      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('lua script'));
      await tester.pump(const Duration(milliseconds: 500));

      final textField = tester.widget<TextField>(searchField);
      expect(textField.controller?.text, equals('lua script'));

      await service.clearHistory();
    });

    testWidgets('typing in search field shows clear button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'test search');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clear button clears search field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScriptsScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'test search');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final textField = tester.widget<TextField>(searchField);
      expect(textField.controller?.text, isEmpty);
    });
  });
}
