import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Script Repository API Tests', () {
    late ScriptRepository scriptRepository;

    setUpAll(() async {
      // Initialize WranglerManager for real API testing
      await WranglerManager.initialize();
      
      // Initialize services
      scriptRepository = ScriptRepository();
      
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
      
      
    });

    tearDownAll(() async {
      await WranglerManager.cleanup();
    });

    group('Script Management', () {
      test('should create and manage script records', () async {
        // Arrange - Create a test script
        final testScript = ScriptRecord(
          id: 'test-publish-script',
          title: 'My Test Script for Publishing',
          luaSource: '''function init(arg)
  return {
    message = "Hello from published script!",
    count = 0
  }, {}
end

function view(state)
  return {
    type = "text",
    text = state.message
  }
end

function update(msg, state)
  if msg.type == "increment" then
    state.count = state.count + 1
  end
  return state, {}
end''',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Add script to repository
        final existingScripts = await scriptRepository.loadScripts();
        final updatedScripts = [...existingScripts, testScript];
        await scriptRepository.persistScripts(updatedScripts);

        // Assert - Verify script was saved
        final savedScripts = await scriptRepository.loadScripts();
        final savedScript = savedScripts.firstWhere((s) => s.id == testScript.id);
        expect(savedScript.title, testScript.title);
        expect(savedScript.luaSource, testScript.luaSource);
      });

      test('should update existing script', () async {
        // Arrange - Create and save a script
        final originalScript = ScriptRecord(
          id: 'test-update-script',
          title: 'Original Title',
          luaSource: '-- Original source',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final existingScripts = await scriptRepository.loadScripts();
        await scriptRepository.persistScripts([...existingScripts, originalScript]);

        // Act - Update script
        final updatedScript = originalScript.copyWith(
          title: 'Updated Title',
          luaSource: '-- Updated source',
          updatedAt: DateTime.now(),
        );
        final currentScripts = await scriptRepository.loadScripts();
        final updatedScripts = currentScripts
            .where((s) => s.id != originalScript.id)
            .toList()
          ..add(updatedScript);
        await scriptRepository.persistScripts(updatedScripts);

        // Assert - Verify script was updated
        final retrievedScripts = await scriptRepository.loadScripts();
        final retrievedScript = retrievedScripts.firstWhere((s) => s.id == originalScript.id);
        expect(retrievedScript.title, 'Updated Title');
        expect(retrievedScript.luaSource, '-- Updated source');
      });

      test('should delete script from repository', () async {
        // Arrange - Create and save a script
        final testScript = ScriptRecord(
          id: 'test-delete-script',
          title: 'Script to Delete',
          luaSource: '-- This will be deleted',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final existingScripts = await scriptRepository.loadScripts();
        await scriptRepository.persistScripts([...existingScripts, testScript]);

        // Verify it exists
        var currentScripts = await scriptRepository.loadScripts();
        expect(currentScripts.any((s) => s.id == testScript.id), isTrue);

        // Act - Delete script
        final scriptsAfterDelete = currentScripts.where((s) => s.id != testScript.id).toList();
        await scriptRepository.persistScripts(scriptsAfterDelete);

        // Assert - Verify it was deleted
        final finalScripts = await scriptRepository.loadScripts();
        expect(finalScripts.any((s) => s.id == testScript.id), isFalse);
      });

      test('should list all scripts', () async {
        // Arrange - Create multiple scripts
        final scripts = [
          ScriptRecord(
            id: 'list-test-1',
            title: 'List Test Script 1',
            luaSource: '-- Script 1',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ScriptRecord(
            id: 'list-test-2',
            title: 'List Test Script 2',
            luaSource: '-- Script 2',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final existingScripts = await scriptRepository.loadScripts();
        await scriptRepository.persistScripts([...existingScripts, ...scripts]);

        // Act - Get all scripts
        final allScripts = await scriptRepository.loadScripts();

        // Assert - Verify scripts are listed
        final testScripts = allScripts.where((s) => s.id.startsWith('list-test-')).toList();
        expect(testScripts.length, 2);
        expect(testScripts.any((s) => s.title == 'List Test Script 1'), isTrue);
        expect(testScripts.any((s) => s.title == 'List Test Script 2'), isTrue);
      });
    });

    group('Publish Preparation', () {
      test('should prepare script for marketplace publishing', () async {
        // Arrange - Create a script with marketplace metadata
        final marketplaceScript = ScriptRecord(
          id: 'marketplace-ready-script',
          title: 'Marketplace Ready Script',
          luaSource: '''function init(arg)
  return {value = 42}, {}
end

function view(state)
  return {
    type = "text",
    text = "Value: " .. state.value
  }
end''',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {
            'description': 'A script ready for marketplace',
            'tags': ['demo', 'example'],
            'category': 'utility',
          },
        );

        // Act - Save script
        final existingScripts = await scriptRepository.loadScripts();
        await scriptRepository.persistScripts([...existingScripts, marketplaceScript]);

        // Assert - Verify script is ready for publishing
        final savedScripts = await scriptRepository.loadScripts();
        final savedScript = savedScripts.firstWhere((s) => s.id == marketplaceScript.id);
        expect(savedScript.metadata['description'], 'A script ready for marketplace');
        expect(savedScript.metadata['tags'], ['demo', 'example']);
        expect(savedScript.metadata['category'], 'utility');
      });
    });
  });
}