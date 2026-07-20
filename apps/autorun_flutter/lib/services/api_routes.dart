import '../config/app_config.dart';

/// Single source for every `/api/v1` route path the app requests.
///
/// Each route is defined exactly once here (TD-6); services consume these names
/// instead of re-inlining `'$_base/scripts/…'` path segments at ~25 call sites.
/// The backend route table (`backend/src/handlers/*`, registered in
/// `backend/src/main.rs`) remains the cross-language source of truth — this
/// only de-duplicates *within* Dart. KISS: plain path strings, no URL-builder
/// framework.
abstract final class ApiRoutes {
  ApiRoutes._();

  /// API base prefix shared by every route below. Was duplicated as the
  /// private `_baseUrl` in both the marketplace and passkey services.
  static String get base => '${AppConfig.apiEndpoint}/api/v1';

  // ---- Scripts -------------------------------------------------------------
  static String get scriptsSearch => '$base/scripts/search';
  static String get scriptsCategories => '$base/scripts/categories';

  /// Create a script (POST) — also the upload URL.
  static String get scriptsCreate => '$base/scripts';

  static String script(String id) => '$base/scripts/$id';
  static String scriptPreview(String id) => '$base/scripts/$id/preview';
  static String scriptDownload(String id) => '$base/scripts/$id/download';
  static String scriptEntitlement(String id) => '$base/scripts/$id/entitlement';
  /// Provider-agnostic purchase endpoint (Phase K). Dispatches to the
  /// backend's active provider (stub auto-grants; icpay returns a checkout
  /// intent; none → 503). Signed like /download + /entitlement.
  static String scriptPurchase(String id) => '$base/scripts/$id/purchase';
  static String scriptReviews(String id) => '$base/scripts/$id/reviews';
  static String scriptVersion(String id, String version) =>
      '$base/scripts/$id/versions/$version';
  static String scriptDelete(String id) => '$base/scripts/$id/delete';
  static String scriptsByCategory(String category) =>
      '$base/scripts/category/$category';
  static String get scriptsCompatible => '$base/scripts/compatible';

  // ---- Accounts ------------------------------------------------------------
  static String get accounts => '$base/accounts';
  static String accountByUsername(String username) => '$base/accounts/$username';
  static String accountByPublicKey(String encodedKey) =>
      '$base/accounts/by-public-key/$encodedKey';
  static String accountKeys(String username) => '$base/accounts/$username/keys';
  static String accountKey(String username, String keyId) =>
      '$base/accounts/$username/keys/$keyId';

  // ---- Payments / Stats ----------------------------------------------------
  /// Provider-agnostic public client config (Phase K). Replaces the
  /// ICPay-specific /payments/icpay/config for new clients.
  static String get paymentsConfig => '$base/payments/config';
  /// Legacy ICPay-specific config route — still mounted by the backend when
  /// PAYMENT_PROVIDER=icpay (delegates to the generic /payments/config).
  static String get paymentsIcpayConfig => '$base/payments/icpay/config';
  static String get marketplaceStats => '$base/marketplace-stats';
}
