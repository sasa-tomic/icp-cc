import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Script Upload API Tests', () {
    late MarketplaceOpenApiService marketplaceService;
    late String testScriptTitle;
    String testScriptId = '';

    setUpAll(() async {
      // Initialize WranglerManager for real API testing
      await WranglerManager.initialize();
      
      // Initialize services
      marketplaceService = MarketplaceOpenApiService();
      
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
      
      // Generate unique test script identifier
      testScriptTitle = 'API Test Script ${DateTime.now().millisecondsSinceEpoch}';
      
      
    });

    tearDownAll(() async {
      // Clean up: Try to delete the test script if it was created
      if (testScriptId.isNotEmpty) {
        try {
          await marketplaceService.deleteScript(testScriptId);
          print('Cleaned up test script: $testScriptId');
        } catch (e) {
          print('Failed to clean up test script: $e');
        }
      }
      
      await WranglerManager.cleanup();
    });

    test('API: Verify uploaded script data integrity', () async {
      // This test verifies backend API integration
      
      // Upload a test script directly via API
      print('Uploading test script via API for data integrity check...');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'API test script for data integrity verification',
        category: 'Development',
        tags: ['api-test', 'data-integrity'],
        luaSource: '''-- API Test Script for Data Integrity
function init(arg)
  return {
    message = "Hello from API test!",
    counter = 0
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = state.message,
          style = "title"
        }
      },
      {
        type = "text",
        props = {
          text = "Counter: " .. state.counter,
          style = "subtitle"
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
        authorName: 'API Test Runner',
        version: '1.0.0',
        price: 0.0,
      );

      testScriptId = uploadedScript.id;
      print('Script uploaded with ID: $testScriptId');

      // Verify script details
      final retrievedScript = await marketplaceService.getScriptDetails(testScriptId);
      
      expect(retrievedScript.id, equals(testScriptId));
      expect(retrievedScript.title, equals(testScriptTitle));
      expect(retrievedScript.description, contains('data integrity'));
      expect(retrievedScript.category, equals('Development'));
      expect(retrievedScript.authorName, equals('API Test Runner'));
      expect(retrievedScript.isPublic, isTrue);
      expect(retrievedScript.price, equals(0.0));
      expect(retrievedScript.version, equals('1.0.0'));
      expect(retrievedScript.tags, contains('api-test'));
      expect(retrievedScript.tags, contains('data-integrity'));

      // Verify script appears in search results
      final searchResult = await marketplaceService.searchScripts(
        query: testScriptTitle,
        limit: 10,
      );

      expect(searchResult.scripts.isNotEmpty, isTrue);
      final foundScript = searchResult.scripts.firstWhere(
        (script) => script.id == testScriptId,
        orElse: () => throw Exception('Script not found in search results'),
      );
      
      expect(foundScript.title, equals(testScriptTitle));
      expect(foundScript.category, equals('Development'));

      print('✅ Script data integrity verified!');
    });
  });
}