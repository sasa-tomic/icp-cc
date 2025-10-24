import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _marketplaceApiUrl = String.fromEnvironment(
    'MARKETPLACE_API_URL',
    defaultValue: 'https://fra.cloud.appwrite.io/v1',
  );

  static String get marketplaceApiUrl => _marketplaceApiUrl;

  static bool get isLocalDevelopment {
    return _marketplaceApiUrl.contains('localhost') || _marketplaceApiUrl.contains('127.0.0.1');
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

  // Debug method to print current configuration
  static void debugPrintConfig() {
    if (kDebugMode) {
      debugPrint('=== App Configuration ===');
      debugPrint('Marketplace API URL: $marketplaceApiUrl');
      debugPrint('Environment: $environmentName');
      debugPrint('Is Local Development: $isLocalDevelopment');
      debugPrint('==========================');
    }
  }
}