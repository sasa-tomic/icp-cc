import 'package:icp_autorun/services/marketplace_open_api_service.dart';

void main() async {
  final marketplaceService = MarketplaceOpenApiService();
  
  print('Testing upload with fix...');
  
  try {
    final uploadedScript = await marketplaceService.uploadScript(
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
    
    print('✅ Upload successful!');
    print('Script ID: ${uploadedScript.id}');
    print('Title: ${uploadedScript.title}');
    print('Category: ${uploadedScript.category}');
    
    // Clean up
    await marketplaceService.deleteScript(uploadedScript.id);
    print('✅ Cleanup completed');
    
  } catch (e) {
    print('❌ Upload failed: $e');
  }
}