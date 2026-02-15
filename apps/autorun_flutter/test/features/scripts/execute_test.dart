import 'package:flutter_test/flutter_test.dart';
import 'package:autorun_flutter/services/script_runner.dart';
import 'package:autorun_flutter/models/profile_keypair.dart';

import '../shared/test_helpers.dart';

/// E2E test: Script execution with Lua runtime
/// 
/// This test covers the complete script execution flow:
/// 1. Load Lua script
/// 2. Execute with input
/// 3. Handle effects (ICP calls)
/// 4. Render UI output
void main() {
  late ScriptRunner runner;
  late TestKeypair testKeypair;

  setUpAll(() async {
    testKeypair = TestKeypairFactory.getEd25519Keypair();
    runner = ScriptRunner();
  });

  group('execute lua script', () {
    test('script can return simple message', () async {
      final luaSource = '''
        function init(arg)
          return { message = arg.message or "Hello" }, {}
        end
        
        function view(state)
          return {
            type = "message",
            content = state.message
          }
        end
      ''';

      final result = await runner.execute(
        luaSource: luaSource,
        input: {'message': 'Test Message'},
      );

      expect(result.success, isTrue);
      expect(result.output, isNotNull);
      expect(result.output!['type'], equals('message'));
      expect(result.output!['content'], equals('Test Message'));
    });

    test('script can return list items', () async {
      final luaSource = '''
        function init(arg)
          return { items = {"Item 1", "Item 2", "Item 3"} }, {}
        end
        
        function view(state)
          return {
            type = "list",
            title = "My List",
            items = state.items
          }
        end
      ''';

      final result = await runner.execute(luaSource: luaSource);

      expect(result.success, isTrue);
      expect(result.output!['type'], equals('list'));
      expect(result.output!['items'], hasLength(3));
    });

    test('script handles syntax errors gracefully', () async {
      final luaSource = '''
        function init(arg)
          return { -- missing closing brace
        end
      ''';

      final result = await runner.execute(luaSource: luaSource);

      expect(result.success, isFalse);
      expect(result.error, isNotEmpty);
      expect(result.error, contains('syntax'));
    });

    test('script can make ICP call effect', () async {
      final luaSource = '''
        function init(arg)
          return {}, {
            {
              type = "icp_call",
              id = "call-1",
              canister_id = "aaaaa-aa",
              method = "greet",
              args = { name = "Test" }
            }
          }
        end
        
        function view(state)
          return { type = "message", content = "Calling..." }
        end
      ''';

      final result = await runner.execute(
        luaSource: luaSource,
        keypair: testKeypair,
      );

      expect(result.success, isTrue);
      expect(result.effects, isNotEmpty);
      expect(result.effects!.first['type'], equals('icp_call'));
    });

    test('script respects execution timeout', () async {
      final luaSource = '''
        function init(arg)
          while true do end -- infinite loop
          return {}, {}
        end
      ''';

      final result = await runner.execute(
        luaSource: luaSource,
        timeoutMs: 1000,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('timeout'));
    });
  });

  group('script update cycle', () {
    test('script can handle button click', () async {
      final luaSource = '''
        local state = { count = 0 }
        
        function init(arg)
          return state, {}
        end
        
        function update(msg, state)
          if msg.type == "button_click" and msg.id == "increment" then
            return { count = state.count + 1 }, {}
          end
          return state, {}
        end
        
        function view(state)
          return {
            type = "column",
            children = {
              { type = "message", content = "Count: " .. state.count },
              { type = "button", id = "increment", label = "Increment" }
            }
          }
        end
      ''';

      // Initial render
      var result = await runner.execute(luaSource: luaSource);
      expect(result.success, isTrue);
      expect(result.output, isNotNull);

      // Simulate button click
      result = await runner.execute(
        luaSource: luaSource,
        initialState: result.state,
        message: {'type': 'button_click', 'id': 'increment'},
      );

      expect(result.success, isTrue);
      final content = result.output!['children'][0]['content'] as String;
      expect(content, contains('Count: 1'));
    });
  });
}
