import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/models/script_record.dart';
import 'miniflare_script_repository.dart';

/// Test helper utilities for Miniflare integration testing
class MiniflareTestHelper {
  static const String defaultBaseUrl = 'http://localhost:8787';
  
  /// Check if Miniflare server is running and available
  static Future<bool> isMiniflareRunning({String? baseUrl}) async {
    try {
      final response = await http.get(
        Uri.parse('${baseUrl ?? defaultBaseUrl}/api/v1/health'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Wait for Miniflare server to be available (with timeout)
  static Future<bool> waitForMiniflare({
    String? baseUrl,
    Duration timeout = const Duration(seconds: 30),
    Duration checkInterval = const Duration(seconds: 1),
  }) async {
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      if (await isMiniflareRunning(baseUrl: baseUrl)) {
        return true;
      }
      await Future.delayed(checkInterval);
    }
    
    return false;
  }

  /// Create a test repository with proper error handling for tests
  static MiniflareScriptRepository createTestRepository({
    String? baseUrl,
  }) {
    return MiniflareScriptRepository(
      baseUrl: baseUrl ?? defaultBaseUrl,
      client: http.Client(), // Always use real HTTP client for e2e tests
    );
  }

  /// Setup test environment with Miniflare checks
  static Future<void> setupMiniflareTestEnvironment({
    String? baseUrl,
    bool requireServer = true, // Changed default to true for e2e tests
  }) async {
    final isRunning = await isMiniflareRunning(baseUrl: baseUrl);

    if (!isRunning) {
      throw Exception(
        'Miniflare server is not running at ${baseUrl ?? defaultBaseUrl}. '
        'Start it with: npm run dev in the cloudflare-api directory. '
        'E2E tests MUST NOT run in offline mode or use mocks/fallbacks.',
      );
    }
  }

  /// Clean up test data after tests
  static Future<void> cleanupTestData({
    String? baseUrl,
    List<String>? scriptIds,
  }) async {
    if (scriptIds == null || scriptIds.isEmpty) return;
    
    try {
      final repository = MiniflareScriptRepository(baseUrl: baseUrl);
      
      for (final scriptId in scriptIds) {
        await repository.deleteScript(scriptId);
      }
      
      repository.dispose();
    } catch (e) {
      // Silently ignore cleanup errors
      debugPrint('Warning: Failed to cleanup test data: $e');
    }
  }
}

/// Test extension methods for MiniflareScriptRepository
extension MiniflareScriptRepositoryTestExtensions on MiniflareScriptRepository {
  /// Create test script data for testing
  static ScriptRecord createTestScript({
    String? id,
    String? title,
    String? luaSource,
    Map<String, dynamic>? metadata,
  }) {
    return ScriptRecord(
      id: id ?? 'test-script-${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Test Script',
      luaSource: luaSource ?? '''function init(arg)
  return { message = "Hello from test script!" }, {}
end

function view(state)
  return { type = "text", text = state.message }
end

function update(msg, state)
  if msg.type == "test" then
    state.message = "Updated!"
  end
  return state, {}
end''',
      metadata: metadata ?? {
        'description': 'Test script for unit testing',
        'category': 'Testing',
        'tags': ['test', 'unit'],
        'authorName': 'Test Author',
        'authorPublicKey': 'test-public-key-for-icp-compatibility',
        'authorPrincipal': '2vxsx-fae',
        'version': '1.0.0',
        'price': 0.0,
        'isPublic': false,
      },
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Create multiple test scripts for batch testing
  static List<ScriptRecord> createTestScripts({int count = 3}) {
    return List.generate(count, (index) => createTestScript(
      id: 'test-script-$index',
      title: 'Test Script $index',
      metadata: {
        'description': 'Test script $index for batch testing',
        'category': index % 2 == 0 ? 'Testing' : 'Development',
        'tags': ['test', 'batch', 'script-$index'],
        'authorName': 'Batch Test Author',
        'authorPublicKey': 'test-public-key-for-icp-compatibility',
        'authorPrincipal': '2vxsx-fae',
        'version': '1.0.0',
        'price': index * 0.5,
        'isPublic': index % 2 == 0,
      },
    ));
  }

  /// Assert that a script exists in the repository
  Future<void> expectScriptExists(String scriptId) async {
    final script = await getScriptById(scriptId);
    expect(script, isNotNull, reason: 'Script $scriptId should exist');
    expect(script!.id, equals(scriptId));
  }

  /// Assert that a script does not exist in the repository
  Future<void> expectScriptNotExists(String scriptId) async {
    final script = await getScriptById(scriptId);
    expect(script, isNull, reason: 'Script $scriptId should not exist');
  }

  /// Count scripts matching a predicate
  Future<int> countScriptsWhere(bool Function(ScriptRecord) predicate) async {
    final scripts = await getAllScripts();
    return scripts.where(predicate).length;
  }
}