import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/marketplace_script.dart';
import '../models/purchase_record.dart';
import '../models/account.dart';
import '../utils/base64_utils.dart';
import '../theme/app_design_system.dart';
import 'api_routes.dart';

// Flag to control debug output in tests
bool suppressDebugOutput = false;

/// Thrown by `POST /api/v1/scripts/:id/download` when the caller is entitled
/// to FREE download but the script is paid and the caller has no purchase
/// record (HTTP 402). Carries the price so the UI can render the Buy CTA.
class PurchaseRequiredException implements Exception {
  final double price;
  const PurchaseRequiredException(this.price);

  @override
  String toString() => 'PurchaseRequiredException: price \$$price';
}

/// Thrown when an authenticated download fails signature / public-key
/// verification (HTTP 401). Indicates the signing keypair is not bound to any
/// account, or the signature over `download:{id}:{ts}:{nonce}` is invalid.
class DownloadAuthException implements Exception {
  final String detail;
  const DownloadAuthException(this.detail);

  @override
  String toString() => 'DownloadAuthException: $detail';
}

/// Thrown by `GET /api/v1/payments/icpay/config` when the publishable key is
/// unset server-side (HTTP 503). The caller must surface this LOUDLY to the
/// user ("Payments not configured") rather than silently swallowing it.
class PaymentsNotConfiguredException implements Exception {
  const PaymentsNotConfiguredException();
  @override
  String toString() =>
      'PaymentsNotConfiguredException: ICPay publishable key not set on server';
}

/// Thrown when the ICPay config payload is structurally incomplete — i.e. the
/// backend returned 200 `success:true` but a required field (`shortcode` or
/// `apiUrl`) is missing/empty. Carries the raw body so the caller can surface
/// exactly what the server sent. This is a LOUD failure: the client must NOT
/// silently substitute a duplicated literal for the missing value (AUD-8 — the
/// backend is the single source for the ICPay API host).
class PaymentsConfigMalformedException implements Exception {
  final String detail;
  final String rawBody;
  const PaymentsConfigMalformedException(this.detail, this.rawBody);
  @override
  String toString() =>
      'PaymentsConfigMalformedException: $detail (raw body: $rawBody)';
}

/// Thrown by `GET /api/v1/scripts/:id/reviews` when the response `data` does
/// not match the backend contract `{reviews: [...], total: int, hasMore: bool}`.
/// Surfaced loudly (and rethrown) so the UI shows a real error instead of
/// silently rendering an empty Reviews tab — see UXR7-1 / QS-1.
class MalformedReviewsResponseException implements Exception {
  final String detail;
  const MalformedReviewsResponseException(this.detail);
  @override
  String toString() => 'MalformedReviewsResponseException: $detail';
}

abstract class MarketplaceOpenApi {
  Future<MarketplaceSearchResult> searchScripts({
    String? query,
    String? category,
    String? canisterId,
    double? minRating,
    double? maxPrice,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
    int limit = 20,
    int offset = 0,
  });

  List<String> getCategories();

  /// Fetches the live, content-derived category list from
  /// `GET /api/v1/scripts/categories` (distinct categories among public scripts).
  /// Falls back to the static [getCategories] defaults on error with a loud
  /// warning — categories are UI metadata, not security-critical, so a stale
  /// chip list is preferable to blocking the whole browse screen.
  Future<List<String>> fetchCategories();

  Future<String> downloadScript(String scriptId, {String? version});
}

class MarketplaceOpenApiService implements MarketplaceOpenApi {
  static final MarketplaceOpenApiService _instance =
      MarketplaceOpenApiService._internal();
  factory MarketplaceOpenApiService() => _instance;
  MarketplaceOpenApiService._internal() : _httpClient = http.Client();

  http.Client _httpClient;
  static const int defaultSearchLimit = 20;

  @visibleForTesting
  void overrideHttpClient(http.Client client) {
    _httpClient = client;
  }

  @visibleForTesting
  void resetHttpClient() {
    _httpClient = http.Client();
  }

  // Search scripts with advanced filtering
  @override
  Future<MarketplaceSearchResult> searchScripts({
    String? query,
    String? category,
    String? canisterId,
    double? minRating,
    double? maxPrice,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
    int limit = defaultSearchLimit,
    int offset = 0,
  }) async {
    try {
      final url = ApiRoutes.scriptsSearch;

      // Build request body, only including non-null values
      final requestBody = <String, dynamic>{
        'sortBy': sortBy,
        'order': sortOrder,
        'limit': limit,
        'offset': offset,
      };

      // Only add optional parameters if they're not null
      if (query != null) requestBody['query'] = query;
      if (category != null) requestBody['category'] = category;
      if (canisterId != null) requestBody['canisterId'] = canisterId;
      if (minRating != null) requestBody['minRating'] = minRating;
      if (maxPrice != null) requestBody['maxPrice'] = maxPrice;

      final response = await _httpClient
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(AppDurations.browseTimeout);

      final responseData = _decodeSuccessResponse(response, label: 'Search');

      final data = responseData['data'];
      final scripts = (data['scripts'] as List)
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();

      return MarketplaceSearchResult(
        scripts: scripts,
        total: data['total'] ?? 0,
        hasMore: data['hasMore'] ?? false,
        offset: offset,
        limit: limit,
      );
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Search scripts failed: $e');
      rethrow;
    }
  }

