import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/canister_history_service.dart';

void main() {
  group('Canister Client History', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    group('CanisterHistoryService integration', () {
      testWidgets('should populate form when replaying from history',
          (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        await service.addCall(
          canisterId: 'test-canister-id',
          methodName: 'test_method',
          arguments: '{"account": "123"}',
          callType: CallType.query,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        expect(history.length, 1);

        final record = history.first;
        expect(record.canisterId, 'test-canister-id');
        expect(record.methodName, 'test_method');
        expect(record.arguments, '{"account": "123"}');

        await service.clearHistory();
      });

      testWidgets('should display empty state when no history', (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        final history = await service.getHistory();
        expect(history, isEmpty);
      });

      testWidgets('should show success/error status in history items',
          (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        await service.addCall(
          canisterId: 'canister-1',
          methodName: 'success_method',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        await service.addCall(
          canisterId: 'canister-2',
          methodName: 'error_method',
          arguments: '[]',
          callType: CallType.update,
          resultSummary: 'error: timeout',
        );

        final history = await service.getHistory();
        expect(history[0].resultSummary, 'error: timeout');
        expect(history[1].resultSummary, 'success');

        await service.clearHistory();
      });

      testWidgets('should clear all history on clear button', (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        await service.addCall(
          canisterId: 'canister-1',
          methodName: 'method_1',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );
        await service.addCall(
          canisterId: 'canister-2',
          methodName: 'method_2',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        expect(await service.getCount(), 2);

        await service.clearHistory();

        expect(await service.getCount(), 0);
      });
    });

    group('History list display', () {
      testWidgets('should format timestamp correctly', (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        await service.addCall(
          canisterId: 'test',
          methodName: 'test',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        final record = history.first;

        final now = DateTime.now();
        expect(record.timestamp.difference(now).inSeconds.abs(), lessThan(2));

        await service.clearHistory();
      });

      testWidgets('should differentiate call types visually', (tester) async {
        final service = CanisterHistoryService();
        await service.clearHistory();

        await service.addCall(
          canisterId: 'test',
          methodName: 'query_method',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        await service.addCall(
          canisterId: 'test',
          methodName: 'update_method',
          arguments: '[]',
          callType: CallType.update,
          resultSummary: 'success',
        );

        await service.addCall(
          canisterId: 'test',
          methodName: 'composite_method',
          arguments: '[]',
          callType: CallType.compositeQuery,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        expect(history[0].callType, CallType.compositeQuery);
        expect(history[1].callType, CallType.update);
        expect(history[2].callType, CallType.query);

        await service.clearHistory();
      });
    });
  });
}
