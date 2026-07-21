// UX-H5 Path 1: recent-calls Clear button must guard one-click history wipe
// behind a confirm dialog.
//
// CanisterHistoryService is a singleton backed by SharedPreferences key
// `canister_call_history` (JSON list of CanisterCallRecord). The test seeds
// the prefs before each widget pump so the widget renders with non-empty
// history.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/services/canister_history_service.dart';
import 'package:icp_autorun/widgets/recent_calls_list.dart';

void main() {
  const historyKey = 'canister_call_history';

  Future<void> seedHistory(int count) async {
    final records = List.generate(count, (i) {
      return CanisterCallRecord(
        canisterId: 'aaaaa-aa',
        methodName: 'method_$i',
        arguments: '()',
        timestamp: DateTime.utc(2026, 7, 1).add(Duration(minutes: i)),
        callType: CallType.query,
        resultSummary: 'success',
      ).toJson();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(historyKey, jsonEncode(records));
  }

  Future<void> pumpRecentCallsList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentCallsList(
            onTapEntry: (_, __, ___) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('UX-H5 Path 1: recent calls Clear confirm dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Clear button shows a confirm dialog and does NOT wipe on Cancel',
        (tester) async {
      await seedHistory(3);
      await pumpRecentCallsList(tester);

      // Sanity: history is rendered.
      expect(find.text('method_0'), findsOneWidget);
      expect(find.text('method_1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clearHistoryButton')));
      await tester.pumpAndSettle();

      // Dialog appears.
      expect(find.byKey(const Key('clearHistoryConfirmDialog')), findsOneWidget);
      expect(find.text('Clear call history?'), findsOneWidget);

      // Cancel → dialog closes, history preserved.
      await tester.tap(find.byKey(const Key('clearHistoryCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clearHistoryConfirmDialog')), findsNothing);
      expect(find.text('method_0'), findsOneWidget);

      final stored = await CanisterHistoryService().getHistory();
      expect(stored.length, 3);
    });

    testWidgets('Confirming the dialog wipes the history', (tester) async {
      await seedHistory(3);
      await pumpRecentCallsList(tester);

      await tester.tap(find.byKey(const Key('clearHistoryButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clearHistoryConfirmButton')));
      await tester.pumpAndSettle();

      // History wiped.
      expect(find.text('method_0'), findsNothing);
      expect(
        find.textContaining('No recent calls.'),
        findsOneWidget,
      );

      final stored = await CanisterHistoryService().getHistory();
      expect(stored, isEmpty);
    });

    testWidgets('Dismissing the dialog by tapping outside does NOT wipe',
        (tester) async {
      await seedHistory(2);
      await pumpRecentCallsList(tester);

      await tester.tap(find.byKey(const Key('clearHistoryButton')));
      await tester.pumpAndSettle();

      // Tap the barrier to dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clearHistoryConfirmDialog')), findsNothing);
      expect(find.text('method_0'), findsOneWidget);

      final stored = await CanisterHistoryService().getHistory();
      expect(stored.length, 2);
    });
  });
}
