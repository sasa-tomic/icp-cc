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

  // A-W6-9: `isLocalDevelopment` must classify by the parsed URI host against
  // an explicit dev-host set, NOT by substring. The old `.contains('.local')`
  // heuristic mis-classified prod hosts like `api.localtest.com` as dev.
  group('AppConfig.isLocalDevelopment dev-host classification', () {
    // setTestEndpoint is a no-op on Web (_isTestMode is false there), so the
    // classification can't be driven deterministically under `flutter test -p
    // chrome`. These cases are native-only.
    void classify(String endpoint, bool expectedLocal) {
      if (kIsWeb) return;
      AppConfig.setTestEndpoint(endpoint);
      expect(
        AppConfig.isLocalDevelopment,
        expectedLocal,
        reason: 'endpoint=$endpoint',
      );
      expect(
        AppConfig.isProduction,
        !expectedLocal,
        reason: 'isProduction must be the complement, endpoint=$endpoint',
      );
    }

    test('prod host containing ".local" substring is NOT local dev', () {
      // RED on old code: '.contains('.local')' wrongly returns true here.
      classify('https://api.localtest.com', false);
    });

    test('localtunnel host is NOT local dev', () {
      classify('https://myapp.localtunnel.me', false);
    });

    test('plain prod hostname is NOT local dev', () {
      classify('https://icp-mp.kalaj.org', false);
    });

    test('127.0.0.1 IS local dev', () {
      classify('http://127.0.0.1:8080', true);
    });

    test('localhost IS local dev', () {
      classify('http://localhost:8080', true);
    });

    test('dev host with port in a path-containing URL still classified by host', () {
      classify('http://127.0.0.1:4943/api/v2', true);
    });
  });
}
