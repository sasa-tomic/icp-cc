import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _cloudflareEndpoint = String.fromEnvironment(
    'CLOUDFLARE_ENDPOINT',
    defaultValue: 'http://localhost:8787',
  );

  static String get apiEndpoint => _cloudflareEndpoint;
  static String get cloudflareEndpoint => _cloudflareEndpoint;

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