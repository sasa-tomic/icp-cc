import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('ScriptRecord usage stats', () {
    late ScriptRecord baseRecord;

    setUp(() {
      baseRecord = ScriptRecord(
        id: 'test-id',
        title: 'Test Script',
        luaSource: 'print("hello")',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
    });

    group('recordRun()', () {
      test('increments run count from 0 to 1', () {
        expect(baseRecord.runCount, equals(0));

        final updated = baseRecord.recordRun();

        expect(updated.runCount, equals(1));
        expect(baseRecord.runCount, equals(0));
      });

      test('increments run count from N to N+1', () {
        final recordWithRuns = baseRecord.copyWith(runCount: 5);

        final updated = recordWithRuns.recordRun();

        expect(updated.runCount, equals(6));
      });

      test('sets lastRunAt to current time', () {
        final beforeRun = DateTime.now();

        final updated = baseRecord.recordRun();

        final afterRun = DateTime.now();
        expect(updated.lastRunAt, isNotNull);
        expect(
            updated.lastRunAt!
                .isAfter(beforeRun.subtract(const Duration(seconds: 1))),
            isTrue);
        expect(
            updated.lastRunAt!
                .isBefore(afterRun.add(const Duration(seconds: 1))),
            isTrue);
      });

      test('updates lastRunAt on subsequent runs', () async {
        final firstRun = baseRecord.recordRun();
        await Future.delayed(const Duration(milliseconds: 10));

        final secondRun = firstRun.recordRun();

        expect(secondRun.lastRunAt!.isAfter(firstRun.lastRunAt!), isTrue);
      });

      test('preserves all other fields', () {
        final record = ScriptRecord(
          id: 'my-id',
          title: 'My Script',
          emoji: '📜',
          imageUrl: 'https://example.com/image.png',
          luaSource: 'print("test")',
          createdAt: DateTime(2023, 6, 15),
          updatedAt: DateTime(2024, 1, 1),
          metadata: {'marketplace_id': 'mp-123'},
        );

        final updated = record.recordRun();

        expect(updated.id, equals(record.id));
        expect(updated.title, equals(record.title));
        expect(updated.emoji, equals(record.emoji));
        expect(updated.imageUrl, equals(record.imageUrl));
        expect(updated.luaSource, equals(record.luaSource));
        expect(updated.createdAt, equals(record.createdAt));
        expect(updated.updatedAt, equals(record.updatedAt));
        expect(updated.metadata, equals(record.metadata));
      });
    });

    group('JSON serialization', () {
      test('toJson includes runCount and lastRunAt', () {
        final record = baseRecord.copyWith(
          runCount: 42,
          lastRunAt: DateTime.utc(2024, 6, 15, 10, 30),
        );

        final json = record.toJson();

        expect(json['runCount'], equals(42));
        expect(json['lastRunAt'], equals('2024-06-15T10:30:00.000Z'));
      });

      test('fromJson parses runCount and lastRunAt', () {
        final json = {
          'id': 'test-id',
          'title': 'Test Script',
          'luaSource': 'print("hello")',
          'createdAt': '2024-01-01T00:00:00.000Z',
          'updatedAt': '2024-01-01T00:00:00.000Z',
          'runCount': 10,
          'lastRunAt': '2024-06-15T10:30:00.000Z',
        };

        final record = ScriptRecord.fromJson(json);

        expect(record.runCount, equals(10));
        expect(record.lastRunAt, equals(DateTime.utc(2024, 6, 15, 10, 30)));
      });

      test('toJson with null lastRunAt omits value', () {
        final json = baseRecord.toJson();

        expect(json['runCount'], equals(0));
        expect(json['lastRunAt'], isNull);
      });

      test('round-trip preserves usage stats', () {
        final original = baseRecord.copyWith(
          runCount: 99,
          lastRunAt: DateTime.utc(2024, 12, 25, 12, 0),
        );

        final roundTripped = ScriptRecord.fromJson(original.toJson());

        expect(roundTripped.runCount, equals(original.runCount));
        expect(roundTripped.lastRunAt, equals(original.lastRunAt));
      });
    });

    group('backward compatibility', () {
      test('JSON without runCount defaults to 0', () {
        final json = {
          'id': 'test-id',
          'title': 'Test Script',
          'luaSource': 'print("hello")',
          'createdAt': '2024-01-01T00:00:00.000Z',
          'updatedAt': '2024-01-01T00:00:00.000Z',
        };

        final record = ScriptRecord.fromJson(json);

        expect(record.runCount, equals(0));
      });

      test('JSON without lastRunAt defaults to null', () {
        final json = {
          'id': 'test-id',
          'title': 'Test Script',
          'luaSource': 'print("hello")',
          'createdAt': '2024-01-01T00:00:00.000Z',
          'updatedAt': '2024-01-01T00:00:00.000Z',
        };

        final record = ScriptRecord.fromJson(json);

        expect(record.lastRunAt, isNull);
      });

      test('new record has default usage stats', () {
        final record = ScriptRecord(
          id: 'new-id',
          title: 'New Script',
          luaSource: 'return 1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(record.runCount, equals(0));
        expect(record.lastRunAt, isNull);
      });
    });

    group('copyWith usage stats', () {
      test('copyWith can update runCount', () {
        final updated = baseRecord.copyWith(runCount: 5);

        expect(updated.runCount, equals(5));
        expect(baseRecord.runCount, equals(0));
      });

      test('copyWith can update lastRunAt', () {
        final newTime = DateTime.utc(2024, 12, 31);
        final updated = baseRecord.copyWith(lastRunAt: newTime);

        expect(updated.lastRunAt, equals(newTime));
        expect(baseRecord.lastRunAt, isNull);
      });

      test('copyWith preserves existing usage stats when not specified', () {
        final record = baseRecord.copyWith(
          runCount: 10,
          lastRunAt: DateTime.utc(2024, 6, 1),
        );

        final updated = record.copyWith(title: 'Updated Title');

        expect(updated.runCount, equals(10));
        expect(updated.lastRunAt, equals(DateTime.utc(2024, 6, 1)));
      });
    });
  });
}
