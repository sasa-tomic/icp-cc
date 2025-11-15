import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_repository.dart';

void main() {
  test('ScriptRepository persists and loads scripts', () async {
    final Directory temp = await Directory.systemTemp.createTemp('scripts_repo_test_');
    final repo = ScriptRepository(overrideDirectory: temp);

    final now = DateTime.now().toUtc();
    final a = ScriptRecord(
      id: 'a',
      title: 'A',
      emoji: '🧪',
      imageUrl: null,
      luaSource: 'return 1',
      createdAt: now,
      updatedAt: now,
    );
    final b = ScriptRecord(
      id: 'b',
      title: 'B',
      emoji: null,
      imageUrl: 'local://img.png',
      luaSource: 'return 2',
      createdAt: now,
      updatedAt: now,
    );

    await repo.persistScripts([a, b]);
    final list = await repo.loadScripts();
    expect(list.length, 2);
    expect(list[0].id, 'a');
    expect(list[1].id, 'b');
  });
}
