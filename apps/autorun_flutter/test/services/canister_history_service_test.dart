import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/canister_history_service.dart';

void main() {
  group('CanisterHistoryService', () {
    late CanisterHistoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = CanisterHistoryService();
    });

    tearDown(() async {
      await service.clearHistory();
    });

    group('addCall', () {
      test('should add canister call to history', () async {
        await service.addCall(
          canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
          methodName: 'icrc1_balance_of',
          arguments: '{"account": {"owner": "abc123"}}',
          callType: CallType.query,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        expect(history.length, 1);
        expect(history.first.canisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
        expect(history.first.methodName, 'icrc1_balance_of');
        expect(history.first.arguments, '{"account": {"owner": "abc123"}}');
        expect(history.first.callType, CallType.query);
        expect(history.first.resultSummary, 'success');
      });

      test('should store calls in reverse chronological order', () async {
        await service.addCall(
          canisterId: 'canister-1',
          methodName: 'method_a',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );
        await Future.delayed(const Duration(milliseconds: 10));
        await service.addCall(
          canisterId: 'canister-2',
          methodName: 'method_b',
          arguments: '[]',
          callType: CallType.update,
          resultSummary: 'error: failed',
        );

        final history = await service.getHistory();
        expect(history.length, 2);
        expect(history.first.methodName, 'method_b');
        expect(history.last.methodName, 'method_a');
      });

      test('should cap history at 50 records', () async {
        for (int i = 0; i < 55; i++) {
          await service.addCall(
            canisterId: 'canister-$i',
            methodName: 'method_$i',
            arguments: '[]',
            callType: CallType.query,
            resultSummary: 'success',
          );
        }

        final history = await service.getHistory();
        expect(history.length, 50);
        expect(history.first.methodName, 'method_54');
      });

      test('should store timestamp correctly', () async {
        final before = DateTime.now();
        await service.addCall(
          canisterId: 'test',
          methodName: 'test',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );
        final after = DateTime.now();

        final history = await service.getHistory();
        expect(
            history.first.timestamp
                .isAfter(before.subtract(const Duration(seconds: 1))),
            isTrue);
        expect(
            history.first.timestamp
                .isBefore(after.add(const Duration(seconds: 1))),
            isTrue);
      });

      test('should store all call types', () async {
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
        expect(history[2].callType, CallType.query);
        expect(history[1].callType, CallType.update);
        expect(history[0].callType, CallType.compositeQuery);
      });
    });

    group('getHistory', () {
      test('should return empty list when no history', () async {
        final history = await service.getHistory();
        expect(history, isEmpty);
      });

      test('should return unmodifiable list', () async {
        await service.addCall(
          canisterId: 'test',
          methodName: 'test',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        expect(() => history.add(history.first), throwsUnsupportedError);
      });
    });

    group('clearHistory', () {
      test('should clear all history', () async {
        await service.addCall(
          canisterId: 'test1',
          methodName: 'method1',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );
        await service.addCall(
          canisterId: 'test2',
          methodName: 'method2',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );

        await service.clearHistory();

        final history = await service.getHistory();
        expect(history, isEmpty);
      });

      test('should handle clearing empty history', () async {
        await service.clearHistory();

        final history = await service.getHistory();
        expect(history, isEmpty);
      });
    });

    group('getCount', () {
      test('should return 0 for empty history', () async {
        expect(await service.getCount(), 0);
      });

      test('should return correct count', () async {
        await service.addCall(
          canisterId: 'test',
          methodName: 'method',
          arguments: '[]',
          callType: CallType.query,
          resultSummary: 'success',
        );
        await service.addCall(
          canisterId: 'test2',
          methodName: 'method2',
          arguments: '[]',
          callType: CallType.update,
          resultSummary: 'error',
        );

        expect(await service.getCount(), 2);
      });
    });

    group('persistence', () {
      test('should persist data across service instances', () async {
        await service.addCall(
          canisterId: 'persistent-canister',
          methodName: 'persistent_method',
          arguments: '{"key": "value"}',
          callType: CallType.query,
          resultSummary: 'success',
        );

        final newService = CanisterHistoryService();
        final history = await newService.getHistory();

        expect(history.length, 1);
        expect(history.first.canisterId, 'persistent-canister');
        expect(history.first.methodName, 'persistent_method');
        expect(history.first.arguments, '{"key": "value"}');
      });
    });

    group('CanisterCallRecord serialization', () {
      test('should serialize to JSON correctly', () {
        final record = CanisterCallRecord(
          canisterId: 'test-canister',
          methodName: 'test_method',
          arguments: '["arg1", "arg2"]',
          timestamp: DateTime.parse('2023-01-01T12:00:00.000Z'),
          callType: CallType.update,
          resultSummary: 'error: timeout',
        );

        final json = record.toJson();

        expect(json['canisterId'], 'test-canister');
        expect(json['methodName'], 'test_method');
        expect(json['arguments'], '["arg1", "arg2"]');
        expect(json['timestamp'], '2023-01-01T12:00:00.000Z');
        expect(json['callType'], 'update');
        expect(json['resultSummary'], 'error: timeout');
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'canisterId': 'test-canister',
          'methodName': 'test_method',
          'arguments': '{"test": true}',
          'timestamp': '2023-01-01T12:00:00.000Z',
          'callType': 'query',
          'resultSummary': 'success',
        };

        final record = CanisterCallRecord.fromJson(json);

        expect(record.canisterId, 'test-canister');
        expect(record.methodName, 'test_method');
        expect(record.arguments, '{"test": true}');
        expect(record.timestamp, DateTime.parse('2023-01-01T12:00:00.000Z'));
        expect(record.callType, CallType.query);
        expect(record.resultSummary, 'success');
      });

      test('should handle all call types in serialization', () {
        for (final type in CallType.values) {
          final record = CanisterCallRecord(
            canisterId: 'test',
            methodName: 'method',
            arguments: '[]',
            timestamp: DateTime.now(),
            callType: type,
            resultSummary: 'success',
          );

          final json = record.toJson();
          final restored = CanisterCallRecord.fromJson(json);

          expect(restored.callType, type);
        }
      });
    });

    group('error handling', () {
      test('should handle empty strings', () async {
        await service.addCall(
          canisterId: '',
          methodName: '',
          arguments: '',
          callType: CallType.query,
          resultSummary: '',
        );

        final history = await service.getHistory();
        expect(history.length, 1);
        expect(history.first.canisterId, '');
        expect(history.first.methodName, '');
        expect(history.first.arguments, '');
        expect(history.first.resultSummary, '');
      });

      test('should handle large arguments', () async {
        final largeArgs = '{"data": "${'x' * 10000}"}';

        await service.addCall(
          canisterId: 'test',
          methodName: 'test',
          arguments: largeArgs,
          callType: CallType.query,
          resultSummary: 'success',
        );

        final history = await service.getHistory();
        expect(history.first.arguments, largeArgs);
      });
    });
  });
}