  // Get script details by ID.
  //
  // Pass [accountId] (the backend Account.id, not username) to receive the
  // entitlement-gated view: for paid scripts the response's `bundle` is `null`
  // and `purchased` is `false` unless the account owns/has-purchased the
  // script. Without [accountId] the server treats paid scripts as locked.
  Future<MarketplaceScript> getScriptDetails(
    String scriptId, {
    String? accountId,
  }) async {
    try {
      final uri = accountId == null || accountId.isEmpty
          ? Uri.parse(ApiRoutes.script(scriptId))
          : Uri.parse(ApiRoutes.script(scriptId))
              .replace(queryParameters: {'account_id': accountId});

      final response = await _httpClient.get(uri).timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        throw Exception('Script not found');
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Get script details');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Script details');
      return MarketplaceScript.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script details failed: $e');
      rethrow;
    }
  }

  /// Lightweight browse-time preview (UX-6).
  ///
  /// Returns a server-side CAPPED excerpt of the source plus browse-relevant
  /// metadata instead of the full bundle, so the Script Details dialog can
  /// render a 50-line preview without downloading the whole script. For PAID
  /// scripts the cap is smaller and the full source is NEVER sent — call this
  /// instead of [downloadScript] for any browse/preview purpose.
  ///
  /// Throws on 404 / non-2xx / malformed body (same contract as
  /// [getScriptDetails]); the caller decides the fallback (free → full
  /// download, paid → purchase gate).
  Future<ScriptPreview> getScriptPreview(String scriptId) async {
    try {
      final response = await _httpClient
          .get(Uri.parse(ApiRoutes.scriptPreview(scriptId)))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        throw Exception('Script not found');
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Get script preview');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Script preview');
      return ScriptPreview.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script preview failed: $e');
      rethrow;
    }
  }

  // Note: getFeaturedScripts / getTrendingScripts client methods were REMOVED
  // (AUD-12): they had no production callers (only their own self-tests) —
  // YAGNI. The backend `/scripts/featured` + `/scripts/trending` endpoints
  // remain (covered by `list_bundle_omission_tests`); re-add a typed client
  // method only when a screen actually consumes them.

  // Get scripts by category
  Future<List<MarketplaceScript>> getScriptsByCategory(
    String category, {
    int limit = 20,
    int offset = 0,
    String sortBy = 'rating',
    String sortOrder = 'desc',
  }) async {
    try {
      final uri = Uri.parse(ApiRoutes.scriptsByCategory(category))
          .replace(queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      });

      final response = await _httpClient.get(uri).timeout(AppDurations.browseTimeout);

      final responseData =
          _decodeSuccessResponse(response, label: 'Get scripts by category');

      final data = responseData['data'] as List;
      return data
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();
    } catch (e) {
      if (!suppressDebugOutput) {
        debugPrint('Get scripts by category failed: $e');
      }
      rethrow;
    }
  }

  // Get script reviews
  Future<List<ScriptReview>> getScriptReviews(
    String scriptId, {
    int limit = 20,
    int offset = 0,
    bool verifiedOnly = false,
  }) async {
    try {
      final uri = Uri.parse(ApiRoutes.scriptReviews(scriptId))
          .replace(queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (verifiedOnly) 'verified_only': 'true',
      });

      final response = await _httpClient.get(uri).timeout(AppDurations.browseTimeout);

      final responseData =
          _decodeSuccessResponse(response, label: 'Get script reviews');

      // The backend returns data as a Map: {reviews: [...], total: int,
      // hasMore: bool} (backend/src/handlers/reviews.rs). A bare-array cast
      // crashes on every Reviews-tab open (UXR7-1). Read it as a Map and
      // extract the reviews list; surface a LOUD typed error if the contract
      // ever drifts rather than silently returning an empty list.
      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw MalformedReviewsResponseException(
          'expected data to be a Map with a "reviews" list, '
          'got ${data.runtimeType}',
        );
      }
      final reviewsList = data['reviews'];
      if (reviewsList is! List) {
        throw MalformedReviewsResponseException(
          'expected "reviews" to be a list, got ${reviewsList.runtimeType}',
        );
      }
      return reviewsList
          .whereType<Map<String, dynamic>>()
          .map((review) => ScriptReview.fromJson(review))
          .toList();
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script reviews failed: $e');
      rethrow;
    }
  }

  // Get marketplace categories
  @override
  List<String> getCategories() {
    return const [
      'Example',
      'Uncategorized',
      'Gaming',
      'Finance',
      'DeFi',
      'NFT',
      'Social',
      'Utilities',
      'Development',
      'Education',
      'Entertainment',
      'Business',
    ];
  }

  @override
  Future<List<String>> fetchCategories() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse(ApiRoutes.scriptsCategories),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(AppDurations.browseTimeout);

      final responseData = _decodeSuccessResponse(response, label: 'Categories');
      final data = responseData['data'];
      final categories = data['categories'];
      if (categories is! List) {
        throw FormatException(
          "categories response 'data.categories' is not a List: $categories",
        );
      }
      final result = categories.whereType<String>().toList();
      if (result.isEmpty) {
        // An empty live list is suspicious (backend always seeds defaults);
        // keep the static fallback rather than rendering zero chips.
        debugPrint('fetchCategories: backend returned empty list; '
            'using static defaults');
        return getCategories();
      }
      return result;
    } catch (e) {
      // Categories are UI metadata — never block the browse screen on them.
      // Log loudly (per AGENTS.md) and degrade to the static defaults.
      debugPrint('fetchCategories failed, using static defaults: $e');
      return getCategories();
    }
  }

  // Validate ICP canister ID format
  bool _isValidCanisterId(String canisterId) {
    // Basic validation for ICP canister ID format
    // Supports both 5-5-5-5-3 and 5-5-5-5-5-5 formats
    final regex55553 = RegExp(r'^[a-z0-9]{5}(-[a-z0-9]{5}){3}-[a-z0-9]{3}$');
    final regex555555 = RegExp(r'^[a-z0-9]{5}(-[a-z0-9]{5}){5}$');
    return regex55553.hasMatch(canisterId) || regex555555.hasMatch(canisterId);
  }

  // Search scripts by canister ID (specific functionality for ICP integration)
  Future<List<MarketplaceScript>> searchScriptsByCanisterId(
    String canisterId, {
    int limit = 20,
  }) async {
    try {
      // Validate canister ID format
      if (!_isValidCanisterId(canisterId)) {
        throw Exception('Invalid canister ID format');
      }

      final result = await searchScripts(
        canisterId: canisterId,
        limit: limit,
        sortBy: 'rating',
        sortOrder: 'desc',
      );

      return result.scripts;
    } catch (e) {
      if (!suppressDebugOutput) {
        debugPrint('Search scripts by canister ID failed: $e');
      }
      rethrow;
    }
  }

  @override
  Future<String> downloadScript(String scriptId, {String? version}) async {
    try {
      MarketplaceScript script;

      if (version != null) {
        script = await getScriptVersion(scriptId, version);
      } else {
        script = await getScriptDetails(scriptId);
      }

      if (script.price > 0) {
        throw Exception('Paid scripts require authentication to download');
      }

      if (!script.isPublic) {
        throw Exception('Script is not available for download');
      }

      return script.bundle;
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Download script failed: $e');
      rethrow;
    }
  }

  /// Fetch the public ICPay client config. `GET /api/v1/payments/icpay/config`.
  ///
  /// Returns the browser-safe publishable key + token shortcode + ICPay API
  /// URL. Throws [PaymentsNotConfiguredException] on HTTP 503 (publishable key
  /// unset server-side) — the caller MUST surface this to the user, not
  /// swallow it. Other non-2xx statuses throw a plain [Exception].
  Future<IcpayClientConfig> getIcpayConfig() async {
    try {
      final response = await _httpClient
          .get(Uri.parse(ApiRoutes.paymentsIcpayConfig))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 503) {
        throw const PaymentsNotConfiguredException();
      }

      final responseData =
          _decodeSuccessResponse(response, label: 'ICPay config');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'ICPay config');
      return IcpayClientConfig.fromJson(data, rawBody: response.body);
    } on PaymentsNotConfiguredException {
      rethrow;
    } on PaymentsConfigMalformedException {
      rethrow;
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get ICPay config failed: $e');
      rethrow;
    }
  }

  /// Authenticated paid-bundle retrieval. `POST /api/v1/scripts/:id/download`.
  ///
  /// [accountId] is the backend Account.id of the caller — NOT sent in the
  /// request body (the backend resolves the account from [publicKeyB64] via
  /// the public-keys table). Kept on the signature for caller intent + so the
  /// high-level orchestrator can correlate the download with the active
  /// account in logs.
  ///
  /// The body sent is exactly `{"public_key","signature","timestamp","nonce"}`
  /// (snake_case, matching the backend `DownloadRequest` deserialiser). The
  /// signature is Ed25519 over the canonical string
  /// `download:{script_id}:{timestamp}:{nonce}` — produced by
  /// [DownloadSignatureService].
  ///
  /// Returns the script bundle on 200. Throws:
  /// - [PurchaseRequiredException] (with price) on 402 — UI routes to Buy.
  /// - [DownloadAuthException] on 401 — signature/key problem; loud error.
  Future<String> downloadPaidScriptBundle(
    String scriptId, {
    required String accountId,
    required String publicKeyB64,
    required String signatureB64,
    required String timestamp,
    required String nonce,
  }) async {
    final body = jsonEncode({
      'public_key': publicKeyB64,
      'signature': signatureB64,
      'timestamp': timestamp,
      'nonce': nonce,
    });

    if (!suppressDebugOutput) {
      debugPrint('Paid download request: script=$scriptId account=$accountId');
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.scriptDownload(scriptId)),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(AppDurations.downloadTimeout);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Paid download failed: $e');
      rethrow;
    }

    if (response.statusCode == 402) {
      double? price;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) {
            price = (data['price'] as num?)?.toDouble();
          }
        }
      } on FormatException catch (e) {
        debugPrint('downloadPaidScriptBundle 402 body decode failed: $e');
      }
      throw PurchaseRequiredException(price ?? 0.0);
    }
    if (response.statusCode == 401) {
      String detail = 'Authentication failed';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['error'] is String) {
          detail = decoded['error'] as String;
        }
      } on FormatException catch (e) {
        debugPrint('downloadPaidScriptBundle 401 body decode failed: $e');
      }
      throw DownloadAuthException(detail);
    }
    if (response.statusCode > 299) {
      throw Exception(
          'Paid download failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final responseData = jsonDecode(response.body);
    if (responseData is! Map<String, dynamic> ||
        responseData['success'] != true) {
      throw Exception(
          responseData['error'] ?? 'Paid download failed');
    }
    final data = responseData['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Paid download response missing data field');
    }
    final bundle = data['bundle'] as String?;
    if (bundle == null) {
      throw Exception('Paid download response missing bundle field');
    }
    return bundle;
  }

  Future<MarketplaceScript> getScriptVersion(
      String scriptId, String version) async {
    try {
      final response = await _httpClient
          .get(Uri.parse(ApiRoutes.scriptVersion(scriptId, version)))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        throw Exception('Script version $version not found');
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Get script version');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Script version');
      return MarketplaceScript.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) {
        debugPrint('Get script version failed: $e');
      }
      rethrow;
    }
  }

  Future<List<ScriptVersion>> getScriptVersions(String scriptId) async {
    try {
      final response = await _httpClient
          .get(Uri.parse(ApiRoutes.scriptVersions(scriptId)))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        return [];
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Get script versions');

      final data = responseData['data'];
      if (data == null || data is! List) {
        return [];
      }
      return data
          .whereType<Map<String, dynamic>>()
          .map((v) => ScriptVersion.fromJson(v))
          .toList();
    } catch (e) {
      if (!suppressDebugOutput) {
        debugPrint('Get script versions failed: $e');
      }
      rethrow;
    }
  }

  // Get marketplace statistics (public data)
  Future<MarketplaceStats> getMarketplaceStats() async {
    final url = ApiRoutes.marketplaceStats;
    if (!suppressDebugOutput) debugPrint('GET request URL: $url');
    final response =
        await _httpClient.get(Uri.parse(url)).timeout(AppDurations.browseTimeout);

    final responseData =
        _decodeSuccessResponse(response, label: 'Get marketplace stats');
    final data = _decodeDataField<Map<String, dynamic>>(responseData,
        label: 'Marketplace stats');
    return MarketplaceStats.fromJson(data);
  }

  // Get canister compatibility info.
  //
  // The Cloudflare endpoint accepts exactly one canister id per request, so
  // the API takes a single [canisterId] rather than a list — this makes it
  // impossible for a caller to (mis)believe >1 id is honoured.
  Future<List<MarketplaceScript>> getCompatibleScripts(
    String canisterId, {
    int limit = 50,
  }) async {
    try {
      if (!_isValidCanisterId(canisterId)) {
        throw Exception('Invalid canister ID format: $canisterId');
      }

      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.scriptsCompatible),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'canisterId': canisterId,
              'limit': limit,
            }),
          )
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get compatible scripts');
      }

      final data = responseData['data'] as List;
      return data
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get compatible scripts failed: $e');
      rethrow;
    }
  }

  // Upload a new script to the marketplace
  Future<MarketplaceScript> uploadScript({
    required String slug,
    required String title,
    required String description,
    required String category,
    required List<String> tags,
    required String bundle,
    List<String>? canisterIds,
    String? iconUrl,
    List<String>? screenshots,
    String? version,
    String? compatibility,
    double price = 0.0,
    String? authorPrincipal,
    String? authorPublicKey,
    String? signature,
    String? timestampIso,
  }) async {
    try {
      final requestBodyMap = <String, dynamic>{
        'slug': slug,
        'title': title,
        'description': description,
        'category': category,
        'tags': tags,
        'bundle': bundle,
        'canister_ids': canisterIds ?? [],
        'screenshots': screenshots ?? [],
        'version': version ?? '1.0.0',
        'price': price,
        'is_public': true,
      };

      // Only include non-null optional fields
      if (iconUrl != null) {
        requestBodyMap['icon_url'] = iconUrl;
      }
      if (compatibility != null) {
        requestBodyMap['compatibility'] = compatibility;
      }
      if (authorPrincipal != null) {
        requestBodyMap['author_principal'] = authorPrincipal;
      }
      if (authorPublicKey != null) {
        requestBodyMap['author_public_key'] = authorPublicKey;
      }
      if (signature != null) {
        requestBodyMap['signature'] = signature;
      }
      if (timestampIso != null) {
        requestBodyMap['timestamp'] = timestampIso;
      }

      final requestBody = jsonEncode(requestBodyMap);

      if (!suppressDebugOutput) {
        debugPrint('Upload request URL: ${ApiRoutes.scriptsCreate}');
        debugPrint('Request body: $requestBody');
      }

      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.scriptsCreate),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(AppDurations.downloadTimeout);

      if (response.statusCode < 200 || response.statusCode > 299) {
        if (!suppressDebugOutput) {
          debugPrint('Upload failed with status: ${response.statusCode}');
          debugPrint('Response body: ${response.body}');
          debugPrint('Reason phrase: "${response.reasonPhrase}"');
        }
        final errorMessage = _buildUploadErrorMessage(
          statusCode: response.statusCode,
          reasonPhrase: response.reasonPhrase,
          responseBody: response.body,
        );
        throw Exception(errorMessage);
      }

      if (response.body.isEmpty) {
        throw Exception(
            'Upload failed (HTTP ${response.statusCode}): Empty response from server');
      }

      final responseData = jsonDecode(response.body);
      if (responseData['success'] != true) {
        throw Exception(
          _buildUploadErrorMessage(
            statusCode: response.statusCode,
            reasonPhrase: response.reasonPhrase,
            serverError: responseData['error']?.toString(),
          ),
        );
      }

      final data = responseData['data'];
      if (data == null) {
        // Script was created but is not yet approved (not public)
        // Return a basic script object with the upload info
        return MarketplaceScript(
          id: 'script-${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          description: description,
          category: category,
          tags: tags,
          authorPrincipal: authorPrincipal,
          authorPublicKey: authorPublicKey,
          uploadSignature: signature,
          price: price,
          currency: 'ICP',
          downloads: 0,
          rating: 0.0,
          reviewCount: 0,
          verifiedReviewCount: 0,
          bundle: bundle,
          iconUrl: iconUrl,
          screenshots: screenshots ?? [],
          canisterIds: canisterIds ?? [],
          version: version ?? '1.0.0',
          compatibility: compatibility,
          isPublic: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      if (data is! Map<String, dynamic>) {
        throw Exception(
            'Upload response data is not a valid object. Data type: ${data.runtimeType}');
      }
      return MarketplaceScript.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Upload script failed: $e');
      rethrow;
    }
  }

  String _buildUploadErrorMessage({
    required int statusCode,
    String? reasonPhrase,
    String? responseBody,
    Object? serverError,
  }) {
    // Prefer an already-extracted server `error` string; otherwise tolerate
    // whatever the body contains via the shared extractor (never a
    // FormatException).
    final serverText = serverError?.toString().trim();
    final detail = (serverText != null && serverText.isNotEmpty)
        ? serverText
        : _extractServerError(statusCode, reasonPhrase, responseBody ?? '');
    return 'Upload failed (HTTP $statusCode): $detail';
  }

  // Update an existing script
  Future<MarketplaceScript> updateScript(
    String scriptId, {
    String? title,
    String? description,
    String? category,
    List<String>? tags,
    String? bundle,
    List<String>? canisterIds,
    String? iconUrl,
    List<String>? screenshots,
    String? version,
    String? compatibility,
    double? price,
    String? authorPrincipal,
    String? signature,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (category != null) body['category'] = category;
      if (tags != null) body['tags'] = tags;
      if (bundle != null) body['bundle'] = bundle;
      if (canisterIds != null) body['canister_ids'] = canisterIds;
      if (iconUrl != null) body['icon_url'] = iconUrl;
      if (screenshots != null) body['screenshots'] = screenshots;
      if (version != null) body['version'] = version;
      if (compatibility != null) body['compatibility'] = compatibility;
      if (price != null) body['price'] = price;
      if (authorPrincipal != null) body['author_principal'] = authorPrincipal;
      if (signature != null) body['signature'] = signature;

      final response = await _httpClient
          .put(
            Uri.parse(ApiRoutes.script(scriptId)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(AppDurations.downloadTimeout);

      final responseData =
          _decodeSuccessResponse(response, label: 'Update');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Update script');
      return MarketplaceScript.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Update script failed: $e');
      rethrow;
    }
  }

  // Delete a script
  Future<bool> deleteScript(String scriptId,
      {String? authorPrincipal, String? signature}) async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final body = <String, dynamic>{
        'action': 'delete',
        'timestamp': timestamp,
      };
      if (authorPrincipal != null) body['author_principal'] = authorPrincipal;
      if (signature != null) body['signature'] = signature;

      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.scriptDelete(scriptId)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(AppDurations.downloadTimeout);

      // Status + success contract enforced once, tolerantly (a non-JSON 502
      // body surfaces "HTTP 502: ..." rather than a FormatException).
      _decodeSuccessResponse(response, label: 'Delete');

      return true;
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Delete script failed: $e');
      rethrow;
    }
  }

  // Account management endpoints

  /// Register a new account with username and public key.
  ///
  /// Route: `ApiRoutes.accounts`.
  Future<Account> registerAccount(RegisterAccountRequest request) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.accounts),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(AppDurations.downloadTimeout);

      final responseData = _decodeSuccessResponse(
        response,
        label: 'Account registration',
        statusErrorPrefix: 'Account registration failed',
        failureFallback: 'Failed to register account',
      );
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Account registration');
      return Account.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Register account failed: $e');
      rethrow;
    }
  }

  /// Get account details by username.
  ///
  /// Route: `ApiRoutes.accountByUsername`.
  Future<Account?> getAccount({required String username}) async {
    try {
      final encodedUsername = Uri.encodeComponent(username);
      final response = await _httpClient
          .get(Uri.parse(ApiRoutes.accountByUsername(encodedUsername)))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        return null; // Account not found
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Account');
      final data =
          _decodeDataField<Map<String, dynamic>>(responseData, label: 'Account');
      return Account.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get account failed: $e');
      rethrow;
    }
  }

  /// Get account details by public key.
  ///
  /// Route: `ApiRoutes.accountByPublicKey`.
  ///
  /// Allows looking up an account using only the public key (base64 encoded).
  /// Returns null if no account is associated with this public key.
  Future<Account?> getAccountByPublicKey({required String publicKeyB64}) async {
    try {
      Base64Utils.requireBytes(publicKeyB64, fieldName: 'publicKeyB64');
      final encodedPublicKey = Uri.encodeComponent(publicKeyB64);
      final response = await _httpClient
          .get(Uri.parse(
              ApiRoutes.accountByPublicKey(encodedPublicKey)))
          .timeout(AppDurations.browseTimeout);

      if (response.statusCode == 404) {
        return null; // No account found for this public key
      }
      final responseData =
          _decodeSuccessResponse(response, label: 'Account by public key');
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Account by public key');
      return Account.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) {
        debugPrint('Get account by public key failed: $e');
      }
      rethrow;
    }
  }

  /// Add a public key to an account.
  ///
  /// Route: `ApiRoutes.accountKeys`.
  Future<AccountPublicKey> addPublicKey({
    required String username,
    required AddPublicKeyRequest request,
  }) async {
    try {
      final encodedUsername = Uri.encodeComponent(username);
      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.accountKeys(encodedUsername)),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(AppDurations.downloadTimeout);

      final responseData = _decodeSuccessResponse(
        response,
        label: 'Add key',
        statusErrorPrefix: 'Add key failed',
        failureFallback: 'Failed to add key',
      );
      final data =
          _decodeDataField<Map<String, dynamic>>(responseData, label: 'Add key');
      return AccountPublicKey.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Add public key failed: $e');
      rethrow;
    }
  }

  /// Remove a public key from an account (soft delete).
  ///
  /// Route: `ApiRoutes.accountKey`.
  Future<AccountPublicKey> removePublicKey({
    required String username,
    required String keyId,
    required RemovePublicKeyRequest request,
  }) async {
    try {
      final encodedUsername = Uri.encodeComponent(username);
      final response = await _httpClient
          .delete(
            Uri.parse(ApiRoutes.accountKey(encodedUsername, keyId)),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(AppDurations.downloadTimeout);

      final responseData = _decodeSuccessResponse(
        response,
        label: 'Remove key',
        statusErrorPrefix: 'Remove key failed',
        failureFallback: 'Failed to remove key',
      );
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Remove key');
      return AccountPublicKey.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Remove public key failed: $e');
      rethrow;
    }
  }

  /// Update account profile.
  ///
  /// Route: `ApiRoutes.accountByUsername` (PATCH).
  Future<Account> updateAccount({
    required String username,
    required UpdateAccountRequest request,
  }) async {
    try {
      final encodedUsername = Uri.encodeComponent(username);
      final response = await _httpClient
          .patch(
            Uri.parse(ApiRoutes.accountByUsername(encodedUsername)),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(AppDurations.downloadTimeout);

      final responseData = _decodeSuccessResponse(
        response,
        label: 'Update account',
        statusErrorPrefix: 'Update account failed',
        failureFallback: 'Failed to update account',
      );
      final data = _decodeDataField<Map<String, dynamic>>(responseData,
          label: 'Update account');
      return Account.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Update account failed: $e');
      rethrow;
    }
  }

  /// Whether [username] is free to register. Delegates to [getAccount],
  /// which returns `null` on HTTP 404; any other failure (5xx, transport,
  /// malformed body) propagates to the caller.
  Future<bool> isUsernameAvailable(String username) async {
    final account = await getAccount(username: username);
    return account == null;
  }

  /// Tolerantly extracts a human-readable error detail from an HTTP *error*
  /// response body (non-2xx). Used only from error branches, where masking the
  /// status with a [FormatException] ("Unexpected end of input") would be
  /// strictly worse than a generic message. **Never throws.**
  ///
  /// Resolution order:
  ///   1. JSON `{"error": "..."}` → its (stringified) value;
  ///   2. otherwise the raw body, truncated to 200 chars so a 502 HTML page
  ///      cannot flood the UI;
  ///   3. otherwise the HTTP reason phrase;
  ///   4. otherwise a generic placeholder.
  String _extractServerError(int status, String? reasonPhrase, String body) {
    final bodyText = body.trim();
    if (bodyText.isNotEmpty) {
      try {
        final decoded = jsonDecode(bodyText);
        if (decoded is Map<String, dynamic>) {
          final errorValue = decoded['error']?.toString().trim();
          if (errorValue != null && errorValue.isNotEmpty) {
            return errorValue;
          }
        }
      } on FormatException catch (e) {
        debugPrint('MarketplaceOpenApi error-body JSON decode failed: $e');
      }
      return bodyText.length > 200
          ? '${bodyText.substring(0, 200)}...'
          : bodyText;
    }
    final reason = reasonPhrase?.trim();
    if (reason != null && reason.isNotEmpty) return reason;
    return 'Unknown error from server';
  }

  /// Decodes a marketplace envelope `{success, data, error}` response,
  /// enforcing the wire contract uniformly across every endpoint (W6-3).
  ///
  /// Pipeline:
  ///   1. non-2xx → throws [Exception] carrying `HTTP {status}` + a tolerantly
  ///      extracted server error (non-JSON / empty bodies handled — never a
  ///      [FormatException] that masks the status). When [statusErrorPrefix] is
  ///      given the message is `"$prefix (HTTP $status): $detail"` to preserve
  ///      endpoint-specific messaging (upload / account CRUD).
  ///   2. 2xx → `jsonDecode`s the body. A non-JSON 2xx body propagates as a
  ///      [FormatException] (the caller's "the server sent garbage on a success
  ///      code" signal — intentionally NOT swallowed).
  ///   3. decoded but `success != true` (including omitted / null / non-bool)
  ///      → throws [Exception] with the envelope `error`, never a [TypeError].
  ///   4. `success: true` → returns the decoded envelope map.
  ///
  /// [label] seeds the fallback messages (e.g. "Search failed").
  /// [failureFallback] overrides the success:`false` fallback verbatim when an
  /// endpoint has its own canonical wording.
  Map<String, dynamic> _decodeSuccessResponse(
    http.Response response, {
    String? label,
    String? statusErrorPrefix,
    String? failureFallback,
  }) {
    final status = response.statusCode;
    if (status < 200 || status > 299) {
      final detail =
          _extractServerError(status, response.reasonPhrase, response.body);
      throw Exception(statusErrorPrefix != null
          ? '$statusErrorPrefix (HTTP $status): $detail'
          : 'HTTP $status: $detail');
    }
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('${label ?? 'Response'} is not a valid JSON object');
    }
    if (decoded['success'] != true) {
      final error = decoded['error']?.toString();
      final message = (error != null && error.isNotEmpty)
          ? error
          : (failureFallback ??
              (label != null ? '$label failed' : 'Request failed'));
      throw Exception(message);
    }
    return decoded;
  }

  /// Extracts and type-checks the `data` field of a decoded envelope (W6-3).
  /// Throws a clear [Exception] (not a silent [TypeError]) when `data` is
  /// absent or the wrong shape. [T] is the expected runtime type —
  /// `Map<String, dynamic>` (→ "object") or `List` (→ "list").
  T _decodeDataField<T>(Map<String, dynamic> envelope, {required String label}) {
    final data = envelope['data'];
    if (data is T) return data;
    // Derive a human-readable kind without comparing generic type literals
    // (which the parser would misread). Sentinel instances + `is T` is
    // unambiguous.
    final kind = <dynamic>[] is T
        ? 'list'
        : <String, dynamic>{} is T
            ? 'object'
            : 'value';
    throw Exception(data == null
        ? '$label response missing data field'
        : '$label response data is not a valid $kind');
  }
}

