import 'dart:convert';

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
    bool failSilently = false, // Changed default to false for e2e tests
  }) {
    return MiniflareScriptRepository(
      baseUrl: baseUrl ?? defaultBaseUrl,
      client: failSilently ? _SilentFailHttpClient() : http.Client(),
    );
  }

  /// Setup test environment with Miniflare checks
  static Future<void> setupMiniflareTestEnvironment({
    String? baseUrl,
    bool requireServer = false,
  }) async {
    final isRunning = await isMiniflareRunning(baseUrl: baseUrl);
    
    if (!isRunning && requireServer) {
      throw Exception(
        'Miniflare server is not running at ${baseUrl ?? defaultBaseUrl}. '
        'Start it with: npm run dev in the cloudflare-api directory',
      );
    }
    
    if (!isRunning) {
      debugPrint('Warning: Miniflare server not available. Tests will run in offline mode.');
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

/// HTTP client that fails silently for network errors
/// Used in tests to avoid test failures when Miniflare is not available
class _SilentFailHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _inner.send(request);
    } catch (e) {
      // Return a mock successful response with empty data for tests
      final responseBody = '{"success": true, "data": {"scripts": []}}';
      return http.StreamedResponse(
        Stream.value(utf8.encode(responseBody)),
        200,
        request: request,
        headers: {
          'content-type': 'application/json',
          'content-length': responseBody.length.toString(),
        },
      );
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
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