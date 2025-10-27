import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_marketplace_service.dart';

void main() {
  group('Script Upload API Tests', () {
    late MockMarketplaceOpenApiService mockMarketplaceService;
    late String testScriptTitle;
    String testScriptId = '';

    setUp(() async {
      // Initialize mock service
      mockMarketplaceService = MockMarketplaceOpenApiService();
      
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
      
      // Generate unique test script identifier
      testScriptTitle = 'API Test Script ${DateTime.now().millisecondsSinceEpoch}';
      
      // Add mock test data
      mockMarketplaceService.addMockTestData();
    });

    tearDown(() async {
      // Clean up: Try to delete the test script if it was created
      if (testScriptId.isNotEmpty) {
        await mockMarketplaceService.deleteScript(testScriptId);
      }
      
      // Clear mock data
      mockMarketplaceService.clearMockData();
    });

    group('Script Upload Operations', () {
      test('should upload a new script successfully', () async {
        // Arrange - Create a test script
        final testScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: testScriptTitle,
          luaSource: '''-- API Test Script for Upload
-- This script tests the upload functionality

function init(arg)
  return {
    counter = 0,
    test_timestamp = ${DateTime.now().millisecondsSinceEpoch}
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = "API Test Script",
          style = "title"
        }
      },
      {
        type = "text",
        props = {
          text = "Timestamp: " .. state.test_timestamp,
          style = "subtitle"
        }
      },
      {
        type = "button",
        props = {
          label = "Increment Counter",
          on_press = { type = "increment" }
        }
      }
    }
  }
end

function update(msg, state)
  if msg.type == "increment" then
    state.counter = state.counter + 1
  end
  return state, {}
end''',
          metadata: {
            'description': 'Test script for upload API verification',
            'category': 'Development',
            'tags': ['test', 'api', 'upload'],
            'authorName': 'API Test Runner',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Upload the script
        testScriptId = await mockMarketplaceService.uploadScript(testScript);

        // Assert - Verify upload was successful
        expect(testScriptId, isNotEmpty);
        expect(testScriptId, startsWith('mock_script_'));

        // Verify the script can be retrieved
        final retrievedScript = await mockMarketplaceService.getScriptById(testScriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, equals(testScriptTitle));
        expect(retrievedScript.description, equals(testScript.metadata['description']));
        expect(retrievedScript.category, equals(testScript.metadata['category']));
        expect(retrievedScript.authorName, equals(testScript.metadata['authorName']));
        expect(retrievedScript.isPublic, true);
      });

      test('should handle script upload with special characters', () async {
        // Arrange - Create a script with special characters
        final specialScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Special Characters Test: naeiou symbols',
          luaSource: '''-- Special Characters Test
function init()
  return {
    message = "Hello: naeiou world!",
    symbols = "symbols_test",
    quotes = '"Double quotes" and 'single quotes''
  }, {}
end

function view(state)
  return {
    type = "text",
    text = state.message
  }
end''',
          metadata: {
            'description': 'Testing special chars: "quotes", \'apostrophes\', & symbols',
            'category': 'Testing',
            'tags': ['special-chars', 'ñáéíóú', 'test'],
            'authorName': 'Test Author N',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Upload the script with special characters
        final specialScriptId = await mockMarketplaceService.uploadScript(specialScript);

        // Assert - Verify upload was successful
        expect(specialScriptId, isNotEmpty);

        // Verify the script data is preserved correctly
        final retrievedScript = await mockMarketplaceService.getScriptById(specialScriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, contains('naeiou'));
        expect(retrievedScript.description, contains('quotes'));
        expect(retrievedScript.authorName, contains('N'));
      });

      test('should handle script upload with empty optional fields', () async {
        // Arrange - Create a script with minimal required fields
        final minimalScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Minimal Script',
          luaSource: '''-- Minimal Test Script
function init()
  return {}, {}
end

function view(state)
  return {
    type = "text",
    text = "Minimal script"
  }
end''',
          metadata: {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Upload the minimal script
        final minimalScriptId = await mockMarketplaceService.uploadScript(minimalScript);

        // Assert - Verify upload was successful
        expect(minimalScriptId, isNotEmpty);

        // Verify the script was saved with default values
        final retrievedScript = await mockMarketplaceService.getScriptById(minimalScriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, equals('Minimal Script'));
        expect(retrievedScript.description, isEmpty);
        expect(retrievedScript.tags, isEmpty);
        expect(retrievedScript.authorName, equals('Mock Author'));
      });

      test('should handle script upload with large content', () async {
        // Arrange - Create a script with large content
        final largeLuaCode = List.generate(100, (i) => 
          '-- Line ${i + 1}: This is a long line with some content to test large script handling\n'
        ).join();

        final largeScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Large Content Script',
          luaSource: largeLuaCode,
          metadata: {
            'description': 'A script with large content to test upload limits',
            'category': 'Testing',
            'tags': ['large', 'content', 'test'],
            'authorName': 'Large Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Upload the large script
        final largeScriptId = await mockMarketplaceService.uploadScript(largeScript);

        // Assert - Verify upload was successful
        expect(largeScriptId, isNotEmpty);

        // Verify the large content was preserved
        final retrievedScript = await mockMarketplaceService.getScriptById(largeScriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.luaSource.length, equals(largeLuaCode.length));
        expect(retrievedScript.luaSource, contains('Line 50:'));
        expect(retrievedScript.luaSource, contains('Line 100:'));
      });
    });

    group('Script Retrieval Operations', () {
      test('should retrieve uploaded script by ID', () async {
        // Arrange - Upload a test script first
        final testScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Retrieval Test Script',
          luaSource: '''-- Retrieval Test Script
function init()
  return { message = "Retrieval test" }, {}
end

function view(state)
  return {
    type = "text",
    text = state.message
  }
end''',
          metadata: {
            'description': 'Script for testing retrieval by ID',
            'category': 'Testing',
            'tags': ['retrieval', 'test'],
            'authorName': 'Retrieval Test',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final uploadedScriptId = await mockMarketplaceService.uploadScript(testScript);

        // Act - Retrieve the script by ID
        final retrievedScript = await mockMarketplaceService.getScriptById(uploadedScriptId);

        // Assert - Verify the retrieved script matches the original
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.id, equals(uploadedScriptId));
        expect(retrievedScript.title, equals(testScript.title));
        expect(retrievedScript.description, equals(testScript.metadata['description']));
        expect(retrievedScript.category, equals(testScript.metadata['category']));
        expect(retrievedScript.authorName, equals(testScript.metadata['authorName']));
        expect(retrievedScript.luaSource, equals(testScript.luaSource));
        expect(retrievedScript.isPublic, equals(testScript.metadata['isPublic']));
      });

      test('should return null for non-existent script ID', () async {
        // Act - Try to retrieve a script with non-existent ID
        final nonExistentScript = await mockMarketplaceService.getScriptById('non_existent_id');

        // Assert - Verify null is returned
        expect(nonExistentScript, isNull);
      });
    });

    group('Script Update Operations', () {
      test('should update existing script successfully', () async {
        // Arrange - Upload a test script first
        final originalScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Original Title',
          luaSource: '-- Original source',
          metadata: {
            'description': 'Original description',
            'category': 'Development',
            'tags': ['original'],
            'authorName': 'Original Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final scriptId = await mockMarketplaceService.uploadScript(originalScript);

        // Create updated version
        final updatedMetadata = Map<String, dynamic>.from(originalScript.metadata);
        updatedMetadata['description'] = 'Updated description';
        updatedMetadata['category'] = 'Utility';
        updatedMetadata['tags'] = ['updated', 'modified'];
        updatedMetadata['authorName'] = 'Updated Author';
        updatedMetadata['version'] = '2.0.0';
        updatedMetadata['price'] = 1.0;

        final updatedScript = ScriptRecord(
          id: scriptId,
          title: 'Updated Title',
          luaSource: '-- Updated source code',
          metadata: updatedMetadata,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Update the script
        final updateSuccess = await mockMarketplaceService.updateScript(scriptId, updatedScript);

        // Assert - Verify update was successful
        expect(updateSuccess, isTrue);

        // Verify the updated content
        final retrievedScript = await mockMarketplaceService.getScriptById(scriptId);
        expect(retrievedScript, isNotNull);
        expect(retrievedScript!.title, equals('Updated Title'));
        expect(retrievedScript.description, equals('Updated description'));
        expect(retrievedScript.category, equals('Utility'));
        expect(retrievedScript.tags, contains('updated'));
        expect(retrievedScript.tags, contains('modified'));
        expect(retrievedScript.authorName, equals('Updated Author'));
        expect(retrievedScript.luaSource, equals('-- Updated source code'));
        expect(retrievedScript.version, equals('2.0.0'));
        expect(retrievedScript.price, equals(1.0));
      });

      test('should fail to update non-existent script', () async {
        // Arrange - Create an update script for non-existent ID
        final updateScript = ScriptRecord(
          id: 'non_existent_id',
          title: 'Non-existent Update',
          luaSource: '-- Should fail',
          metadata: {
            'description': 'This should fail',
            'category': 'Testing',
            'tags': ['fail'],
            'authorName': 'Test',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act - Try to update non-existent script
        final updateSuccess = await mockMarketplaceService.updateScript('non_existent_id', updateScript);

        // Assert - Verify update failed
        expect(updateSuccess, isFalse);
      });
    });

    group('Script Delete Operations', () {
      test('should delete existing script successfully', () async {
        // Arrange - Upload a test script first
        final testScript = ScriptRecord(
          id: '', // Empty ID for new script
          title: 'Script to Delete',
          luaSource: '-- This will be deleted',
          metadata: {
            'description': 'This script will be deleted',
            'category': 'Testing',
            'tags': ['delete', 'test'],
            'authorName': 'Delete Test',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final scriptId = await mockMarketplaceService.uploadScript(testScript);

        // Verify it exists before deletion
        final beforeDeletion = await mockMarketplaceService.getScriptById(scriptId);
        expect(beforeDeletion, isNotNull);

        // Act - Delete the script
        final deleteSuccess = await mockMarketplaceService.deleteScript(scriptId);

        // Assert - Verify deletion was successful
        expect(deleteSuccess, isTrue);

        // Verify it no longer exists
        final afterDeletion = await mockMarketplaceService.getScriptById(scriptId);
        expect(afterDeletion, isNull);
      });

      test('should handle deletion of non-existent script', () async {
        // Act - Try to delete non-existent script
        final deleteSuccess = await mockMarketplaceService.deleteScript('non_existent_id');

        // Assert - Should still return true (idempotent operation)
        expect(deleteSuccess, isTrue);
      });
    });

    group('Marketplace Stats Operations', () {
      test('should get marketplace statistics', () async {
        // Act - Get marketplace stats
        final stats = await mockMarketplaceService.getMarketplaceStats();

        // Assert - Verify stats structure
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats.containsKey('totalScripts'), isTrue);
        expect(stats.containsKey('totalDownloads'), isTrue);
        expect(stats.containsKey('categories'), isTrue);
        expect(stats.containsKey('averageRating'), isTrue);

        // Verify data types
        expect(stats['totalScripts'], isA<int>());
        expect(stats['totalDownloads'], isA<int>());
        expect(stats['categories'], isA<List>());
        expect(stats['averageRating'], isA<double>());
      });
    });
  });
}