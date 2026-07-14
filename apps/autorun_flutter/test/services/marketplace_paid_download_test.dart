import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/script_signature_service.dart';

/// Coverage for the ICPay / paid-download surface of
/// [MarketplaceOpenApiService]:
/// - `getScriptDetails(id)` fetches metadata-only (W7-2: the `?account_id=`
///   entitlement bypass is gone; `bundle`/`purchased` are never authoritative
///   for paid scripts here).
/// - `checkEntitlement` is the signed replacement: POSTs an Ed25519-signed
///   body and parses `{purchased, owns}`. Throws on 401 / non-2xx.
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

  group('getScriptDetails (W7-2: no accountId param)', () {
    test('hits the bare /scripts/:id URL with no query string', () async {
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

      // W7-2: the entitlement-bypassing ?account_id= query is GONE. The bare
      // URL is all that's sent; entitlement is resolved via checkEntitlement.
      expect(capturedUrl, 'https://mock.api/api/v1/scripts/script-free');
      expect(script.purchased, isTrue);
    });
  });

  group('checkEntitlement (W7-2 signed entitlement check)', () {
    /// Builds a minimal valid [SignedEntitlementRequest] for testing. The
    /// signature is a placeholder — the mock HTTP client doesn't verify it
    /// (that's the backend's job, covered by the Rust entitlement tests).
    SignedEntitlementRequest fakeSigned() => const SignedEntitlementRequest(
          signatureB64: 'sig-b64',
          authorPublicKeyB64: 'pk-b64',
          authorPrincipal: 'principal-text',
          timestamp: 1700000000,
          nonce: '11111111-1111-1111-1111-111111111111',
        );

    test('POSTs the 5-field signed body to /entitlement and parses the result',
        () async {
      Map<String, dynamic>? capturedBody;
      String? capturedUrl;
      final client = MockClient((request) async {
        capturedUrl = request.url.toString();
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return ok(jsonEncode({
          'success': true,
          'data': {'purchased': true, 'owns': false},
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final result =
          await service.checkEntitlement('script-1', signed: fakeSigned());

      expect(result.purchased, isTrue);
      expect(result.owns, isFalse);
      expect(capturedUrl,
          'https://mock.api/api/v1/scripts/script-1/entitlement');
      // Body is exactly the snake_case shape the backend expects.
      expect(capturedBody, {
        'signature': 'sig-b64',
        'author_public_key': 'pk-b64',
        'author_principal': 'principal-text',
        'timestamp': 1700000000,
        'nonce': '11111111-1111-1111-1111-111111111111',
      });
    });

    test('surfaces 401 (bad signature / unknown key) as an Exception', () {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'success': false, 'error': 'Invalid signature'}),
            401,
          ));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.checkEntitlement('script-1', signed: fakeSigned()),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'status', contains('HTTP 401'))),
      );
    });

    test('throws FormatException when purchased/owns are not booleans',
        () async {
      final client = MockClient((_) async => ok(jsonEncode({
            'success': true,
            // purchased missing, owns is a string — malformed contract.
            'data': {'owns': 'yes'},
          })));
      service.overrideHttpClient(client);
      addTearDown(client.close);

      expect(
        () => service.checkEntitlement('script-1', signed: fakeSigned()),
        throwsA(isA<FormatException>()),
      );
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
    test('parses camelCase config on 200 (echoes the backend shortcode, no '
        'client-side fallback literal)', () async {
      const sentShortcode = 'icpay_token_test_42';
      final client = MockClient((request) async {
        expect(request.url.toString(),
            'https://mock.api/api/v1/payments/icpay/config');
        return ok(jsonEncode({
          'success': true,
          'data': {
            'publishableKey': 'pk_test_abc',
            'shortcode': sentShortcode,
            'apiUrl': 'https://api.icpay.org',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      final config = await service.getIcpayConfig();
      expect(config.publishableKey, 'pk_test_abc');
      // Asserts equality to the RETURNED config value — not a bare 'ic_icp'
      // literal, so a re-introduced client-side fallback would fail here.
      expect(config.shortcode, sentShortcode);
      expect(config.apiUrl, 'https://api.icpay.org');
    });

    test('fails loudly when the 200 config omits shortcode (no fallback)',
        () async {
      final client = MockClient((request) async {
        return ok(jsonEncode({
          'success': true,
          'data': {
            'publishableKey': 'pk_test_abc',
            // shortcode intentionally missing — must NOT default to 'ic_icp'.
            'apiUrl': 'https://api.icpay.org',
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await expectLater(
        service.getIcpayConfig(),
        throwsA(isA<PaymentsConfigMalformedException>()
            .having((e) => e.detail, 'detail', contains('shortcode'))),
      );
    });

    test('throws when the 200 config omits apiUrl (NO silent client fallback)',
        () async {
      // AUD-8: the client must not carry a duplicated api.icpay.org literal.
      // A missing apiUrl is a malformed server config — fail loudly with a typed
      // error carrying the raw body, never a silent fallback to a stale host.
      final client = MockClient((request) async {
        return ok(jsonEncode({
          'success': true,
          'data': {
            'publishableKey': 'pk_test_abc',
            'shortcode': 'ic_icp',
            // apiUrl intentionally missing — must NOT fall back to a literal.
          },
        }));
      });
      service.overrideHttpClient(client);
      addTearDown(client.close);

      await expectLater(
        service.getIcpayConfig(),
        throwsA(isA<PaymentsConfigMalformedException>()
            .having((e) => e.detail, 'detail', contains('apiUrl'))
            .having((e) => e.rawBody, 'rawBody', contains('shortcode'))),
      );
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
