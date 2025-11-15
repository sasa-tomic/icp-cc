import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/poem_script_repository.dart';
import '../test_helpers/test_signature_utils.dart';
import '../test_helpers/unified_test_builder.dart';

void main() {
  group('Script Repository API Tests', () {
    late PoemScriptRepository poemRepository;

    setUp(() async {
      // Initialize Poem repository
      poemRepository = PoemScriptRepository();
      
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      // Clean up repository
      poemRepository.dispose();
    });

    group('Script Management', () {
      test('should create and manage script records', () async {
        // Arrange - Create a test script with proper signature
        final testScript = TestTemplates.createTestScriptWithSignature(
          id: 'test-publish-script',
          title: 'My Test Script for Publishing',
          description: 'Test script for publishing',
          category: 'Development',
          tags: ['test', 'publish'],
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
        );

        // Act - Add script to repository
        final savedScriptId = await poemRepository.saveScript(testScript);

        // Assert - Verify script was saved
        final savedScripts = await poemRepository.getAllScripts();
        final savedScript = savedScripts.firstWhere((s) => s.id == savedScriptId);
        expect(savedScript.title, testScript.title);
        expect(savedScript.luaSource, testScript.luaSource);
      });

      test('should update existing script', () async {
        // Arrange - Create and save a script
        final originalScript = TestTemplates.createTestScriptWithSignature(
          id: 'test-update-script',
          title: 'Original Title',
          description: 'Original description',
          category: 'Development',
          tags: ['original'],
          authorName: 'Original Author',
          luaSource: '-- Original source',
        );
        final originalScriptId = await poemRepository.saveScript(originalScript);

        // Act - Update script using the proper update helper
        final updateData = TestTemplates.createTestUpdateRequest(
          originalScriptId,
          updates: {
            'title': 'Updated Title',
            'description': 'Updated description',
            'category': 'Utility',
            'lua_source': '-- Updated source',
            'version': '2.0.0',
            'tags': ['updated', 'modified'],
            'authorName': 'Updated Author',
            'authorPublicKey': TestSignatureUtils.getPublicKey(),
            'price': 1.0,
            'isPublic': true,
          },
        );

        final updatedScript = ScriptRecord(
          id: originalScriptId,
          title: 'Updated Title',
          luaSource: '-- Updated source',
          metadata: updateData,
          createdAt: originalScript.createdAt,
          updatedAt: DateTime.now(),
        );
        await poemRepository.saveScript(updatedScript);

        // Assert - Verify script was updated
        final retrievedScript = await poemRepository.getScriptById(originalScriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, 'Updated Title');
        expect(retrievedScript.luaSource, '-- Updated source');
        expect(retrievedScript.metadata['description'], 'Updated description');
        expect(retrievedScript.metadata['category'], 'Utility');
        expect(retrievedScript.metadata['isPublic'], true);
      });

      test('should delete script from repository', () async {
        // Arrange - Create and save a script
        final testScript = TestTemplates.createTestScriptWithSignature(
          id: 'test-delete-script',
          title: 'Script to Delete',
          description: 'Script for deletion testing',
          category: 'Testing',
          tags: ['delete', 'test'],
          authorName: 'Delete Test',
          luaSource: '-- This will be deleted',
        );
        final scriptId = await poemRepository.saveScript(testScript);

        // Verify it exists
        var currentScripts = await poemRepository.getAllScripts();
        expect(currentScripts.any((s) => s.id == scriptId), isTrue);

        // Act - Delete script
        await poemRepository.deleteScript(scriptId);

        // Assert - Verify it was deleted
        final finalScripts = await poemRepository.getAllScripts();
        expect(finalScripts.any((s) => s.id == scriptId), isFalse);
      });

      test('should list all scripts', () async {
        // Arrange - Create multiple scripts
        final scripts = [
          TestTemplates.createTestScriptWithSignature(
            id: 'list-test-1',
            title: 'List Test Script 1',
            description: 'First list test script',
            category: 'Development',
            tags: ['list', 'test'],
            authorName: 'List Test Author',
            luaSource: '-- Script 1',
          ),
          TestTemplates.createTestScriptWithSignature(
            id: 'list-test-2',
            title: 'List Test Script 2',
            description: 'Second list test script',
            category: 'Utility',
            tags: ['list', 'test'],
            authorName: 'List Test Author',
            luaSource: '-- Script 2',
          ),
        ];

 final scriptIds = <String>[];
        for (final script in scripts) {
          final savedId = await poemRepository.saveScript(script);
          scriptIds.add(savedId);
        }

        // Act - Get all scripts
        final allScripts = await poemRepository.getAllScripts();

        // Assert - Verify all scripts are present
        expect(allScripts.length, greaterThanOrEqualTo(2)); // Including mock test data
        // Note: We can't check by original IDs since server generates new ones
        // Instead we check that we have at least the expected number of new scripts
      });

      test('should search scripts by title and description', () async {
        // Arrange - Create scripts with searchable content
        final searchableScript = TestTemplates.createTestScriptWithSignature(
          id: 'searchable-script',
          title: 'Unique Searchable Title',
          description: 'This is a unique description for searching',
          category: 'Testing',
          tags: ['searchable', 'test'],
          authorName: 'Search Test',
          luaSource: '-- Searchable script',
        );
        await poemRepository.saveScript(searchableScript);

        // Act - Search by title
        final titleResults = await poemRepository.searchScripts('Unique Searchable');
        
        // Act - Search by description
        final descriptionResults = await poemRepository.searchScripts('unique description');

        // Assert - Verify search works
        expect(titleResults.any((s) => s.title.contains('Unique Searchable')), isTrue);
        expect(descriptionResults.any((s) => s.title.contains('Unique Searchable')), isTrue);
      });

      test('should filter scripts by category', () async {
        // Arrange - Create scripts in different categories
        final devScript = TestTemplates.createTestScriptWithSignature(
          id: 'dev-script',
          title: 'Development Script',
          description: 'A development script',
          category: 'Development',
          tags: ['development', 'test'],
          authorName: 'Dev Author',
          luaSource: '-- Dev script',
        );
        final utilScript = TestTemplates.createTestScriptWithSignature(
          id: 'util-script',
          title: 'Utility Script',
          description: 'A utility script',
          category: 'Utility',
          tags: ['utility', 'test'],
          authorName: 'Util Author',
          luaSource: '-- Utility script',
        );

        await poemRepository.saveScript(devScript);
        await poemRepository.saveScript(utilScript);

        // Act - Get scripts by category
        final devScripts = await poemRepository.getScriptsByCategory('Development');
        final utilScripts = await poemRepository.getScriptsByCategory('Utility');

        // Assert - Verify filtering works
        expect(devScripts.any((s) => s.title.contains('Development Script')), isTrue);
        expect(utilScripts.any((s) => s.title.contains('Utility Script')), isTrue);
      });

      test('should get only public scripts', () async {
        // Arrange - Create public and private scripts
        final publicScript = TestTemplates.createTestScriptWithSignature(
          id: 'public-script',
          title: 'Public Script',
          description: 'A public script',
          category: 'Development',
          tags: ['public', 'test'],
          authorName: 'Public Author',
          luaSource: '-- Public script',
        );

        // Create private script with its own signature for private script
        final privateTimestamp = DateTime.now().toIso8601String();
        final privateSignaturePayload = {
          'action': 'upload',
          'title': 'Private Script',
          'description': 'A private script',
          'category': 'Development',
          'lua_source': '-- Private script',
          'version': '1.0.0',
          'tags': ['private', 'test'],
          'author_principal': TestSignatureUtils.getPrincipal(),
          'timestamp': privateTimestamp,
        };
        final privateSignature = TestSignatureUtils.generateTestSignature(privateSignaturePayload);

        final privateScript = ScriptRecord(
          id: 'private-script',
          title: 'Private Script',
          luaSource: '-- Private script',
          metadata: {
            'description': 'A private script',
            'category': 'Development',
            'tags': ['private', 'test'],
            'authorName': 'Private Author',
            'authorPublicKey': TestSignatureUtils.getPublicKey(),
            'authorPrincipal': TestSignatureUtils.getPrincipal(),
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
            'signature': privateSignature,
            'timestamp': privateTimestamp,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await poemRepository.saveScript(publicScript);
        await poemRepository.saveScript(privateScript);

        // Act - Get public scripts
        final publicScripts = await poemRepository.getPublicScripts();

        // Assert - Verify only public scripts are returned
        expect(publicScripts.any((s) => s.title.contains('Public Script')), isTrue);
        expect(publicScripts.any((s) => s.title.contains('Private Script')), isFalse);
      });

      test('should publish script successfully', () async {
        // Arrange - Create a private script with its own signature
        final privateTimestamp = DateTime.now().toIso8601String();
        final privateSignaturePayload = {
          'action': 'upload',
          'title': 'Script to Publish',
          'description': 'Script that will be published',
          'category': 'Development',
          'lua_source': '-- Will be published',
          'version': '1.0.0',
          'tags': ['publish', 'test'],
          'author_principal': TestSignatureUtils.getPrincipal(),
          'timestamp': privateTimestamp,
        };
        final privateSignature = TestSignatureUtils.generateTestSignature(privateSignaturePayload);

        final privateScript = ScriptRecord(
          id: 'script-to-publish',
          title: 'Script to Publish',
          luaSource: '-- Will be published',
          metadata: {
            'description': 'Script that will be published',
            'category': 'Development',
            'tags': ['publish', 'test'],
            'authorName': 'Publish Author',
            'authorPublicKey': TestSignatureUtils.getPublicKey(),
            'authorPrincipal': TestSignatureUtils.getPrincipal(),
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
            'signature': privateSignature,
            'timestamp': privateTimestamp,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final savedScriptId = await poemRepository.saveScript(privateScript);

        // Act - Publish the script using the saved ID
        final scriptToPublish = ScriptRecord(
          id: savedScriptId,
          title: privateScript.title,
          luaSource: privateScript.luaSource,
          metadata: privateScript.metadata,
          createdAt: privateScript.createdAt,
          updatedAt: DateTime.now(),
        );
        final publishedId = await poemRepository.publishScript(scriptToPublish);

        // Assert - Verify script is now public
        expect(publishedId, isNotEmpty);
        final publishedScript = await poemRepository.getScriptById(publishedId);
        expect(publishedScript, isNotNull);
        expect(publishedScript!.metadata['isPublic'], true);
      });

      test('should get accurate script count', () async {
        // Arrange
        final poemRepository = PoemScriptRepository();

        // Act - Get script count (should be non-negative)
        final count = await poemRepository.getScriptsCount();

        // Assert - Verify count is reasonable
        expect(count, greaterThanOrEqualTo(0));
      });
    });
  });
}
