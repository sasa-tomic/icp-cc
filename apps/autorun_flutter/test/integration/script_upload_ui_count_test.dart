import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/config/app_config.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Script Upload UI Count E2E Tests', () {
    late MarketplaceOpenApiService marketplaceService;
    late String uploadedScriptId;

    setUpAll(() async {
      // Initialize WranglerManager for real API testing
      await WranglerManager.initialize();
      
      // Initialize marketplace service
      marketplaceService = MarketplaceOpenApiService();
      
      // Enable debug output to see API calls
      suppressDebugOutput = false;
      
      // Print configuration for debugging
      AppConfig.debugPrintConfig();
    });

    tearDownAll(() async {
      // Clean up: Try to delete test script if it was created
      if (uploadedScriptId.isNotEmpty) {
        try {
          await marketplaceService.deleteScript(uploadedScriptId);
          print('Cleaned up test script: $uploadedScriptId');
        } catch (e) {
          print('Failed to clean up test script: $e');
        }
      }
      
      // Restore debug output
      suppressDebugOutput = false;
      await WranglerManager.cleanup();
    });

    test('E2E: UI script count increases by exactly 1 after script upload', () async {
      print('\n=== E2E Test: UI Script Count Increase ===');

      // Step 1: Get initial UI script count (simulating what the UI would display)
      print('Step 1: Getting initial UI script count...');
      final initialSearchResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 50, // Typical UI page size
        offset: 0,
      );
      
      final initialUiCount = initialSearchResult.total;
      print('Initial UI script count: $initialUiCount');

      // Step 2: Verify initial state is reasonable
      expect(initialUiCount, greaterThan(0),
          reason: 'Should have some scripts in the marketplace initially');

      // Step 3: Create and upload a unique test script
      final uniqueTimestamp = DateTime.now().millisecondsSinceEpoch;
      final testScriptTitle = 'UI Count Test $uniqueTimestamp';
      
      print('Step 3: Uploading test script for UI count verification...');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'E2E test script specifically for UI count verification',
        category: 'Development',
        tags: ['e2e', 'ui-count', 'test'],
        luaSource: '''-- UI Count Test Script
-- This script verifies UI count increases correctly

function init(arg)
  return {
    ui_test = true,
    timestamp = $uniqueTimestamp,
    count = 0
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = "UI Count Test Script",
          style = "title"
        }
      },
      {
        type = "text",
        props = {
          text = "Test ID: " .. state.timestamp,
          style = "subtitle"
        }
      },
      {
        type = "button",
        props = {
          label = "Test UI Count",
          on_press = { type = "test_count" }
        }
      }
    }
  }
end

function update(msg, state)
  if msg.type == "test_count" then
    state.count = state.count + 1
  end
  return state, {}
end''',
        authorName: 'UI Count Test',
        canisterIds: [],
        version: '1.0.0',
        price: 0.0,
      );

      uploadedScriptId = uploadedScript.id;
      print('Script uploaded successfully with ID: $uploadedScriptId');

      // Verify upload was successful
      expect(uploadedScript.title, equals(testScriptTitle));
      expect(uploadedScript.category, equals('Development'));
      expect(uploadedScript.isPublic, isTrue);
      expect(uploadedScript.authorName, equals('UI Count Test'));

      // Step 4: Wait for UI to refresh (simulating user waiting for UI update)
      print('Step 4: Waiting for UI refresh...');
      await Future.delayed(const Duration(milliseconds: 1000));

      // Step 5: Get UI script count after upload (simulating UI refresh)
      print('Step 5: Getting UI script count after upload...');
      final afterUploadSearchResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 50, // Same as initial UI query
        offset: 0,
      );
      
      final afterUploadUiCount = afterUploadSearchResult.total;
      print('UI script count after upload: $afterUploadUiCount');

      // Step 6: Verify UI count increased by exactly 1
      final uiCountIncrease = afterUploadUiCount - initialUiCount;
      
      print('UI Count Analysis:');
      print('  Initial UI count: $initialUiCount');
      print('  After upload UI count: $afterUploadUiCount');
      print('  UI count increase: $uiCountIncrease');

      // Primary assertion: UI count should increase by exactly 1
      expect(uiCountIncrease, equals(1),
          reason: 'UI script count should increase by exactly 1 after upload');

      // Step 7: Verify uploaded script appears in UI results
      print('Step 7: Verifying uploaded script appears in UI results...');
      final foundScripts = afterUploadSearchResult.scripts
          .where((script) => script.id == uploadedScriptId)
          .toList();
      
      expect(foundScripts.length, equals(1),
          reason: 'Uploaded script should appear in UI search results');
      
      final foundScript = foundScripts.first;
      expect(foundScript.title, equals(testScriptTitle));
      expect(foundScript.id, equals(uploadedScriptId));

      // Step 8: Verify script appears at top of UI (newest first)
      print('Step 8: Verifying script appears at top of UI results...');
      final topScript = afterUploadSearchResult.scripts.first;
      expect(topScript.id, equals(uploadedScriptId),
          reason: 'Newly uploaded script should appear first in UI when sorted by createdAt desc');

      // Step 9: Simulate UI pagination test
      print('Step 9: Testing UI pagination consistency...');
      final paginatedResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 10, // Smaller page size for pagination test
        offset: 0,
      );
      
      expect(paginatedResult.total, equals(afterUploadUiCount),
          reason: 'Pagination should show same total count');
      
      expect(paginatedResult.scripts.first.id, equals(uploadedScriptId),
          reason: 'First page should show newest script');

      print('✅ E2E Test PASSED: UI script count increased by exactly 1');
      print('   Initial UI count: $initialUiCount');
      print('   Final UI count: $afterUploadUiCount');
      print('   UI count increase: $uiCountIncrease');
      print('   Script appears at top of UI: ✅');
      print('   Pagination consistency: ✅');
    });

    test('E2E: UI count remains stable when upload fails', () async {
      print('\n=== E2E Test: UI Count Stability on Upload Failure ===');

      // Get initial UI count
      final initialResult = await marketplaceService.searchScripts(
        limit: 50,
        offset: 0,
      );
      final initialCount = initialResult.total;
      print('Initial UI count: $initialCount');

      // Try to upload an invalid script (should fail)
      try {
        print('Attempting to upload invalid script...');
        await marketplaceService.uploadScript(
          title: '', // Empty title should cause failure
          description: 'Invalid script test',
          category: 'Development',
          tags: ['invalid'],
          luaSource: '-- Invalid script',
          authorName: 'Invalid Test',
          version: '1.0.0',
          price: 0.0,
        );
        
        fail('Upload should have failed with empty title');
      } catch (e) {
        print('Upload failed as expected: $e');
      }

      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 500));

      // Check UI count remains unchanged
      final afterFailureResult = await marketplaceService.searchScripts(
        limit: 50,
        offset: 0,
      );
      final afterFailureCount = afterFailureResult.total;

      expect(afterFailureCount, equals(initialCount),
          reason: 'UI count should remain unchanged when upload fails');

      print('✅ E2E Test PASSED: UI count stable on upload failure');
    });

    test('E2E: UI count updates correctly after script deletion', () async {
      print('\n=== E2E Test: UI Count Update After Deletion ===');

      // Upload a temporary script for deletion test
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempScriptTitle = 'Temp Delete Test $timestamp';
      
      print('Uploading temporary script for deletion test...');
      final tempScript = await marketplaceService.uploadScript(
        title: tempScriptTitle,
        description: 'Temporary script for deletion test',
        category: 'Utilities',
        tags: ['temp', 'delete-test'],
        luaSource: '-- Temporary script for deletion test\nprint("Delete me")',
        authorName: 'Delete Test',
        version: '1.0.0',
        price: 0.0,
      );

      final tempScriptId = tempScript.id;
      print('Temporary script uploaded: $tempScriptId');

      // Wait for upload to reflect
      await Future.delayed(const Duration(milliseconds: 500));

      // Get count after upload
      final afterUploadResult = await marketplaceService.searchScripts(
        limit: 50,
        offset: 0,
      );
      final afterUploadCount = afterUploadResult.total;

      // Delete the script
      print('Deleting temporary script...');
      await marketplaceService.deleteScript(tempScriptId);

      // Wait for deletion to reflect
      await Future.delayed(const Duration(milliseconds: 500));

      // Get count after deletion
      final afterDeleteResult = await marketplaceService.searchScripts(
        limit: 50,
        offset: 0,
      );
      final afterDeleteCount = afterDeleteResult.total;

      // Verify count decreased by exactly 1
      expect(afterDeleteCount, equals(afterUploadCount - 1),
          reason: 'UI count should decrease by exactly 1 after script deletion');

      // Verify script is no longer in results
      final foundScripts = afterDeleteResult.scripts
          .where((script) => script.id == tempScriptId)
          .toList();
      
      expect(foundScripts.isEmpty, isTrue,
          reason: 'Deleted script should not appear in search results');

      print('✅ E2E Test PASSED: UI count updates correctly after deletion');
      print('   Count after upload: $afterUploadCount');
      print('   Count after deletion: $afterDeleteCount');
      print('   Count decrease: ${afterUploadCount - afterDeleteCount}');
    });
  });
}