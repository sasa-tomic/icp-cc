import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/wrangler_manager.dart';
import '../test_helpers/http_test_helper.dart';

void main() {
  group('Upload Fix API Tests', () {
    setUpAll(() async {
      await WranglerManager.initialize();
    });

    tearDownAll(() async {
      await WranglerManager.cleanup();
    });

    test('API: Upload with non-empty lua_source should succeed', () async {
      final testTitle = 'Direct API Test ${DateTime.now().millisecondsSinceEpoch}';
      
      print('Testing direct API upload...');
      
      // First test: simple GET request to verify connectivity using HttpTestHelper
      try {
        print('🔍 About to call HttpTestHelper.get()...');
        print('🔍 Current time: ${DateTime.now()}');
        print('🔍 Endpoint: http://localhost:8787/api/v1/marketplace-stats');
        
        final connectivityResult = await HttpTestHelper.get(
          'http://localhost:8787/api/v1/marketplace-stats',
          headers: {
            'Accept': '*/*',
            'User-Agent': 'flutter-test',
          },
          config: const HttpRequestConfig(
            timeout: Duration(seconds: 5),
            maxRetries: 3,
            userMessage: 'Failed to verify connectivity to marketplace stats endpoint',
          ),
        );
        
        print('🔍 HttpTestHelper.get() completed');
        print('🔍 Result success: ${connectivityResult.isSuccess}');
        print('🔍 Result status: ${connectivityResult.response.statusCode}');
        
        expect(connectivityResult.isSuccess, isTrue, reason: 'GET request should work with HttpTestHelper');
        print('✅ GET request successful with HttpTestHelper');
        print('Response status: ${connectivityResult.response.statusCode}');
        print('Response body length: ${connectivityResult.response.body.length}');
      } catch (e) {
        print('❌ GET request failed with HttpTestHelper: $e');
        rethrow;
      }
      
      // Test direct API call using our robust HTTP helper
      try {
        final uploadResult = await HttpTestHelper.post(
          'http://localhost:8787/api/v1/scripts',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'title': testTitle,
            'description': 'Direct API test script for upload verification',
            'category': 'Development',
            'tags': ['test', 'api', 'upload'],
            'lua_source': '''-- Direct API Test Script
function init(arg)
  return {
    message = "Hello from direct API upload!"
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

-- Test function
function greet(name)
    return "Hello, " .. name .. "!"
end
''',
            'author_name': 'API Test Runner',
            'canister_ids': [],
            'screenshots': [],
            'version': '1.0.0',
            'price': 0.0,
            'is_public': true,
          }),
          config: const HttpRequestConfig(
            timeout: Duration(seconds: 10),
            maxRetries: 3,
            userMessage: 'Failed to upload script via direct API call',
          ),
        );
        
        expect(uploadResult.isSuccess, isTrue, reason: 'POST request should work with HttpTestHelper');
        print('✅ POST request successful with HttpTestHelper');
        print('Response status: ${uploadResult.response.statusCode}');
        print('Response body: ${uploadResult.response.body}');
        
        // Parse response to verify upload was successful
        final responseData = jsonDecode(uploadResult.response.body);
        expect(responseData['success'], isTrue, reason: 'API should return success');
        expect(responseData['data']['id'], isNotNull, reason: 'API should return script ID');
        expect(responseData['data']['title'], equals(testTitle), reason: 'API should return correct title');
        
        print('✅ Script uploaded successfully via API!');
        print('Script ID: ${responseData['data']['id']}');
        print('Script Title: ${responseData['data']['title']}');
        
      } catch (e) {
        print('❌ API upload failed: $e');
        rethrow;
      }
    });
  });
}