import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/marketplace_open_api_service.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Script Upload API E2E Tests', () {
    late MarketplaceOpenApiService marketplaceService;
    late String testScriptId;

    setUpAll(() async {
      // Initialize WranglerManager for real API testing
      await WranglerManager.initialize();
      
      // Use real service with production endpoint
      marketplaceService = MarketplaceOpenApiService();
      
      // Enable debug output
      suppressDebugOutput = false;
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

    test('Real API: Upload script and verify it appears in search results', () async {
      // Arrange: Get initial script count
      print('Getting initial script count...');
      final initialResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );
      
      final initialCount = initialResult.total;
      print('Initial script count: $initialCount');
      
      // Generate unique test script identifier
      final testScriptTitle = 'API E2E Test Script ${DateTime.now().millisecondsSinceEpoch}';

      // Act: Upload a new script
      print('Uploading new script: $testScriptTitle');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'API E2E test script for upload flow verification',
        category: 'Development',
        tags: ['e2e', 'api-test', 'upload-flow'],
        luaSource: '''-- API E2E Test Script for Upload Flow
function init(arg)
  return {
    message = "Hello from API E2E test!",
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
      },
      {
        type = "button",
        props = {
          label = "Increment",
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
end

print("API E2E test script loaded successfully!")''',
        authorName: 'API E2E Test Runner',
        version: '1.0.0',
        price: 0.0,
      );

      testScriptId = uploadedScript.id;
      print('Script uploaded with ID: $testScriptId');

      // Assert: Verify upload was successful
      expect(uploadedScript.title, equals(testScriptTitle));
      expect(uploadedScript.category, equals('Development'));
      expect(uploadedScript.isPublic, isTrue);
      expect(uploadedScript.authorName, equals('API E2E Test Runner'));

      // Act: Search for scripts immediately after upload
      print('Searching for scripts immediately after upload...');
      final afterUploadResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );

      // Assert: Verify script count increased by 1
      expect(afterUploadResult.total, equals(initialCount + 1),
          reason: 'Total script count should increase by 1 after upload');
      
      // Assert: Verify our uploaded script is in the results
      final foundScripts = afterUploadResult.scripts
          .where((script) => script.title == testScriptTitle)
          .toList();
      
      expect(foundScripts.length, equals(1),
          reason: 'Uploaded script should appear in search results immediately');
      
      final foundScript = foundScripts.first;
      expect(foundScript.id, equals(testScriptId));
      expect(foundScript.title, equals(testScriptTitle));
      expect(foundScript.description, contains('upload flow'));
      expect(foundScript.category, equals('Development'));
      expect(foundScript.authorName, equals('API E2E Test Runner'));
      expect(foundScript.tags, contains('e2e'));
      expect(foundScript.tags, contains('api-test'));
      expect(foundScript.tags, contains('upload-flow'));

      // Assert: Verify script appears at the top (newest first)
      final topScript = afterUploadResult.scripts.first;
      expect(topScript.id, equals(testScriptId),
          reason: 'Newly uploaded script should appear first when sorted by createdAt desc');

      print('✅ Script successfully uploaded and appears in search results!');
    });

    test('Real API: Can retrieve uploaded script by ID', () async {
      // This test assumes the previous test created a script
      expect(testScriptId.isNotEmpty, isTrue, reason: 'Test script ID should be set from previous test');

      // Act: Get script by ID
      print('Retrieving script by ID: $testScriptId');
      final retrievedScript = await marketplaceService.getScriptDetails(testScriptId);

      // Assert: Verify all script details
      expect(retrievedScript.id, equals(testScriptId));
      expect(retrievedScript.title, contains('API E2E Test Script'));
      expect(retrievedScript.description, contains('upload flow'));
      expect(retrievedScript.category, equals('Development'));
      expect(retrievedScript.authorName, equals('API E2E Test Runner'));
      expect(retrievedScript.isPublic, isTrue);
      expect(retrievedScript.luaSource, contains('API E2E Test Script for Upload Flow'));
      expect(retrievedScript.luaSource, contains('function init'));
      expect(retrievedScript.luaSource, contains('function view'));
      expect(retrievedScript.luaSource, contains('function update'));

      print('✅ Script details retrieved successfully!');
    });

    test('Real API: Script search by title works', () async {
      // This test assumes the previous test created a script
      expect(testScriptId.isNotEmpty, isTrue, reason: 'Test script ID should be set from previous tests');

      // Act: Search by our unique script title
      print('Searching by script title...');
      final searchResult = await marketplaceService.searchScripts(
        query: testScriptId.contains('API E2E') ? 'API E2E Test Script' : 'API E2E',
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 10,
        offset: 0,
      );

      // Assert: Should find at least our script
      expect(searchResult.scripts.isNotEmpty, isTrue,
          reason: 'Search should find at least one script');
      
      final foundScript = searchResult.scripts.firstWhere(
        (script) => script.id == testScriptId,
        orElse: () => throw Exception('Uploaded script not found in search results'),
      );
      expect(foundScript.id, equals(testScriptId));

      print('✅ Script search by title works!');
    });

    test('Real API: Uploaded script appears in correct category filter', () async {
      // This test assumes the previous test created a script
      expect(testScriptId.isNotEmpty, isTrue, reason: 'Test script ID should be set from previous test');

      // Act: Search specifically in Development category
      print('Searching in Development category...');
      final developmentResult = await marketplaceService.searchScripts(
        category: 'Development',
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 50,
        offset: 0,
      );

      // Assert: Verify our script appears in Development category
      final devScripts = developmentResult.scripts
          .where((script) => script.id == testScriptId)
          .toList();
      
      expect(devScripts.length, equals(1),
          reason: 'Uploaded script should appear in its category filter');
      
      // Act: Search in a different category (should not find our script)
      print('Searching in Gaming category (should not find our script)...');
      final gamingResult = await marketplaceService.searchScripts(
        category: 'Gaming',
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 50,
        offset: 0,
      );

      final gamingScripts = gamingResult.scripts
          .where((script) => script.id == testScriptId)
          .toList();
      
      expect(gamingScripts.isEmpty, isTrue,
          reason: 'Script should not appear in wrong category filter');

      print('✅ Script correctly appears in category filters!');
    });
  });
}