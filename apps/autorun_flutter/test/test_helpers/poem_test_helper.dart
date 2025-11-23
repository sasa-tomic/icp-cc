import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/models/script_record.dart';
import 'poem_script_repository.dart';

/// Test helper utilities for API server integration testing
class PoemTestHelper {
  static String get defaultBaseUrl {
    final port = Platform.environment['MARKETPLACE_API_PORT'];
    if (port == null || port.isEmpty) {
      throw Exception(
        'MARKETPLACE_API_PORT environment variable not set. '
        'Please start the API server with: just api-up'
      );
    }
    return 'http://127.0.0.1:$port';
  }
  
  /// Check if Poem API server is running and available
  static Future<bool> isPoemApiRunning({String? baseUrl}) async {
    try {
      final response = await http.get(
        Uri.parse('${baseUrl ?? defaultBaseUrl}/'),
      ).timeout(const Duration(seconds: 10));

      // Any response (including 404) means the server is running
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  /// Wait for Poem API server to be available (with timeout)
  static Future<bool> waitForPoemApi({
    String? baseUrl,
    Duration timeout = const Duration(seconds: 30),
    Duration checkInterval = const Duration(seconds: 1),
  }) async {
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      if (await isPoemApiRunning(baseUrl: baseUrl)) {
        return true;
      }
      await Future.delayed(checkInterval);
    }
    
    return false;
  }

  /// Create a test repository with proper error handling for tests
  static PoemScriptRepository createTestRepository({
    String? baseUrl,
  }) {
    return PoemScriptRepository(
      baseUrl: baseUrl ?? defaultBaseUrl,
      client: http.Client(), // Always use real HTTP client for e2e tests
    );
  }

  /// Setup test environment with API server checks
  static Future<void> setupPoemTestEnvironment({
    String? baseUrl,
    bool requireServer = true, // Changed default to true for e2e tests
  }) async {
    final isRunning = await isPoemApiRunning(baseUrl: baseUrl);

    if (!isRunning) {
      throw Exception(
        'API server is not running at ${baseUrl ?? defaultBaseUrl}. '
        'Start it with: just api-up. '
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
      final repository = PoemScriptRepository(baseUrl: baseUrl);
      
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

/// Test extension methods for PoemScriptRepository
extension PoemScriptRepositoryTestExtensions on PoemScriptRepository {
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
        'isPublic': true,
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