// Data classes for the open API response
class MarketplaceSearchResult {
  final List<MarketplaceScript> scripts;
  final int total;
  final bool hasMore;
  final int offset;
  final int limit;

  MarketplaceSearchResult({
    required this.scripts,
    required this.total,
    required this.hasMore,
    required this.offset,
    required this.limit,
  });

  @override
  String toString() {
    return 'MarketplaceSearchResult{total: $total, scripts: ${scripts.length}, hasMore: $hasMore}';
  }
}

class MarketplaceStats {
  final int totalScripts;
  final int totalAuthors;
  final int totalDownloads;
  final double averageRating;

  MarketplaceStats({
    required this.totalScripts,
    required this.totalAuthors,
    required this.totalDownloads,
    required this.averageRating,
  });

  factory MarketplaceStats.fromJson(Map<String, dynamic> json) {
    return MarketplaceStats(
      totalScripts: json['totalScripts'] ?? json['total_scripts'] ?? 0,
      totalAuthors: json['totalAuthors'] ?? json['total_authors'] ?? 0,
      totalDownloads: json['totalDownloads'] ?? json['total_downloads'] ?? 0,
      averageRating:
          (json['averageRating'] ?? json['average_rating'] ?? 0.0).toDouble(),
    );
  }
}

class ScriptValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  ScriptValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  factory ScriptValidationResult.fromJson(Map<String, dynamic> json) {
    return ScriptValidationResult(
      isValid: json['is_valid'] ?? false,
      errors: List<String>.from(json['errors'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
    );
  }
}

class ScriptVersion {
  final String version;
  final String? changelog;
  final DateTime createdAt;
  final int downloads;
  final bool isLatest;

