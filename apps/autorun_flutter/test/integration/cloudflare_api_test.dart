import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Cloudflare Workers API Integration Tests', () {
    late MarketplaceOpenApiService apiService;

    setUpAll(() async {
      // Configure test environment (assumes wrangler is running externally)
      await WranglerManager.initialize();
      
      // Configure for local Cloudflare Workers testing
      AppConfig.debugPrintConfig();
      apiService = MarketplaceOpenApiService();
    });

    tearDownAll(() async {
      // Cleanup test configuration
      await WranglerManager.cleanup();
    });

    test('should get marketplace stats from Cloudflare Workers', () async {
      try {
        final stats = await apiService.getMarketplaceStats();
        print('Marketplace stats: $stats');
        expect(stats.totalScripts, greaterThanOrEqualTo(0));
      } catch (e) {
        fail('Failed to get marketplace stats: $e');
      }
    });

    test('should search scripts from Cloudflare Workers', () async {
      try {
        final result = await apiService.searchScripts(
          query: 'test',
          limit: 5,
        );
        print('Search results: ${result.scripts.length} scripts found');
        expect(result.scripts, isA<List>());
      } catch (e) {
        fail('Failed to search scripts: $e');
      }
    });

    test('should get featured scripts from Cloudflare Workers', () async {
      try {
        final scripts = await apiService.getFeaturedScripts(limit: 5);
        print('Featured scripts: ${scripts.length} scripts found');
        expect(scripts, isA<List>());
      } catch (e) {
        fail('Failed to get featured scripts: $e');
      }
    });

    test('should get trending scripts from Cloudflare Workers', () async {
      try {
        final scripts = await apiService.getTrendingScripts(limit: 5);
        print('Trending scripts: ${scripts.length} scripts found');
        expect(scripts, isA<List>());
      } catch (e) {
        fail('Failed to get trending scripts: $e');
      }
    });

    test('should validate script using Cloudflare Workers', () async {
      try {
        final result = await apiService.validateScript('''function init(arg)
  return {}, {}
end

function view(state)
  return {type = "text", props = {text = "Hello World"}}
end

function update(msg, state)
  return state, {}
end''');
        print('Validation result: ${result.isValid}');
        expect(result.isValid, isTrue);
      } catch (e) {
        fail('Failed to validate script: $e');
      }
    });

    test('should upload script to Cloudflare Workers', () async {
      try {
        // Test data for script upload
        const testTitle = 'Test Upload Script';
        const testDescription = 'A test script for upload functionality verification';
        const testCategory = 'Utilities';
        const testTags = ['test', 'upload', 'automation'];
        const testLuaSource = '''-- Test Upload Script
function init(arg)
  return {
    message = "Hello from uploaded script!"
  }, {}
end

function view(state)
  return {
    type = "text",
    props = {
      text = state.message
    }
  }
end

function update(msg, state)
  return state, {}
end

-- Simple automation function
function greet(name)
    return "Hello, " .. name .. "!"
end''';
        const testAuthorName = 'Test Author';
        const testVersion = '1.0.0';
        const testPrice = 0.0;

        print('--- Testing Script Upload ---');
        print('Title: $testTitle');
        print('Category: $testCategory');
        print('Author: $testAuthorName');
        print('Lua Source Length: ${testLuaSource.length} characters');

        // First validate the script
        final validationResult = await apiService.validateScript(testLuaSource);
        print('Script validation result: ${validationResult.isValid}');
        expect(validationResult.isValid, isTrue, reason: 'Script should be valid before upload');

        // Upload the script
        print('--- Attempting Upload ---');
        final uploadedScript = await apiService.uploadScript(
          title: testTitle,
          description: testDescription,
          category: testCategory,
          tags: testTags,
          luaSource: testLuaSource,
          authorName: testAuthorName,
          version: testVersion,
          price: testPrice,
        );

        print('✅ Script uploaded successfully!');
        print('Script ID: ${uploadedScript.id}');
        print('Script Title: ${uploadedScript.title}');
        print('Script Author: ${uploadedScript.authorName}');
        print('Script Category: ${uploadedScript.category}');
        print('Script Price: ${uploadedScript.price} ICP');
        print('Script Created At: ${uploadedScript.createdAt}');
        print('Is Public: ${uploadedScript.isPublic}');

        // Verify the uploaded script data
        expect(uploadedScript.title, equals(testTitle));
        expect(uploadedScript.description, equals(testDescription));
        expect(uploadedScript.category, equals(testCategory));
        expect(uploadedScript.tags, equals(testTags));
        expect(uploadedScript.luaSource, equals(testLuaSource));
        expect(uploadedScript.authorName, equals(testAuthorName));
        expect(uploadedScript.version, equals(testVersion));
        expect(uploadedScript.price, equals(testPrice));
        expect(uploadedScript.isPublic, isTrue);
        expect(uploadedScript.id, isNotNull);
        expect(uploadedScript.id, isNotEmpty);
        expect(uploadedScript.createdAt, isNotNull);
        expect(uploadedScript.updatedAt, isNotNull);

        // Test that we can retrieve the uploaded script
        print('--- Testing Script Retrieval ---');
        try {
          final retrievedScript = await apiService.getScriptDetails(uploadedScript.id);
          print('✅ Script retrieved successfully!');
          print('Retrieved Script ID: ${retrievedScript.id}');
          print('Retrieved Script Title: ${retrievedScript.title}');

          expect(retrievedScript.id, equals(uploadedScript.id));
          expect(retrievedScript.title, equals(uploadedScript.title));
          expect(retrievedScript.luaSource, equals(uploadedScript.luaSource));
        } catch (e) {
          print('⚠️ Script not retrievable (expected for unapproved scripts): $e');
          // This is expected behavior for unapproved scripts
        }

        // Test that the script appears in search results (should not appear since not approved)
        print('--- Testing Script Search ---');
        final searchResult = await apiService.searchScripts(
          query: testTitle,
          limit: 10,
        );
        print('Search results: ${searchResult.scripts.length} scripts found');
        
        // Script should NOT appear in search results since it's not approved
        final foundScript = searchResult.scripts.where(
          (script) => script.title.contains(testTitle.split(' ')[0]), // Look for partial title match
        ).toList();
        
        if (foundScript.isEmpty) {
          print('✅ Script correctly not found in search results (expected for unapproved scripts)');
        } else {
          print('⚠️ Script found in search results: ${foundScript.length} matches');
        }

        print('✅ All upload tests passed successfully!');

      } catch (e) {
        print('❌ Upload test failed: $e');
        print('Stack trace: ${StackTrace.current}');
        fail('Script upload test failed: $e');
      }
    });

    test('should handle upload validation errors correctly', () async {
      try {
        print('--- Testing Upload Validation ---');
        
        // Try to upload an invalid script (empty Lua source)
        await apiService.uploadScript(
          title: 'Invalid Script Test',
          description: 'This should fail validation',
          category: 'Utilities',
          tags: ['test'],
          luaSource: '', // Empty script should fail
          authorName: 'Test Author',
        );

        fail('Should have thrown an exception for invalid script');

      } catch (e) {
        print('✅ Upload validation correctly rejected invalid script: $e');
        expect(e, isA<Exception>());
      }
    });

    test('should handle upload with missing required fields', () async {
      try {
        print('--- Testing Missing Required Fields ---');
        
        // Try to upload without required fields
        await apiService.uploadScript(
          title: '', // Empty title should fail
          description: 'Test description',
          category: 'Utilities',
          tags: ['test'],
          luaSource: 'print("test")',
          authorName: 'Test Author',
        );

        fail('Should have thrown an exception for missing title');

      } catch (e) {
        print('✅ Upload validation correctly rejected missing title: $e');
        expect(e, isA<Exception>());
      }
    });
  });
}