import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  test('serializes and deserializes ScriptRecord', () {
    final now = DateTime.now().toUtc();
    const bundle = 'globalThis.init=()=>({state:{},effects:[]});';
    final rec = ScriptRecord(
      id: '1',
      title: 'Balance Viewer',
      emoji: '💰',
      imageUrl: null,
      bundle: bundle,
      createdAt: now,
      updatedAt: now,
    );
    final json = rec.toJson();
    final round = ScriptRecord.fromJson(json);
    expect(round.id, rec.id);
    expect(round.title, rec.title);
    expect(round.emoji, rec.emoji);
    expect(round.imageUrl, rec.imageUrl);
    expect(round.bundle, bundle);
  });

  test('fails fast for empty id/title/bundle', () {
    final now = DateTime.now().toUtc();
    expect(
      () => ScriptRecord.fromJson({
        'id': '',
        'title': 'x',
        'bundle': 'globalThis.init=()=>({});',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => ScriptRecord.fromJson({
        'id': '1',
        'title': '',
        'bundle': 'globalThis.init=()=>({});',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => ScriptRecord.fromJson({
        'id': '1',
        'title': 'x',
        'bundle': '',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
      throwsFormatException,
    );
  });

  test('copyWith updates the bundle', () {
    final now = DateTime.now().toUtc();
    final rec = ScriptRecord(
      id: '1',
      title: 't',
      bundle: 'globalThis.init=()=>({state:{a:1},effects:[]});',
      createdAt: now,
      updatedAt: now,
    );
    const newBundle = 'globalThis.init=()=>({state:{a:2},effects:[]});';
    expect(rec.copyWith(bundle: newBundle).bundle, newBundle);
    expect(rec.copyWith().bundle, rec.bundle);
  });
}
