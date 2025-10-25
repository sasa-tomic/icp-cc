import 'dart:io';
import 'package:icp_autorun/config/app_config.dart';

/// Test configuration for external Cloudflare Workers service
/// This assumes wrangler is managed externally (e.g., via justfile)
class WranglerManager {
  static const int _defaultPort = 8787;
  static bool _isConfigured = false;

  /// Get target endpoint URL
  static String get endpoint => 'http://localhost:$_defaultPort';
  
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
    
    print('=== Test Environment Configuration ===');
    print('Assuming Cloudflare Workers is running externally');
    print('Target endpoint: $endpoint');
    
    // Set the test endpoint in AppConfig so tests use the correct port
    AppConfig.setTestEndpoint(endpoint);
    
    // Verify the service is actually running
    await _verifyServiceRunning();
    
    _isConfigured = true;
    print('✅ Test environment configured successfully');
  }

  /// Cleanup - no-op since wrangler is managed externally
  static Future<void> cleanup() async {
    print('=== Test Environment Cleanup ===');
    print('Cloudflare Workers management handled externally');
    _isConfigured = false;
  }

  /// Verify that the service is actually running and accessible
  static Future<void> _verifyServiceRunning() async {
    print('Verifying Cloudflare Workers is accessible...');
    
    final maxAttempts = 10;
    for (int i = 0; i < maxAttempts; i++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse('$endpoint/api/v1/health'));
        final response = await request.close().timeout(Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          print('✅ Cloudflare Workers is accessible at $endpoint');
          client.close();
          return;
        }
        client.close();
      } catch (e) {
        if (i == maxAttempts - 1) {
          throw Exception('Cloudflare Workers is not accessible at $endpoint. Please start it with: just cloudflare-test-up');
        }
        print('Attempt ${i + 1}/$maxAttempts failed, retrying... ($e)');
        await Future.delayed(Duration(seconds: 2));
      }
    }
  }

  /// Check if service is configured
  static bool get isConfigured => _isConfigured;
}