import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:icp_autorun/config/app_config.dart';

/// Test configuration for the externally managed API service.
/// The API is provided by the local container + Cloudflare tunnel pipeline
/// started via `just api-up`, so the test harness must fail fast when the
/// service is missing.
class ApiServiceManager {
  static bool _isConfigured = false;
  static String? _cachedEndpoint;

  /// Get target endpoint URL from MARKETPLACE_API_PORT environment variable
  static String get endpoint {
    if (_cachedEndpoint != null) return _cachedEndpoint!;

    final port = Platform.environment['MARKETPLACE_API_PORT'];
    if (port == null || port.isEmpty) {
      throw Exception(
        'MARKETPLACE_API_PORT environment variable not set. '
        'Please start the API server with: just api-up'
      );
    }

    _cachedEndpoint = 'http://127.0.0.1:$port';
    return _cachedEndpoint!;
  }

  /// Get API endpoint URL (alias for endpoint)
  static String get endpointUrl => endpoint;

  /// Get API endpoint URL (static method)
  static String get apiEndpoint => endpointUrl;

  /// Configure test environment (static method)
  /// This should be called once before tests run
  static Future<void> initialize() async {
    if (_isConfigured) {
      return;
    }

    debugPrint('=== Test Environment Configuration ===');
    debugPrint('Assuming API server is running externally');
    debugPrint('Target endpoint: $endpoint');

    // Set the test endpoint in AppConfig so tests use the correct port
    AppConfig.setTestEndpoint(endpoint);

    // Always verify service is running for e2e tests - NO FALLBACKS
    await _verifyServiceRunning();

    _isConfigured = true;
    debugPrint('✅ Test environment configured successfully');
  }

  /// Cleanup - no-op since the API server is managed externally
  static Future<void> cleanup() async {
    debugPrint('=== Test Environment Cleanup ===');
    debugPrint('API server management handled externally');
    _isConfigured = false;
    _cachedEndpoint = null;
  }

  /// Verify that the service is actually running and accessible
  static Future<void> _verifyServiceRunning() async {
    debugPrint('Verifying API server is accessible...');

    final maxAttempts = 10;
    for (int i = 0; i < maxAttempts; i++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse('$endpoint/api/v1/health'));
        final response = await request.close().timeout(Duration(seconds: 5));

        if (response.statusCode == 200) {
          debugPrint('✅ API server is accessible at $endpoint');
          client.close();
          return;
        }
        client.close();
      } catch (e) {
        if (i == maxAttempts - 1) {
          throw Exception('API server is not accessible at $endpoint. Please start it with: just api-up');
        }
        debugPrint('Attempt ${i + 1}/$maxAttempts failed, retrying... ($e)');
        await Future.delayed(Duration(seconds: 2));
      }
    }
  }

  /// Check if service is configured
  static bool get isConfigured => _isConfigured;
}
