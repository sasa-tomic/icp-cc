import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  test('serializes and deserializes ScriptRecord', () {
    final now = DateTime.now().toUtc();
    final rec = ScriptRecord(
      id: '1',
      title: 'Balance Viewer',
      emoji: '💰',
      imageUrl: null,
      luaSource: 'return 1+2',
      createdAt: now,
      updatedAt: now,
    );
    final json = rec.toJson();
    final round = ScriptRecord.fromJson(json);
    expect(round.id, rec.id);
    expect(round.title, rec.title);
    expect(round.emoji, rec.emoji);
    expect(round.imageUrl, rec.imageUrl);
    expect(round.luaSource, rec.luaSource);
  });

  test('fails fast for empty id/title/luaSource', () {
    final now = DateTime.now().toUtc();
    expect(
      () => ScriptRecord.fromJson({
        'id': '',
        'title': 'x',
        'luaSource': 'print(1)',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => ScriptRecord.fromJson({
        'id': '1',
        'title': '',
        'luaSource': 'print(1)',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => ScriptRecord.fromJson({
        'id': '1',
        'title': 'x',
        'luaSource': '',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
  });
}
