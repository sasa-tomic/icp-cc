import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _appwriteEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://fra.cloud.appwrite.io/v1',
  );

  static String get appwriteEndpoint => _appwriteEndpoint;

  static bool get isLocalDevelopment {
    return _appwriteEndpoint.contains('localhost') || _appwriteEndpoint.contains('127.0.0.1');
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
      debugPrint('Appwrite Endpoint: $appwriteEndpoint');
      debugPrint('Environment: $environmentName');
      debugPrint('Is Local Development: $isLocalDevelopment');
      debugPrint('==========================');
    }
  }
}