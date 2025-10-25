import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _appwriteEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://icp-autorun.appwrite.network',
  );

  static const String _cloudflareEndpoint = String.fromEnvironment(
    'CLOUDFLARE_ENDPOINT',
    defaultValue: 'http://localhost:8787',
  );

  // Use Cloudflare by default, fallback to Appwrite for backward compatibility
  static bool get useCloudflare => 
      String.fromEnvironment('USE_CLOUDFLARE', defaultValue: 'true') == 'true';

  static String get apiEndpoint => useCloudflare ? _cloudflareEndpoint : _appwriteEndpoint;
  static String get appwriteEndpoint => _appwriteEndpoint;
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
    return useCloudflare ? 'Cloudflare Workers' : 'Appwrite';
  }

  // Debug method to print current configuration
  static void debugPrintConfig() {
    if (kDebugMode) {
      debugPrint('=== App Configuration ===');
      debugPrint('API Provider: $apiProvider');
      debugPrint('API Endpoint: $apiEndpoint');
      debugPrint('Cloudflare Endpoint: $cloudflareEndpoint');
      debugPrint('Appwrite Endpoint: $appwriteEndpoint');
      debugPrint('Environment: $environmentName');
      debugPrint('Is Local Development: $isLocalDevelopment');
      debugPrint('==========================');
    }
  }
}