  const ScriptVersion({
    required this.version,
    this.changelog,
    required this.createdAt,
    this.downloads = 0,
    this.isLatest = false,
  });

  factory ScriptVersion.fromJson(Map<String, dynamic> json) {
    return ScriptVersion(
      version: json['version'] as String? ?? '',
      changelog: json['changelog'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ??
              json['created_at'] as String? ??
              '') ??
          DateTime.now(),
      downloads: json['downloads'] as int? ?? 0,
      isLatest:
          json['isLatest'] as bool? ?? json['is_latest'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'changelog': changelog,
        'createdAt': createdAt.toIso8601String(),
        'downloads': downloads,
        'isLatest': isLatest,
      };

  @override
  String toString() => 'ScriptVersion{version: $version, latest: $isLatest}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptVersion &&
          runtimeType == other.runtimeType &&
          version == other.version;

  @override
  int get hashCode => version.hashCode;
}

/// Public ICPay client config (browser-safe). Mirrors the backend
/// `GET /api/v1/payments/icpay/config` data payload — camelCase on the wire.
/// The secret key never leaves the server; this only carries the publishable
/// key the client uses to create payment intents against ICPay's API.
class IcpayClientConfig {
  final String publishableKey;
  final String shortcode;
  final String apiUrl;

  const IcpayClientConfig({
    required this.publishableKey,
    required this.shortcode,
    required this.apiUrl,
  });

  factory IcpayClientConfig.fromJson(Map<String, dynamic> json,
      {required String rawBody}) {
    // The token shortcode is the canonical token id used to charge callers.
    // It MUST come from the backend payments config (single source: the
    // server's ICPAY_TOKEN_SHORTCODE); never silently shadowed by a client-side
    // literal fallback. If it is absent the server config is incomplete — fail
    // loudly (the fully-unconfigured case already surfaces as HTTP 503 in
    // getIcpayConfig).
    final shortcode = json['shortcode'] as String?;
    if (shortcode == null || shortcode.isEmpty) {
      throw PaymentsConfigMalformedException(
        'ICPay config is missing the required "shortcode" field — the backend '
            'payments config is incomplete',
        rawBody,
      );
    }
    // The ICPay API host MUST come from the backend (AUD-8: no duplicated
    // client-side literal fallback). If absent the server config is incomplete
    // — fail loudly rather than silently pointing at a stale host.
    final apiUrl = json['apiUrl'] as String?;
    if (apiUrl == null || apiUrl.isEmpty) {
      throw PaymentsConfigMalformedException(
        'ICPay config is missing the required "apiUrl" field — the backend '
            'payments config is incomplete',
        rawBody,
      );
    }
    return IcpayClientConfig(
      publishableKey: json['publishableKey'] as String? ?? '',
      shortcode: shortcode,
      apiUrl: apiUrl,
    );
  }

  @override
  String toString() =>
      'IcpayClientConfig{shortcode: $shortcode, apiUrl: $apiUrl, '
      'hasKey: ${publishableKey.isNotEmpty}}';
}

/// Lightweight browse-time preview of a script (UX-6).
/// Mirrors the backend `GET /api/v1/scripts/:id/preview` payload: a CAPPED
/// excerpt of the source plus browse-relevant metadata. Deliberately has no
/// `bundle` field — the full source is never carried here (and for paid
/// scripts it is never sent over the wire at all).
class ScriptPreview {
  final String id;
  final String description;
  final String version;
  final double price;
  final String language;
  final String preview;
  final bool previewTruncated;
  final int totalLines;

  const ScriptPreview({
    required this.id,
    required this.description,
    required this.version,
    required this.price,
    required this.language,
    required this.preview,
    required this.previewTruncated,
    required this.totalLines,
  });

  factory ScriptPreview.fromJson(Map<String, dynamic> json) {
    return ScriptPreview(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      // UXR5-2: language is DETECTED from the bundle by the backend. Default
      // to 'unknown' (→ no badge) — NEVER fabricate 'typescript' for content
      // we haven't inspected.
      language: json['language'] as String? ?? 'unknown',
      preview: json['preview'] as String? ?? '',
      previewTruncated: json['previewTruncated'] as bool? ?? false,
      totalLines: json['totalLines'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'ScriptPreview{id: $id, version: $version, price: $price, '
      'lines: $totalLines, truncated: $previewTruncated}';
}
