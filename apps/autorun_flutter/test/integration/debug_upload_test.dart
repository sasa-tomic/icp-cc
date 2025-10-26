import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/config/app_config.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Debug Upload Test', () {
    late MarketplaceOpenApiService marketplaceService;

    setUpAll(() async {
      await WranglerManager.initialize();
      marketplaceService = MarketplaceOpenApiService();
    });

    test('Debug endpoint configuration', () {
      print('=== Debug Info ===');
      print('AppConfig.apiEndpoint: ${AppConfig.apiEndpoint}');
      print('AppConfig.cloudflareEndpoint: ${AppConfig.cloudflareEndpoint}');
      print('AppConfig.isLocalDevelopment: ${AppConfig.isLocalDevelopment}');
    });

    test('Debug simple upload', () async {
      print('=== Testing Simple Upload ===');
      
      try {
        final result = await marketplaceService.uploadScript(
          title: 'Debug Test Script',
          description: 'Debug test',
          category: 'Development',
          tags: ['debug'],
          luaSource: 'print("debug test")',
          authorName: 'Debug Test',
        );
        print('✅ Upload successful: ${result.id}');
      } catch (e) {
        print('❌ Upload failed: $e');
        print('Exception type: ${e.runtimeType}');
      }
    });

    test('Debug problematic upload like upload_fix_verification_test', () async {
      print('=== Testing Problematic Upload ===');
      
      try {
        final testTitle = 'Fix Verification Test ${DateTime.now().millisecondsSinceEpoch}';
        final result = await marketplaceService.uploadScript(
          title: testTitle,
          description: 'Direct API test for upload fix verification',
          category: 'Development',
          tags: ['fix-test', 'api-direct'],
          luaSource: '''-- Direct API Test Script
function init(arg)
  return {
    message = "Hello from direct API test!"
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
end''',
          authorName: 'Direct API Test Runner',
          version: '1.0.0',
          price: 0.0,
        );
        print('✅ Upload successful: ${result.id}');
      } catch (e) {
        print('❌ Upload failed: $e');
        print('Exception type: ${e.runtimeType}');
      }
    });

    test('Debug upload without version to test difference', () async {
      print('=== Testing Upload Without Version ===');
      
      try {
        final testTitle = 'No Version Test ${DateTime.now().millisecondsSinceEpoch}';
        final result = await marketplaceService.uploadScript(
          title: testTitle,
          description: 'Test without version parameter',
          category: 'Development',
          tags: ['no-version'],
          luaSource: 'print("test without version")',
          authorName: 'No Version Test',
          price: 0.0,
        );
        print('✅ Upload successful: ${result.id}');
      } catch (e) {
        print('❌ Upload failed: $e');
        print('Exception type: ${e.runtimeType}');
      }
    });
  });
}