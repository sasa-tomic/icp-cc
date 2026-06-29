import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/services/script_repository.dart';

void main() {
  late Directory tempDir;
  late ScriptController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('script_controller_lang_');
    controller = ScriptController(ScriptRepository(overrideDirectory: tempDir));
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('createScript language handling', () {
    test('detects typescript from TS-looking luaSourceOverride', () async {
      const tsBundle = '(()=>{return{}})()';
      final rec = await controller.createScript(
        title: 'TS script',
        luaSourceOverride: tsBundle,
      );
      expect(rec.language, ScriptLanguage.typescript);
    });

    test('defaults to lua for empty override', () async {
      final rec = await controller.createScript(title: 'Default script');
      expect(rec.language, ScriptLanguage.lua);
    });

    test('detects lua from lua-shaped source', () async {
      const lua = 'function init(arg)\n  return {}, {}\nend';
      final rec = await controller.createScript(
        title: 'Lua script',
        luaSourceOverride: lua,
      );
      expect(rec.language, ScriptLanguage.lua);
    });

    test('explicit language wins over detection', () async {
      const tsBundle = '(()=>{return{}})()';
      final rec = await controller.createScript(
        title: 'Forced lua',
        luaSourceOverride: tsBundle,
        language: ScriptLanguage.lua,
      );
      expect(rec.language, ScriptLanguage.lua);
    });

    test('explicit typescript is honored for lua source', () async {
      const lua = 'function init(arg)\n  return {}, {}\nend';
      final rec = await controller.createScript(
        title: 'Forced ts',
        luaSourceOverride: lua,
        language: ScriptLanguage.typescript,
      );
      expect(rec.language, ScriptLanguage.typescript);
    });

    test('language persists through repository round-trip', () async {
      const tsBundle = 'const f=()=>1';
      final created = await controller.createScript(
        title: 'Persisted TS',
        luaSourceOverride: tsBundle,
      );
      expect(created.language, ScriptLanguage.typescript);

      final fresh = ScriptController(ScriptRepository(overrideDirectory: tempDir));
      addTearDown(fresh.dispose);
      await fresh.refresh();
      final reloaded = fresh.scripts.firstWhere((s) => s.id == created.id);
      expect(reloaded.language, ScriptLanguage.typescript);
    });
  });
}
