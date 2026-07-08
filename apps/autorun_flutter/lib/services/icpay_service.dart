import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_design_system.dart';
import 'marketplace_open_api_service.dart';

/// Function type for opening a URL externally. Defaults to [launchUrl] so
/// production uses the real url_launcher; tests inject a recording stub.
typedef UrlLauncher = Future<bool> Function(Uri url);

/// ICPay integration for paid-script purchases.
///
/// Three responsibilities, in call order from the Buy CTA:
///   1. [loadConfig] — fetch + cache the public ICPay client config
///      (publishable key, token shortcode, API URL) from the marketplace
///      backend. Throws [PaymentsNotConfiguredException] LOUDLY on 503.
///   2. [createPaymentIntent] — POST to ICPay's `/sdk/public/payments/intents`
///      with the publishable key + usdAmount + metadata linking the intent to
///      the purchasing account + script. Returns a [PaymentIntent] capturing
///      whatever ICPay returns.
///   3. [openCheckout] — launch the hosted checkout URL (from the intent, or a
///      best-effort fallback) in the external browser via url_launcher.
///
/// The hosted-checkout URL pattern is the ONE uncertain field — see the
/// prominent note on [PaymentIntent.checkoutUrl]. The human must confirm the
/// real ICPay hosted-checkout pattern; until then this falls back to
/// `https://app.icpay.org` and logs a warning.
class IcpayService {
  IcpayService({UrlLauncher? urlLauncher, http.Client? httpClient})
      : _urlLauncher = urlLauncher ?? _defaultLaunchUrl,
        _httpClientOverride = httpClient;

  final UrlLauncher _urlLauncher;
  final http.Client? _httpClientOverride;
  IcpayClientConfig? _cachedConfig;

  /// Fetch + cache the ICPay client config from the marketplace backend.
  ///
  /// The config is a public, browser-safe payload (publishable key only — the
  /// secret key never leaves the server), so caching it for the process
  /// lifetime is safe. Throws [PaymentsNotConfiguredException] on 503; the
  /// caller MUST surface this to the user, not swallow it.
  Future<IcpayClientConfig> loadConfig(MarketplaceOpenApiService api) async {
    final cached = _cachedConfig;
    if (cached != null) return cached;
    final config = await api.getIcpayConfig();
    _cachedConfig = config;
    return config;
  }

  /// Create an ICPay payment intent for a script purchase.
  ///
  /// POSTs to `${apiUrl}/sdk/public/payments/intents` with the publishable key
  /// as a Bearer token and a body of `{tokenShortcode, usdAmount,
  /// metadata:{account_id, script_id}}`. The metadata lets the ICPay webhook
  /// (received by the marketplace backend) credit the right account + script.
  ///
  /// Returns a [PaymentIntent] capturing whatever ICPay returns. The response
  /// shape is uncertain from the client side, so [PaymentIntent] is parsed
  /// defensively: known fields (`id`, `status`, checkout URL candidates) are
  /// read where present, extras are tolerated.
  ///
  /// Pass [client] to inject a mock HTTP client in tests.
  Future<PaymentIntent> createPaymentIntent({
    required String accountId,
    required String scriptId,
    required double usdAmount,
    required IcpayClientConfig config,
    http.Client? client,
  }) async {
    final http.Client effectiveClient = client ?? _httpClientOverride ?? http.Client();
    final ownClient = client == null && _httpClientOverride == null;
    try {
      final uri = Uri.parse('${config.apiUrl}/sdk/public/payments/intents');
      final body = jsonEncode({
        'tokenShortcode': config.shortcode,
        'usdAmount': usdAmount,
        'metadata': {
          'account_id': accountId,
          'script_id': scriptId,
        },
      });

      final response = await effectiveClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.publishableKey}',
            },
            body: body,
          )
          .timeout(AppDurations.networkRequest);

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw PaymentIntentException(
          'ICPay intent creation failed '
          '(HTTP ${response.statusCode}): ${response.body}',
        );
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (e) {
        throw PaymentIntentException(
          'ICPay intent response was not valid JSON: $e',
        );
      }
      return PaymentIntent.fromJson(decoded);
    } finally {
      if (ownClient) {
        effectiveClient.close();
      }
    }
  }

  /// Open the ICPay hosted checkout for [intent] in the external browser.
  ///
  /// Returns true if the OS launched the URL. See the prominent assumption
  /// note on [PaymentIntent.checkoutUrl]: if ICPay did not return a checkout
  /// URL, this falls back to `https://app.icpay.org` and logs a warning. The
  /// human must confirm the real hosted-checkout URL pattern from ICPay docs.
  Future<bool> openCheckout(PaymentIntent intent) async {
    final url = intent.checkoutUrl;
    if (url == null) {
      // ASSUMPTION pending ICPay docs: the hosted-checkout URL is not
      // derivable from the intent response shape we can see. Fall back to the
      // ICPay web app root so the user at least lands somewhere they can
      // complete payment; the human MUST verify the real pattern.
      debugPrint(
        'IcpayService.openCheckout: intent has no checkout URL '
        '(intent ${intent.id}); falling back to https://app.icpay.org. '
        'This fallback MUST be replaced with the real ICPay hosted-checkout '
        'URL pattern once confirmed from ICPay docs.',
      );
      return _urlLauncher(Uri.parse('https://app.icpay.org'));
    }
    return _urlLauncher(Uri.parse(url));
  }

  /// Clears the cached config. Tests call this between cases so a stub
  /// `loadConfig` does not leak across the registry.
  void resetConfigCache() {
    _cachedConfig = null;
  }

  static Future<bool> _defaultLaunchUrl(Uri url) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

