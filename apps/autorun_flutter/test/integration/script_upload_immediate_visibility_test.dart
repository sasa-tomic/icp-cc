import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/marketplace_open_api_service.dart';

import '../test_helpers/wrangler_manager.dart';

// Enable debug output for marketplace service
void main() {
  // Temporarily enable debug output for debugging
  suppressDebugOutput = false;
  group('Script Upload Immediate Visibility E2E Tests', () {
    late MarketplaceOpenApiService marketplaceService;
    late String testScriptId;
    late String testScriptTitle;

    setUpAll(() async {
      // Initialize WranglerManager for real API testing
      await WranglerManager.initialize();
      
      // Use real service with production endpoint
      marketplaceService = MarketplaceOpenApiService();
      
      // Generate unique test script identifier
      testScriptTitle = 'E2E Test Script ${DateTime.now().millisecondsSinceEpoch}';
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

    test('Real API: Script upload immediately reflects in search results', () async {
      // Arrange: Get initial script count
      print('Getting initial script count...');
      final initialResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100, // Get more to be accurate
        offset: 0,
      );
      
      final initialCount = initialResult.total;
      print('Initial script count: $initialCount');
      
      // Verify our test script doesn't exist yet
      final existingTestScripts = initialResult.scripts
          .where((script) => script.title.contains('E2E Test Script'))
          .toList();
      expect(existingTestScripts.isEmpty, isTrue, 
          reason: 'Test script should not exist before upload');

      // Act: Upload a new script
      print('Uploading new script: $testScriptTitle');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'E2E test script for immediate visibility verification',
        category: 'Development',
        tags: ['e2e', 'test', 'visibility'],
        luaSource: '''-- E2E Test Script for Immediate Visibility
-- This script tests that uploaded scripts appear immediately

function init(arg)
  return {
    counter = 0,
    message = "Hello from E2E test!"
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

print("E2E test script loaded successfully!")''',
        authorName: 'E2E Test Runner',
        canisterIds: [],
        version: '1.0.0',
        price: 0.0,
      );

      testScriptId = uploadedScript.id;
      print('Script uploaded with ID: $testScriptId');
      print('Upload response details:');
      print('  Title: ${uploadedScript.title}');
      print('  Category: ${uploadedScript.category}');
      print('  Is Public: ${uploadedScript.isPublic}');
      print('  Author: ${uploadedScript.authorName}');
      print('  Created At: ${uploadedScript.createdAt}');

      // Assert: Verify upload was successful
      expect(uploadedScript.title, equals(testScriptTitle));
      expect(uploadedScript.category, equals('Development'));
      expect(uploadedScript.isPublic, isTrue);
      expect(uploadedScript.authorName, equals('E2E Test Runner'));

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
      expect(foundScript.description, contains('immediate visibility'));
      expect(foundScript.category, equals('Development'));
      expect(foundScript.authorName, equals('E2E Test Runner'));
      expect(foundScript.tags, contains('e2e'));
      expect(foundScript.tags, contains('test'));
      expect(foundScript.tags, contains('visibility'));

      // Assert: Verify script appears at the top (newest first)
      final topScript = afterUploadResult.scripts.first;
      expect(topScript.id, equals(testScriptId),
          reason: 'Newly uploaded script should appear first when sorted by createdAt desc');

      print('✅ Script successfully appears in search results immediately!');
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
          .where((script) => script.title == testScriptTitle)
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
          .where((script) => script.title == testScriptTitle)
          .toList();
      
      expect(gamingScripts.isEmpty, isTrue,
          reason: 'Script should not appear in wrong category filter');

      print('✅ Script correctly appears in category filters!');
    });

    test('Real API: Can retrieve uploaded script by ID', () async {
      // This test assumes the previous tests created a script
      expect(testScriptId.isNotEmpty, isTrue, reason: 'Test script ID should be set from previous tests');

      // Act: Get script by ID
      print('Retrieving script by ID: $testScriptId');
      final retrievedScript = await marketplaceService.getScriptDetails(testScriptId);

      // Assert: Verify all script details
      expect(retrievedScript.id, equals(testScriptId));
      expect(retrievedScript.title, equals(testScriptTitle));
      expect(retrievedScript.description, contains('immediate visibility'));
      expect(retrievedScript.category, equals('Development'));
      expect(retrievedScript.authorName, equals('E2E Test Runner'));
      expect(retrievedScript.isPublic, isTrue);
      expect(retrievedScript.luaSource, contains('E2E Test Script for Immediate Visibility'));
      expect(retrievedScript.luaSource, contains('function init'));
      expect(retrievedScript.luaSource, contains('function view'));
      expect(retrievedScript.luaSource, contains('function update'));

      print('✅ Script details retrieved successfully!');
    });

    test('Real API: Script search by title works', () async {
      // This test assumes the previous tests created a script
      expect(testScriptId.isNotEmpty, isTrue, reason: 'Test script ID should be set from previous tests');

      // Act: Search by our unique script title
      print('Searching by script title...');
      final searchResult = await marketplaceService.searchScripts(
        query: testScriptTitle,
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 10,
        offset: 0,
      );

      // Assert: Should find exactly our script
      expect(searchResult.scripts.length, equals(1),
          reason: 'Search by unique title should find exactly one script');
      
      final foundScript = searchResult.scripts.first;
      expect(foundScript.id, equals(testScriptId));
      expect(foundScript.title, equals(testScriptTitle));

      print('✅ Script search by title works!');
    });

    test('Real API: Multiple uploads increase count correctly', () async {
      // Get current count
      final beforeCount = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );

      // Upload another test script
      final secondScriptTitle = 'E2E Second Test ${DateTime.now().millisecondsSinceEpoch}';
      print('Uploading second test script: $secondScriptTitle');
      
      final secondScript = await marketplaceService.uploadScript(
        title: secondScriptTitle,
        description: 'Second E2E test script',
        category: 'Utilities',
        tags: ['e2e', 'second'],
        luaSource: '-- Second test script\nprint("Second test!")',
        authorName: 'E2E Test Runner',
        version: '1.0.0',
        price: 0.0,
      );

      // Get count after second upload
      final afterSecondCount = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );

      // Verify count increased by exactly 1
      expect(afterSecondCount.total, equals(beforeCount.total + 1),
          reason: 'Script count should increase by exactly 1 after each upload');

      // Clean up second script
      try {
        await marketplaceService.deleteScript(secondScript.id);
        print('Cleaned up second test script: ${secondScript.id}');
      } catch (e) {
        print('Failed to clean up second test script: $e');
      }

      print('✅ Multiple uploads increase count correctly!');
    });
  });
}