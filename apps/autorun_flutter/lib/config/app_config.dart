import 'package:flutter/foundation.dart';
import 'dart:io';

class AppConfig {
  static const String _apiEndpoint = String.fromEnvironment(
    'PUBLIC_API_ENDPOINT',
    defaultValue: 'https://icp-mp.kalaj.org',
  );

  static const String _marketplaceWebUrl = String.fromEnvironment(
    'MARKETPLACE_WEB_URL',
    defaultValue: 'https://icp-mp.kalaj.org',
  );

  static String get apiEndpoint {
    // Check if we're in test mode and an API service override is available
    if (_isTestMode && _testServiceEndpoint != null) {
      return _testServiceEndpoint!;
    }
    // Devex: honor `MARKETPLACE_API_PORT` (exported by `just api-dev-up`) at
    // runtime in debug, so a local backend works without a `--dart-define`
    // rebuild. The name implies runtime config — make it so.
    if (kDebugMode) {
      final port = Platform.environment['MARKETPLACE_API_PORT'];
      if (port != null && port.isNotEmpty) {
        return 'http://127.0.0.1:$port';
      }
    }
    return _apiEndpoint;
  }
  
  static String get cloudflareEndpoint => apiEndpoint;

  static String get marketplaceWebUrl => _marketplaceWebUrl;

  // Check if we're in test mode by looking for test environment indicators
  static bool get _isTestMode {
    return Platform.environment.containsKey('FLUTTER_TEST') ||
           kDebugMode && Platform.script.path.contains('test');
  }
  
  // This will be set by ApiServiceManager during tests
  static String? _testServiceEndpoint;
  
  static void setTestEndpoint(String endpoint) {
    if (_isTestMode) {
      _testServiceEndpoint = endpoint;
    }
  }

  static bool get isLocalDevelopment {
    return apiEndpoint.contains('localhost') || 
           apiEndpoint.contains('127.0.0.1') ||
           apiEndpoint.contains('.local');
  }

  static bool get isProduction {
    return !isLocalDevelopment;
  }

  static String get environmentName {
    if (isLocalDevelopment) {
      return 'Local Development';
    } else {
      return 'Production';
    }
  }

  static String get apiProvider {
    return 'Cloudflare Workers';
  }

  /// Single source for the `User-Agent` header sent on outbound HTTP calls
  /// (candid registry, marketplace API, …). TD-6 sweeps every inline literal
  /// to this name.
  static const String userAgent = 'ICP-Autorun-Flutter/1.0';

  // Debug method to print current configuration
  static void debugPrintConfig() {
    if (kDebugMode) {
      debugPrint('=== App Configuration ===');
      debugPrint('API Provider: $apiProvider');
      debugPrint('API Endpoint: $apiEndpoint');
      debugPrint('Cloudflare Endpoint: $cloudflareEndpoint');
      debugPrint('Environment: $environmentName');
      debugPrint('Is Local Development: $isLocalDevelopment');
      debugPrint('==========================');
    }
  }
}
