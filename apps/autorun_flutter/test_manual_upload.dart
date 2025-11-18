import 'package:flutter/foundation.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

void main() async {
  final marketplaceService = MarketplaceOpenApiService();
  
  debugPrint('Testing upload with fix...');

  try {
    final uploadedScript = await marketplaceService.uploadScript(
      slug: 'manual-test-script',
      title: 'Manual Test Script',
      description: 'Manual test to verify upload fix works',
      category: 'Development',
      tags: ['manual-test', 'fix-verification'],
      luaSource: '''-- Manual Test Script
function init(arg)
  return {
    message = "Hello from manual test!"
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
      authorName: 'Manual Test Runner',
      version: '1.0.0',
      price: 0.0,
    );

    debugPrint('✅ Upload successful!');
    debugPrint('Script ID: ${uploadedScript.id}');
    debugPrint('Title: ${uploadedScript.title}');
    debugPrint('Category: ${uploadedScript.category}');

    // Clean up
    await marketplaceService.deleteScript(uploadedScript.id);
    debugPrint('✅ Cleanup completed');

  } catch (e) {
    debugPrint('❌ Upload failed: $e');
  }
}