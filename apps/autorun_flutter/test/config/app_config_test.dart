import 'dart:io' show Platform;

import 'package:icp_autorun/config/app_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.apiEndpoint', () {
    test('returns a non-empty http(s) URL in every runtime', () {
      // Must never throw — on Web, Platform.environment is guarded by kIsWeb
      // (TD/regression guard for the blank-screen blocker).
      final endpoint = AppConfig.apiEndpoint;
      expect(endpoint, isNotEmpty);
      expect(endpoint.startsWith('http'), isTrue);
    });

    test('honors MARKETPLACE_API_PORT in debug mode on native', () {
      // The kIsWeb guard must NOT break the native devex path.
      final port = Platform.environment['MARKETPLACE_API_PORT'];
      if (kDebugMode && !kIsWeb && port != null && port.isNotEmpty) {
        expect(AppConfig.apiEndpoint, 'http://127.0.0.1:$port');
      }
    });
  });

  group('AppConfig environment helpers', () {
    test('isLocalDevelopment and isProduction are mutually exclusive', () {
      expect(AppConfig.isLocalDevelopment == AppConfig.isProduction, isFalse);
    });

    test('environmentName is non-empty', () {
      expect(AppConfig.environmentName, isNotEmpty);
    });

    test('userAgent is a single canonical constant', () {
      expect(AppConfig.userAgent, 'ICP-Autorun-Flutter/1.0');
    });
  });

  group('AppConfig test-mode override', () {
    test('setTestEndpoint is accepted under the flutter test harness', () {
      // _isTestMode is true when FLUTTER_TEST is set (flutter test sets it).
      // On Web, _isTestMode returns false (Platform.environment throws there).
      AppConfig.setTestEndpoint('http://test-override.local');
      // The override takes effect only in test mode — which this is.
      if (!kIsWeb) {
        expect(AppConfig.apiEndpoint, 'http://test-override.local');
      }
    });
  });
}
