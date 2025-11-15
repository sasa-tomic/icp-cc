import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_template.dart';

/// Focused tests covering the new asset-loading behavior for script templates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ScriptTemplates.resetForTest();
  });

  test('ScriptTemplates throws when accessed before initialization', () {
    ScriptTemplates.resetForTest();
    expect(() => ScriptTemplates.templates, throwsStateError);
  });

  test('ScriptTemplates.ensureInitialized loads Lua sources from bundled assets', () async {
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();

    final template = ScriptTemplates.getById('hello_world');
    expect(template, isNotNull, reason: 'hello_world template must be available after initialization');

    final expected = File('lib/examples/01_hello_world.lua').readAsStringSync();
    expect(template!.luaSource, expected, reason: 'Template must mirror the actual Lua asset contents');
  });

  test('ScriptTemplate.load surfaces bundle failures immediately', () async {
    final template = ScriptTemplate(
      id: 'broken_template',
      title: 'Broken Template',
      description: 'This template should fail to load.',
      emoji: '❌',
      level: 'beginner',
      tags: const ['test'],
      filePath: 'lib/examples/missing_template.lua',
    );

    final bundle = _ThrowingAssetBundle();

    await expectLater(
      template.load(bundle),
      throwsA(
        isA<StateError>().having(
          (err) => err.toString(),
          'message',
          contains('Failed to load Lua template asset'),
        ),
      ),
    );
  });
}

class _ThrowingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    throw FlutterError('missing asset: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    throw FlutterError('missing asset: $key');
  }
}
