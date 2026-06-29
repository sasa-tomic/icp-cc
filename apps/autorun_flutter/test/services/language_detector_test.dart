import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/language_detector.dart';
import 'package:icp_autorun/services/script_runner.dart';

void main() {
  group('detectLanguage', () {
    test('IIFE bundle is typescript', () {
      expect(detectLanguage('(()=>{return{}})()'), ScriptLanguage.typescript);
      expect(
        detectLanguage('(function(){return {}})()'),
        ScriptLanguage.typescript,
      );
    });

    test('function init/view/update body is lua', () {
      expect(
        detectLanguage('function init(arg)\n  return {}\nend'),
        ScriptLanguage.lua,
      );
      expect(
        detectLanguage('function view(state)\n  return {}\nend'),
        ScriptLanguage.lua,
      );
      expect(
        detectLanguage('function update(msg, state)\n  return state, {}\nend'),
        ScriptLanguage.lua,
      );
    });

    test('comment line plus local is lua', () {
      expect(detectLanguage('-- comment\nlocal x=1'), ScriptLanguage.lua);
    });

    test('arrow function is typescript', () {
      expect(detectLanguage('const f=()=>1'), ScriptLanguage.typescript);
    });

    test('SDK register call is typescript', () {
      expect(
        detectLanguage('register(init,view,update)'),
        ScriptLanguage.typescript,
      );
    });

    test('empty string defaults to lua', () {
      expect(detectLanguage(''), ScriptLanguage.lua);
      expect(detectLanguage('   \n  '), ScriptLanguage.lua);
    });

    test('canonical Lua sample is lua', () {
      const lua = '''
function init(arg)
  return {
    count = 0,
    name = ""
  }, {}
end

function view(state)
  return { type = "text", props = { text = "hi" } }
end

function update(msg, state)
  return state, {}
end
''';
      expect(detectLanguage(lua), ScriptLanguage.lua);
    });

    test('local keyword on its own line is lua', () {
      expect(detectLanguage('local x = 1'), ScriptLanguage.lua);
    });

    test('whitespace-prefixed IIFE is typescript', () {
      expect(
        detectLanguage('  \n  (()=>{return{}})()'),
        ScriptLanguage.typescript,
      );
    });
  });

  group('scriptLanguageToJson', () {
    test('serializes each variant', () {
      expect(scriptLanguageToJson(ScriptLanguage.lua), 'lua');
      expect(scriptLanguageToJson(ScriptLanguage.typescript), 'typescript');
    });
  });

  group('scriptLanguageFromJson', () {
    test('parses known values', () {
      expect(scriptLanguageFromJson('lua'), ScriptLanguage.lua);
      expect(scriptLanguageFromJson('typescript'), ScriptLanguage.typescript);
    });

    test('round-trips through toJson', () {
      for (final lang in ScriptLanguage.values) {
        expect(scriptLanguageFromJson(scriptLanguageToJson(lang)), lang);
      }
    });

    test('unknown and null default to lua', () {
      expect(scriptLanguageFromJson(null), ScriptLanguage.lua);
      expect(scriptLanguageFromJson('rust'), ScriptLanguage.lua);
      expect(scriptLanguageFromJson(42), ScriptLanguage.lua);
    });
  });
}
