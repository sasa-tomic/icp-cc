import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

/// Coverage for the ICPay / paid-download surface of
/// [MarketplaceOpenApiService]:
/// - `getScriptDetails(id, accountId:)` appends `?account_id=` and parses the
///   entitlement `purchased` flag.
/// - `downloadPaidScriptBundle` returns the bundle on 200, throws
///   [PurchaseRequiredException] (with price) on 402, throws
///   [DownloadAuthException] on 401.
/// - `getIcpayConfig` returns the camelCase config on 200 and throws
///   [PaymentsNotConfiguredException] on 503.
void main() {
  late MarketplaceOpenApiService service;

  setUp(() {
    suppressDebugOutput = true;
    AppConfig.setTestEndpoint('https://mock.api');
    service = MarketplaceOpenApiService();
  });

  tearDown(() {
    suppressDebugOutput = false;
    service.resetHttpClient();
  });

  http.Response ok(String body) => http.Response(
        body,
        200,
        headers: {'Content-Type': 'application/json'},
      );

  group('getScriptDetails(accountId:)', () {
    test('appends ?account_id= when accountId is provided', () async {
      String? capturedUrl;
      final client = MockClient((request) async {
        capturedUrl = request.url.toString();
        return ok(jsonEncode({
          'success': true,
          'data': {
            'id': 'script-paid',
            'title': 'Paid',
            'description': 'd',
            'category': 'c',
            'bundle': 'src',
            'price': 9.99,
            'purchased': false,
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final script = await service.getScriptDetails(
        'script-paid',
        accountId: 'acct-123',
      );

      expect(capturedUrl,
          'https://mock.api/api/v1/scripts/script-paid?account_id=acct-123');
      expect(script.purchased, isFalse,
          reason: 'paid + not purchased must parse purchased:false');
      expect(script.bundle, 'src');
    });

    test('omits query string when accountId is null (legacy shape)', () async {
      String? capturedUrl;
      final client = MockClient((request) async {
        capturedUrl = request.url.toString();
        return ok(jsonEncode({
          'success': true,
          'data': {
            'id': 'script-free',
            'title': 'Free',
            'description': 'd',
            'category': 'c',
            'bundle': 'src',
            'price': 0.0,
            'purchased': true,
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final script = await service.getScriptDetails('script-free');

      expect(capturedUrl, 'https://mock.api/api/v1/scripts/script-free');
      expect(script.purchased, isTrue);
    });

    test('omits query string when accountId is empty', () async {
      String? capturedUrl;
      final client = MockClient((request) async {
        capturedUrl = request.url.toString();
        return ok(jsonEncode({
          'success': true,
          'data': {
            'id': 's',
            'title': 't',
            'bundle': 'b',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await service.getScriptDetails('s', accountId: '');
      expect(capturedUrl, 'https://mock.api/api/v1/scripts/s');
    });
  });

  group('downloadPaidScriptBundle', () {
    test('POSTs the signed body and returns the bundle on 200', () async {
      Map<String, dynamic>? capturedBody;
      String? capturedPath;
      final client = MockClient((request) async {
        capturedPath = request.url.toString();
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return ok(jsonEncode({
          'success': true,
          'data': {'bundle': 'the-paid-source', 'purchased': true},
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final bundle = await service.downloadPaidScriptBundle(
        'script-xyz',
        accountId: 'acct-1',
        publicKeyB64: 'pk-b64',
        signatureB64: 'sig-b64',
        timestamp: '2024-01-01T00:00:00.000Z',
        nonce: '11111111-1111-1111-1111-111111111111',
      );

      expect(bundle, 'the-paid-source');
      expect(capturedPath,
          'https://mock.api/api/v1/scripts/script-xyz/download');
      // Body MUST be exactly the 4-field snake_case shape the backend
      // DownloadRequest deserialiser expects — accountId is NOT in the body.
      expect(capturedBody, {
        'public_key': 'pk-b64',
        'signature': 'sig-b64',
        'timestamp': '2024-01-01T00:00:00.000Z',
        'nonce': '11111111-1111-1111-1111-111111111111',
      });
      expect(capturedBody!.containsKey('account_id'), isFalse,
          reason: 'backend resolves account from the public key; accountId '
              'must NOT be sent in the download body');
    });

    test('throws PurchaseRequiredException with the price on 402', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'Purchase required',
            'data': {'price': 19.99},
          }),
          402,
          headers: {'Content-Type': 'application/json'},
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.downloadPaidScriptBundle(
          'script-paid',
          accountId: 'acct-1',
          publicKeyB64: 'pk',
          signatureB64: 'sig',
          timestamp: '2024-01-01T00:00:00.000Z',
          nonce: 'nonce',
        ),
        throwsA(isA<PurchaseRequiredException>()
            .having((e) => e.price, 'price', 19.99)),
      );
    });

    test(
        'throws PurchaseRequiredException with price 0 when 402 body omits price',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'Purchase required'}),
          402,
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.downloadPaidScriptBundle(
          'script-paid',
          accountId: 'acct-1',
          publicKeyB64: 'pk',
          signatureB64: 'sig',
          timestamp: 'ts',
          nonce: 'n',
        ),
        throwsA(isA<PurchaseRequiredException>()
            .having((e) => e.price, 'price', 0.0)),
      );
    });

    test('throws DownloadAuthException on 401 (bad signature / unknown key)',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'Invalid signature'}),
          401,
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.downloadPaidScriptBundle(
          'script-x',
          accountId: 'acct-1',
          publicKeyB64: 'pk',
          signatureB64: 'sig',
          timestamp: 'ts',
          nonce: 'n',
        ),
        throwsA(isA<DownloadAuthException>()
            .having((e) => e.detail, 'detail', contains('Invalid signature'))),
      );
    });
  });

  group('getIcpayConfig', () {
    test('parses camelCase config on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            'https://mock.api/api/v1/payments/icpay/config');
        return ok(jsonEncode({
          'success': true,
          'data': {
            'publishableKey': 'pk_test_abc',
            'shortcode': 'ic_icp',
            'apiUrl': 'https://api.icpay.org',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final config = await service.getIcpayConfig();
      expect(config.publishableKey, 'pk_test_abc');
      expect(config.shortcode, 'ic_icp');
      expect(config.apiUrl, 'https://api.icpay.org');
    });

    test('throws PaymentsNotConfiguredException on 503 (LOUD)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'ICPAY_PUBLISHABLE_KEY not configured',
          }),
          503,
        );
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        service.getIcpayConfig(),
        throwsA(isA<PaymentsNotConfiguredException>()),
      );
    });

    test('throws plain Exception on other 5xx', () async {
      final client = MockClient((request) async {
        return http.Response('bad gateway', 502);
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        service.getIcpayConfig(),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('HTTP 502'))),
      );
    });
  });
}
