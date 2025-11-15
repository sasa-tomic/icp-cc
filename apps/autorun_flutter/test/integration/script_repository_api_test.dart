import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/miniflare_script_repository.dart';

void main() {
  group('Script Repository API Tests', () {
    late MiniflareScriptRepository miniflareRepository;

    setUp(() async {
      // Initialize miniflare repository
      miniflareRepository = MiniflareScriptRepository();
      
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      // Clean up repository
      miniflareRepository.dispose();
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
          metadata: {
            'description': 'Test script for publishing',
            'category': 'Development',
            'tags': ['test', 'publish'],
            'authorName': 'Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Add script to repository
        await miniflareRepository.saveScript(testScript);

        // Assert - Verify script was saved
        final savedScripts = await miniflareRepository.getAllScripts();
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
          metadata: {
            'description': 'Original description',
            'category': 'Development',
            'tags': ['original'],
            'authorName': 'Original Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(originalScript);

        // Act - Update script
        final updatedMetadata = Map<String, dynamic>.from(originalScript.metadata);
        updatedMetadata['description'] = 'Updated description';
        updatedMetadata['category'] = 'Utility';
        updatedMetadata['tags'] = ['updated', 'modified'];
        updatedMetadata['authorName'] = 'Updated Author';
        updatedMetadata['version'] = '2.0.0';
        updatedMetadata['price'] = 1.0;
        updatedMetadata['isPublic'] = true;

        final updatedScript = ScriptRecord(
          id: originalScript.id,
          title: 'Updated Title',
          luaSource: '-- Updated source',
          metadata: updatedMetadata,
          createdAt: originalScript.createdAt,
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(updatedScript);

        // Assert - Verify script was updated
        final retrievedScript = await miniflareRepository.getScriptById(originalScript.id);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, 'Updated Title');
        expect(retrievedScript.luaSource, '-- Updated source');
        expect(retrievedScript.metadata['description'], 'Updated description');
        expect(retrievedScript.metadata['category'], 'Utility');
        expect(retrievedScript.metadata['isPublic'], true);
      });

      test('should delete script from repository', () async {
        // Arrange - Create and save a script
        final testScript = ScriptRecord(
          id: 'test-delete-script',
          title: 'Script to Delete',
          luaSource: '-- This will be deleted',
          metadata: {
            'description': 'Script for deletion testing',
            'category': 'Testing',
            'tags': ['delete', 'test'],
            'authorName': 'Delete Test',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(testScript);

        // Verify it exists
        var currentScripts = await miniflareRepository.getAllScripts();
        expect(currentScripts.any((s) => s.id == testScript.id), isTrue);

        // Act - Delete script
        await miniflareRepository.deleteScript(testScript.id);

        // Assert - Verify it was deleted
        final finalScripts = await miniflareRepository.getAllScripts();
        expect(finalScripts.any((s) => s.id == testScript.id), isFalse);
      });

      test('should list all scripts', () async {
        // Arrange - Create multiple scripts
        final scripts = [
          ScriptRecord(
            id: 'list-test-1',
            title: 'List Test Script 1',
            luaSource: '-- Script 1',
            metadata: {
              'description': 'First list test script',
              'category': 'Development',
              'tags': ['list', 'test'],
              'authorName': 'List Test Author',
              'version': '1.0.0',
              'price': 0.0,
              'isPublic': false,
            },
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ScriptRecord(
            id: 'list-test-2',
            title: 'List Test Script 2',
            luaSource: '-- Script 2',
            metadata: {
              'description': 'Second list test script',
              'category': 'Utility',
              'tags': ['list', 'test'],
              'authorName': 'List Test Author',
              'version': '1.0.0',
              'price': 0.0,
              'isPublic': true,
            },
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        for (final script in scripts) {
          await miniflareRepository.saveScript(script);
        }

        // Act - Get all scripts
        final allScripts = await miniflareRepository.getAllScripts();

        // Assert - Verify all scripts are present
        expect(allScripts.length, greaterThanOrEqualTo(2)); // Including mock test data
        expect(allScripts.any((s) => s.id == 'list-test-1'), isTrue);
        expect(allScripts.any((s) => s.id == 'list-test-2'), isTrue);
      });

      test('should search scripts by title and description', () async {
        // Arrange - Create scripts with searchable content
        final searchableScript = ScriptRecord(
          id: 'searchable-script',
          title: 'Unique Searchable Title',
          luaSource: '-- Searchable script',
          metadata: {
            'description': 'This is a unique description for searching',
            'category': 'Testing',
            'tags': ['searchable', 'test'],
            'authorName': 'Search Test',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(searchableScript);

        // Act - Search by title
        final titleResults = await miniflareRepository.searchScripts('Unique Searchable');
        
        // Act - Search by description
        final descriptionResults = await miniflareRepository.searchScripts('unique description');

        // Assert - Verify search works
        expect(titleResults.any((s) => s.id == 'searchable-script'), isTrue);
        expect(descriptionResults.any((s) => s.id == 'searchable-script'), isTrue);
      });

      test('should filter scripts by category', () async {
        // Arrange - Create scripts in different categories
        final devScript = ScriptRecord(
          id: 'dev-script',
          title: 'Development Script',
          luaSource: '-- Dev script',
          metadata: {
            'description': 'A development script',
            'category': 'Development',
            'tags': ['development', 'test'],
            'authorName': 'Dev Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final utilScript = ScriptRecord(
          id: 'util-script',
          title: 'Utility Script',
          luaSource: '-- Utility script',
          metadata: {
            'description': 'A utility script',
            'category': 'Utility',
            'tags': ['utility', 'test'],
            'authorName': 'Util Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await miniflareRepository.saveScript(devScript);
        await miniflareRepository.saveScript(utilScript);

        // Act - Get scripts by category
        final devScripts = await miniflareRepository.getScriptsByCategory('Development');
        final utilScripts = await miniflareRepository.getScriptsByCategory('Utility');

        // Assert - Verify filtering works
        expect(devScripts.any((s) => s.id == 'dev-script'), isTrue);
        expect(utilScripts.any((s) => s.id == 'util-script'), isTrue);
      });

      test('should get only public scripts', () async {
        // Arrange - Create public and private scripts
        final publicScript = ScriptRecord(
          id: 'public-script',
          title: 'Public Script',
          luaSource: '-- Public script',
          metadata: {
            'description': 'A public script',
            'category': 'Development',
            'tags': ['public', 'test'],
            'authorName': 'Public Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final privateScript = ScriptRecord(
          id: 'private-script',
          title: 'Private Script',
          luaSource: '-- Private script',
          metadata: {
            'description': 'A private script',
            'category': 'Development',
            'tags': ['private', 'test'],
            'authorName': 'Private Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await miniflareRepository.saveScript(publicScript);
        await miniflareRepository.saveScript(privateScript);

        // Act - Get public scripts
        final publicScripts = await miniflareRepository.getPublicScripts();

        // Assert - Verify only public scripts are returned
        expect(publicScripts.any((s) => s.id == 'public-script'), isTrue);
        expect(publicScripts.any((s) => s.id == 'private-script'), isFalse);
      });

      test('should publish script successfully', () async {
        // Arrange - Create a private script
        final privateScript = ScriptRecord(
          id: 'script-to-publish',
          title: 'Script to Publish',
          luaSource: '-- Will be published',
          metadata: {
            'description': 'Script that will be published',
            'category': 'Development',
            'tags': ['publish', 'test'],
            'authorName': 'Publish Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(privateScript);

        // Act - Publish the script
        final publishedId = await miniflareRepository.publishScript(privateScript);

        // Assert - Verify script is now public
        expect(publishedId, isNotEmpty);
        final publishedScript = await miniflareRepository.getScriptById(publishedId);
        expect(publishedScript, isNotNull);
        expect(publishedScript!.metadata['isPublic'], true);
      });

      test('should get accurate script count', () async {
        // Arrange - Get initial count
        final initialCount = await miniflareRepository.getScriptsCount();

        // Act - Add a new script
        final newScript = ScriptRecord(
          id: 'count-test-script',
          title: 'Count Test Script',
          luaSource: '-- For counting',
          metadata: {
            'description': 'Script for count testing',
            'category': 'Testing',
            'tags': ['count', 'test'],
            'authorName': 'Count Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await miniflareRepository.saveScript(newScript);

        // Assert - Verify count increased
        final finalCount = await miniflareRepository.getScriptsCount();
        expect(finalCount, equals(initialCount + 1));
      });
    });
  });
}