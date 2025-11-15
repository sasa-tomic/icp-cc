 import 'package:flutter_test/flutter_test.dart';
 import 'package:icp_autorun/services/marketplace_open_api_service.dart';
 import 'package:icp_autorun/config/app_config.dart';
 import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Script Upload Count Increase E2E Tests', () {
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

    test('E2E: Script upload increases UI script count by exactly 1', () async {
      print('\n=== E2E Test: Script Upload Count Increase ===');

      // Step 1: Get initial script count from marketplace
      print('Step 1: Getting initial script count...');
      final initialSearchResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100, // Get enough scripts to be accurate
        offset: 0,
      );
      
      final initialScriptCount = initialSearchResult.total;
      print('Initial script count: $initialScriptCount');

      // Step 2: Get initial marketplace stats for cross-verification
      print('Step 2: Getting initial marketplace stats...');
      final initialStats = await marketplaceService.getMarketplaceStats();
      print('Initial stats - Total scripts: ${initialStats.totalScripts}');

      // Verify both sources agree on initial count
      expect(initialStats.totalScripts, equals(initialScriptCount),
          reason: 'Search count and stats count should match initially');

      // Step 3: Create and upload a unique test script
      final uniqueTimestamp = DateTime.now().millisecondsSinceEpoch;
      final testScriptTitle = 'Count Test Script $uniqueTimestamp';
      
      print('Step 3: Uploading test script: $testScriptTitle');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'E2E test script to verify count increases by exactly 1',
        category: 'Development',
        tags: ['e2e', 'count-test', 'verification'],
        luaSource: '''-- E2E Count Test Script
-- This script verifies that script count increases by exactly 1

function init(arg)
  return {
    counter = 0,
    test_timestamp = $uniqueTimestamp
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = "Count Test Script",
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
        authorName: 'E2E Count Test',
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
      expect(uploadedScript.authorName, equals('E2E Count Test'));

      // Step 4: Wait a brief moment for database consistency
      print('Step 4: Waiting for database consistency...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 5: Get script count after upload
      print('Step 5: Getting script count after upload...');
      final afterUploadSearchResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );
      
      final afterUploadScriptCount = afterUploadSearchResult.total;
      print('Script count after upload: $afterUploadScriptCount');

      // Step 6: Get marketplace stats after upload
      print('Step 6: Getting marketplace stats after upload...');
      final afterUploadStats = await marketplaceService.getMarketplaceStats();
      print('Stats after upload - Total scripts: ${afterUploadStats.totalScripts}');

      // Step 7: Verify count increased by exactly 1
      final searchCountIncrease = afterUploadScriptCount - initialScriptCount;
      final statsCountIncrease = afterUploadStats.totalScripts - initialStats.totalScripts;
      
      print('Count verification:');
      print('  Search count increase: $searchCountIncrease');
      print('  Stats count increase: $statsCountIncrease');

      // Primary assertion: Search count should increase by exactly 1
      expect(searchCountIncrease, equals(1),
          reason: 'Search script count should increase by exactly 1 after upload');

      // Secondary assertion: Stats count should also increase by exactly 1
      expect(statsCountIncrease, equals(1),
          reason: 'Marketplace stats count should increase by exactly 1 after upload');

      // Cross-verification: Both counts should still match
      expect(afterUploadStats.totalScripts, equals(afterUploadScriptCount),
          reason: 'Search count and stats count should still match after upload');

      // Step 8: Verify our uploaded script is in the results
      print('Step 8: Verifying uploaded script appears in search results...');
      final foundScripts = afterUploadSearchResult.scripts
          .where((script) => script.id == uploadedScriptId)
          .toList();
      
      expect(foundScripts.length, equals(1),
          reason: 'Uploaded script should appear in search results');
      
      final foundScript = foundScripts.first;
      expect(foundScript.title, equals(testScriptTitle));
      expect(foundScript.id, equals(uploadedScriptId));

      // Step 9: Verify script appears at the top (newest first)
      print('Step 9: Verifying script appears at top of results...');
      final topScript = afterUploadSearchResult.scripts.first;
      expect(topScript.id, equals(uploadedScriptId),
          reason: 'Newly uploaded script should appear first when sorted by createdAt desc');

      print('✅ E2E Test PASSED: Script count increased by exactly 1');
      print('   Initial count: $initialScriptCount');
      print('   Final count: $afterUploadScriptCount');
      print('   Increase: $searchCountIncrease');
    });

    test('E2E: Multiple uploads increase count cumulatively', () async {
      print('\n=== E2E Test: Multiple Uploads Cumulative Count ===');

      // Get baseline count
      final baselineResult = await marketplaceService.searchScripts(
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
        offset: 0,
      );
      final baselineCount = baselineResult.total;
      print('Baseline script count: $baselineCount');

      List<String> uploadedScriptIds = [];

      try {
        // Upload 3 scripts sequentially
        for (int i = 1; i <= 3; i++) {
          final timestamp = DateTime.now().millisecondsSinceEpoch + i;
          final scriptTitle = 'Cumulative Test $i-$timestamp';
          
          print('Uploading script $i: $scriptTitle');
          final script = await marketplaceService.uploadScript(
            title: scriptTitle,
            description: 'Cumulative test script $i',
            category: 'Utilities',
            tags: ['cumulative', 'test', 'batch-$i'],
            luaSource: '-- Cumulative test script $i\nprint("Test $i")',
            authorName: 'Cumulative Test',
            version: '1.0.0',
            price: 0.0,
          );
          
          uploadedScriptIds.add(script.id);
          print('Script $i uploaded with ID: ${script.id}');

          // Brief pause for database consistency
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Get final count
        final finalResult = await marketplaceService.searchScripts(
          sortBy: 'createdAt',
          sortOrder: 'desc',
          limit: 100,
          offset: 0,
        );
        final finalCount = finalResult.total;
        final totalCountIncrease = finalCount - baselineCount;

        print('Final script count: $finalCount');
        print('Total count increase: $totalCountIncrease');

        // Verify count increased by exactly 3
        expect(totalCountIncrease, equals(3),
            reason: 'Count should increase by exactly 3 after uploading 3 scripts');

        // Verify all our scripts are in the results
        for (int i = 0; i < uploadedScriptIds.length; i++) {
          final scriptId = uploadedScriptIds[i];
          final foundScripts = finalResult.scripts
              .where((script) => script.id == scriptId)
              .toList();
          
          expect(foundScripts.length, equals(1),
              reason: 'Each uploaded script should appear in search results');
        }

        print('✅ E2E Test PASSED: Multiple uploads increase count cumulatively');

      } finally {
        // Clean up all uploaded scripts
        for (final scriptId in uploadedScriptIds) {
          try {
            await marketplaceService.deleteScript(scriptId);
            print('Cleaned up script: $scriptId');
          } catch (e) {
            print('Failed to clean up script $scriptId: $e');
          }
        }
      }
    });

    test('E2E: Script count consistency across different search methods', () async {
      print('\n=== E2E Test: Count Consistency Across Search Methods ===');

      // Get counts from different search methods
      print('Getting counts from different search methods...');

      // Method 1: General search
      final generalSearch = await marketplaceService.searchScripts(
        limit: 100,
        offset: 0,
      );
      final generalCount = generalSearch.total;

      // Method 2: Search by category (Development)
      final devSearch = await marketplaceService.searchScripts(
        category: 'Development',
        limit: 100,
        offset: 0,
      );
      final devCount = devSearch.total;

      // Method 3: Featured scripts
      final featuredScripts = await marketplaceService.getFeaturedScripts(limit: 100);
      final featuredCount = featuredScripts.length;

      // Method 4: Trending scripts
      final trendingScripts = await marketplaceService.getTrendingScripts(limit: 100);
      final trendingCount = trendingScripts.length;

      // Method 5: Marketplace stats
      final stats = await marketplaceService.getMarketplaceStats();
      final statsCount = stats.totalScripts;

      print('Count comparison:');
      print('  General search: $generalCount');
      print('  Development category: $devCount');
      print('  Featured scripts: $featuredCount');
      print('  Trending scripts: $trendingCount');
      print('  Marketplace stats: $statsCount');

      // Upload a test script to Development category
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testScriptTitle = 'Consistency Test $timestamp';
      
      print('Uploading consistency test script...');
      final uploadedScript = await marketplaceService.uploadScript(
        title: testScriptTitle,
        description: 'Test script for count consistency verification',
        category: 'Development',
        tags: ['consistency', 'test'],
        luaSource: '-- Consistency test script\nprint("Consistency test")',
        authorName: 'Consistency Test',
        version: '1.0.0',
        price: 0.0,
      );

      // Brief pause for database consistency
      await Future.delayed(const Duration(milliseconds: 500));

      // Get counts after upload
      final afterGeneralSearch = await marketplaceService.searchScripts(
        limit: 100,
        offset: 0,
      );
      final afterGeneralCount = afterGeneralSearch.total;

      final afterDevSearch = await marketplaceService.searchScripts(
        category: 'Development',
        limit: 100,
        offset: 0,
      );
      final afterDevCount = afterDevSearch.total;

      final afterStats = await marketplaceService.getMarketplaceStats();
      final afterStatsCount = afterStats.totalScripts;

      print('Count comparison after upload:');
      print('  General search: $afterGeneralCount (increase: ${afterGeneralCount - generalCount})');
      print('  Development category: $afterDevCount (increase: ${afterDevCount - devCount})');
      print('  Marketplace stats: $afterStatsCount (increase: ${afterStatsCount - statsCount})');

      // Verify consistency
      expect(afterGeneralCount - generalCount, equals(1),
          reason: 'General search count should increase by 1');
      expect(afterDevCount - devCount, equals(1),
          reason: 'Development category count should increase by 1');
      expect(afterStatsCount - statsCount, equals(1),
          reason: 'Marketplace stats count should increase by 1');

      // Clean up
      try {
        await marketplaceService.deleteScript(uploadedScript.id);
        print('Cleaned up consistency test script: ${uploadedScript.id}');
      } catch (e) {
        print('Failed to clean up consistency test script: $e');
      }

      print('✅ E2E Test PASSED: Count consistency verified across search methods');
    });
  });
}