/// A single ICPay payment intent.
///
/// Field names here are the ones the client relies on; the raw decoded body
/// is retained on [raw] for debugging the uncertain ICPay response shape.
///
/// **ASSUMPTION (human must verify):** the hosted checkout URL. ICPay's
/// intent response shape is not fully documented from the client side. This
/// parser reads the checkout URL from a few plausible field names
/// (`checkoutUrl`, `hosted_url`, `url`, `payment_url`); if none are present,
/// [checkoutUrl] is `null` and [IcpayService.openCheckout] falls back to the
/// ICPay web app root with a warning.
class PaymentIntent {
  final String id;
  final String status;
  final String? checkoutUrl;
  final Map<String, dynamic> raw;

  const PaymentIntent({
    required this.id,
    required this.status,
    this.checkoutUrl,
    required this.raw,
  });

  factory PaymentIntent.fromJson(dynamic decoded) {
    // Tolerate either an `{data:{...}}` envelope or a bare object. Prefer the
    // envelope when `data` is a Map (ICPay's documented convention); fall back
    // to the decoded object itself for bare responses.
    final Map<String, dynamic> data;
    if (decoded is Map && decoded['data'] is Map) {
      data = Map<String, dynamic>.from(decoded['data'] as Map);
    } else if (decoded is Map<String, dynamic>) {
      data = decoded;
    } else {
      data = const {};
    }

    final id = (data['id'] ?? data['intent_id'] ?? data['intentId'] ?? '')
        .toString();
    final status = (data['status'] ?? 'unknown').toString();

    // Defensive checkout-URL extraction. Field name is uncertain; try the
    // plausible candidates. The first non-empty, http(s) string wins.
    String? checkoutUrl;
    for (final key in const [
      'checkoutUrl',
      'checkout_url',
      'hostedUrl',
      'hosted_url',
      'paymentUrl',
      'payment_url',
      'url',
    ]) {
      final value = data[key];
      if (value is String && value.startsWith('http')) {
        checkoutUrl = value;
        break;
      }
    }

    return PaymentIntent(
      id: id,
      status: status,
      checkoutUrl: checkoutUrl,
      raw: data,
    );
  }

  @override
  String toString() =>
      'PaymentIntent{id: $id, status: $status, checkoutUrl: $checkoutUrl}';
}

/// Thrown when ICPay intent creation fails (non-2xx or malformed response).
class PaymentIntentException implements Exception {
  final String message;
  const PaymentIntentException(this.message);
  @override
  String toString() => 'PaymentIntentException: $message';
}
