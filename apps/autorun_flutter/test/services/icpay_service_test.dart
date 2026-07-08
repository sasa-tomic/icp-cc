import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/icpay_service.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/theme/app_design_system.dart';

/// Coverage for [IcpayService]:
/// - `loadConfig` caches the result and surfaces [PaymentsNotConfiguredException]
///   from the underlying api.
/// - `createPaymentIntent` POSTs the correct URL/headers/body and parses the
///   intent defensively (bare object + `{data:{...}}` envelope + checkout URL
///   field-name candidates).
/// - `openCheckout` calls the injected launcher with the intent's checkout URL,
///   falling back to the ICPay web root when the URL is absent.
void main() {
  group('IcpayService.loadConfig', () {
    setUp(() {
      AppConfig.setTestEndpoint('https://mock.api');
    });

    test('delegates to api.getIcpayConfig and caches across calls', () async {
      var fetchCount = 0;
      const sentShortcode = 'test_shortcode_fixture';
      final api = MarketplaceOpenApiService();
      api.overrideHttpClient(MockClient((_) async {
        fetchCount++;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'publishableKey': 'pk_test_cached',
              'shortcode': sentShortcode,
              'apiUrl': 'https://api.icpay.org',
            },
          }),
          200,
        );
      }));
      addTearDown(api.resetHttpClient);

      final service = IcpayService();
      final c1 = await service.loadConfig(api);
      final c2 = await service.loadConfig(api);

      expect(identical(c1, c2), isTrue,
          reason: 'cached config must be the same instance');
      expect(fetchCount, 1, reason: 'second loadConfig must hit the cache');
      expect(c1.publishableKey, 'pk_test_cached');
      // Echoes the backend-supplied shortcode (no client-side 'ic_icp' literal).
      expect(c1.shortcode, sentShortcode);

      // resetConfigCache forces a re-fetch.
      service.resetConfigCache();
      final c3 = await service.loadConfig(api);
      expect(fetchCount, 2);
      expect(c3.publishableKey, 'pk_test_cached');
    });

    test('propagates PaymentsNotConfiguredException on 503 (no swallow)',
        () async {
      final api = MarketplaceOpenApiService();
      api.overrideHttpClient(MockClient((_) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'not configured'}),
          503,
        );
      }));
      addTearDown(api.resetHttpClient);

      final service = IcpayService();
      expect(service.loadConfig(api),
          throwsA(isA<PaymentsNotConfiguredException>()));
    });
  });

  group('IcpayService.createPaymentIntent', () {
    // A clearly-test-fixture shortcode — proves the config's shortcode is
    // passed through verbatim (config.shortcode -> request tokenShortcode),
    // not a bare 'ic_icp' literal.
    const shortcode = 'test_shortcode_fixture';
    final config = const IcpayClientConfig(
      publishableKey: 'pk_test_abc',
      shortcode: shortcode,
      apiUrl: 'https://api.icpay.org',
    );

    test('POSTs correct URL, Bearer header, and body with metadata', () async {
      String? capturedUrl;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedUrl = request.url.toString();
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'intent-123',
            'status': 'requires_confirmation',
            'checkoutUrl': 'https://checkout.icpay.org/i123',
          }),
          200,
        );
      });

      final service = IcpayService();
      final intent = await service.createPaymentIntent(
        accountId: 'acct-42',
        scriptId: 'script-9',
        usdAmount: 12.5,
        config: config,
        client: client,
      );

      expect(capturedUrl, 'https://api.icpay.org/sdk/public/payments/intents');
      expect(capturedHeaders?['Authorization'], 'Bearer pk_test_abc');
      expect(capturedHeaders?['Content-Type'], 'application/json');
      expect(capturedBody, {
        'tokenShortcode': shortcode,
        'usdAmount': 12.5,
        'metadata': {
          'account_id': 'acct-42',
          'script_id': 'script-9',
        },
      });
      expect(intent.id, 'intent-123');
      expect(intent.status, 'requires_confirmation');
      expect(intent.checkoutUrl, 'https://checkout.icpay.org/i123');
    });

    test('parses intent from a {data:{...}} envelope', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'intent-env',
              'status': 'succeeded',
              'hosted_url': 'https://checkout.icpay.org/env',
            },
          }),
          200,
        );
      });
      final service = IcpayService();
      final intent = await service.createPaymentIntent(
        accountId: 'a',
        scriptId: 's',
        usdAmount: 1,
        config: config,
        client: client,
      );
      expect(intent.id, 'intent-env');
      expect(intent.status, 'succeeded');
      expect(intent.checkoutUrl, 'https://checkout.icpay.org/env',
          reason: 'hosted_url is one of the defensive field-name candidates');
    });

    test('leaves checkoutUrl null when no URL-like field is present', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'id': 'no-url', 'status': 'pending'}),
          200,
        );
      });
      final service = IcpayService();
      final intent = await service.createPaymentIntent(
        accountId: 'a',
        scriptId: 's',
        usdAmount: 1,
        config: config,
        client: client,
      );
      expect(intent.checkoutUrl, isNull);
    });

    test('throws PaymentIntentException on non-2xx', () async {
      final client = MockClient((_) async {
        return http.Response('Forbidden', 403);
      });
      final service = IcpayService();
      expect(
        () => service.createPaymentIntent(
          accountId: 'a',
          scriptId: 's',
          usdAmount: 1,
          config: config,
          client: client,
        ),
        throwsA(isA<PaymentIntentException>()),
      );
    });

    test('throws PaymentIntentException on non-JSON 200', () async {
      final client = MockClient((_) async {
        return http.Response('<<<not json>>>', 200);
      });
      final service = IcpayService();
      expect(
        () => service.createPaymentIntent(
          accountId: 'a',
          scriptId: 's',
          usdAmount: 1,
          config: config,
          client: client,
        ),
        throwsA(isA<PaymentIntentException>()),
      );
    });

    test('bounds the external POST — an unreachable provider times out '
        '(TD-8: no infinite hang)', () {
      fakeAsync((async) {
        // A client that never responds — models ICPay.org being unreachable
        // from the dev sandbox. Mock lives only at the http.Client boundary.
        final client =
            MockClient((_) => Completer<http.Response>().future);
        final service = IcpayService();

        Object? captured;
        service
            .createPaymentIntent(
          accountId: 'a',
          scriptId: 's',
          usdAmount: 1,
          config: config,
          client: client,
          )
            .then<void>(
              (_) {},
              onError: (Object e) => captured = e,
            );

        async.flushMicrotasks();
        // One tick before the budget: still hanging (proves the call does not
        // fail fast / silently swallow).
        async.elapse(AppDurations.networkRequest - const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(captured, isNull,
            reason: 'must hang until the network budget elapses, not fail fast');

        // Past AppDurations.networkRequest: the POST must time out loudly.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(captured, isA<TimeoutException>(),
            reason: 'an unreachable provider must surface a TimeoutException, '
                'not hang forever');
      });
    });
  });

  group('IcpayService.openCheckout', () {
    test('launches the intent checkoutUrl via the injected launcher',
        () async {
      Uri? launched;
      final service = IcpayService(
        urlLauncher: (url) async {
          launched = url;
          return true;
        },
      );
      const intent = PaymentIntent(
        id: 'i1',
        status: 'pending',
        checkoutUrl: 'https://checkout.icpay.org/i1',
        raw: {},
      );
      final result = await service.openCheckout(intent);
      expect(result, isTrue);
      expect(launched, Uri.parse('https://checkout.icpay.org/i1'));
    });

    test(
        'falls back to https://app.icpay.org when checkoutUrl is null '
        '(ASSUMPTION: human must confirm the real hosted-checkout pattern)',
        () async {
      Uri? launched;
      final service = IcpayService(
        urlLauncher: (url) async {
          launched = url;
          return true;
        },
      );
      const intent = PaymentIntent(
        id: 'i1',
        status: 'pending',
        checkoutUrl: null,
        raw: {},
      );
      await service.openCheckout(intent);
      expect(launched, Uri.parse('https://app.icpay.org'),
          reason: 'fallback URL — must be replaced with the real ICPay '
              'hosted-checkout pattern once confirmed');
    });

    test('propagates launcher failure (returns false)', () async {
      final service = IcpayService(
        urlLauncher: (_) async => false,
      );
      const intent = PaymentIntent(
        id: 'i1',
        status: 'pending',
        checkoutUrl: 'https://checkout.icpay.org/i1',
        raw: {},
      );
      expect(await service.openCheckout(intent), isFalse);
    });
  });
}
