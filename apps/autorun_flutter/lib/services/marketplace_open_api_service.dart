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

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Search failed');
      }

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

      if (response.statusCode > 299) {
        if (response.statusCode == 404) {
          throw Exception('Script not found');
        }
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get script details');
      }

      final data = responseData['data'];
      if (data == null) {
        throw Exception('Script details response missing data field');
      }
      if (data is! Map<String, dynamic>) {
        throw Exception('Script details response data is not a valid object');
      }
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
      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get script preview');
      }

      final data = responseData['data'];
      if (data == null || data is! Map<String, dynamic>) {
        throw Exception('Script preview response missing data field');
      }
      return ScriptPreview.fromJson(data);
    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script preview failed: $e');
      rethrow;
    }
  }

  // Get featured scripts
  Future<List<MarketplaceScript>> getFeaturedScripts({int limit = 10}) async {
    final response = await _httpClient
        .get(Uri.parse('${ApiRoutes.scriptsFeatured}?limit=$limit'))
        .timeout(AppDurations.browseTimeout);

    if (response.statusCode > 299) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    final responseData = jsonDecode(response.body);
    if (!responseData['success']) {
      throw Exception(
          responseData['error'] ?? 'Failed to get featured scripts');
    }

    final data = responseData['data'] as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map((script) => MarketplaceScript.fromJson(script))
        .toList();
  }

  // Get trending scripts
  Future<List<MarketplaceScript>> getTrendingScripts({int limit = 10}) async {
    final response = await _httpClient
        .get(Uri.parse('${ApiRoutes.scriptsTrending}?limit=$limit'))
        .timeout(AppDurations.browseTimeout);

    if (response.statusCode > 299) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    final responseData = jsonDecode(response.body);
    if (!responseData['success']) {
      throw Exception(
          responseData['error'] ?? 'Failed to get trending scripts');
    }

    final data = responseData['data'] as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map((script) => MarketplaceScript.fromJson(script))
        .toList();
  }

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

      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get scripts by category');
      }

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

      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get script reviews');
      }

      final data = responseData['data'] as List;
      return data
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
      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (responseData is! Map<String, dynamic> ||
          responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to load ICPay config');
      }
      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('ICPay config response missing data field');
      }
      return IcpayClientConfig.fromJson(data);
    } on PaymentsNotConfiguredException {
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
      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get script version');
      }

      final data = responseData['data'];
      if (data == null || data is! Map<String, dynamic>) {
        throw Exception('Script version response missing data field');
      }
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
      if (response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(
            responseData['error'] ?? 'Failed to get script versions');
      }

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

    if (response.statusCode > 299) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    final responseData = jsonDecode(response.body);
    if (!responseData['success']) {
      throw Exception(
          responseData['error'] ?? 'Failed to get marketplace stats');
    }

    final data = responseData['data'];
    return MarketplaceStats.fromJson(data);
  }

  // Get canister compatibility info
  Future<List<MarketplaceScript>> getCompatibleScripts(
    List<String> canisterIds, {
    int limit = 50,
  }) async {
    try {
      // Validate all canister IDs
      for (final canisterId in canisterIds) {
        if (!_isValidCanisterId(canisterId)) {
          throw Exception('Invalid canister ID format: $canisterId');
        }
      }

      final response = await _httpClient
          .post(
            Uri.parse(ApiRoutes.scriptsCompatible),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'canisterId': canisterIds
                  .first, // Cloudflare endpoint expects single canister ID
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
      if (!responseData['success']) {
        final errorDetail = responseData['error']?.toString();
        throw Exception(
          _buildUploadErrorMessage(
            statusCode: response.statusCode,
            reasonPhrase: response.reasonPhrase,
            serverError: errorDetail,
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
    String? detail;

    if (serverError != null) {
      final serverText = serverError.toString().trim();
      if (serverText.isNotEmpty) {
        detail = serverText;
      }
    }

    if (detail == null && responseBody != null) {
      final bodyText = responseBody.trim();
      if (bodyText.isNotEmpty) {
        try {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            final errorValue = decoded['error']?.toString().trim();
            if (errorValue != null && errorValue.isNotEmpty) {
              detail = errorValue;
            }
          }
        } on FormatException catch (e) {
          debugPrint('MarketplaceOpenApi error-body JSON decode failed: $e');
        }

        detail ??= bodyText.length > 200
            ? '${bodyText.substring(0, 200)}...'
            : bodyText;
      }
    }

    detail ??= reasonPhrase?.trim().isNotEmpty == true
        ? reasonPhrase!.trim()
        : 'Unknown error from server';

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

      if (response.statusCode > 299) {
        final responseData = jsonDecode(response.body);
        throw Exception(
            responseData['error'] ?? 'Update failed: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Update failed');
      }

      final data = responseData['data'];
      if (data == null) {
        throw Exception('Update script response missing data field');
      }
      if (data is! Map<String, dynamic>) {
        throw Exception('Update script response data is not a valid object');
      }
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

      if (response.statusCode > 299) {
        final responseData = jsonDecode(response.body);
        throw Exception(
            responseData['error'] ?? 'Delete failed: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Delete failed');
      }

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

      if (response.statusCode < 200 || response.statusCode > 299) {
        final String detail = response.body.isNotEmpty
            ? _extractErrorMessage(response.body)
            : response.reasonPhrase ?? 'Unknown failure';
        throw Exception(
            'Account registration failed (HTTP ${response.statusCode}): $detail');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Account registration response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Failed to register account');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Account registration response missing data');
      }
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
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Account response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Failed to load account');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Account response missing data field');
      }
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
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Account by public key response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(
            decoded['error'] ?? 'Failed to load account by public key');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Account by public key response missing data field');
      }
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

      if (response.statusCode < 200 || response.statusCode > 299) {
        final String detail = response.body.isNotEmpty
            ? _extractErrorMessage(response.body)
            : response.reasonPhrase ?? 'Unknown failure';
        throw Exception(
            'Add key failed (HTTP ${response.statusCode}): $detail');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Add key response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Failed to add key');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Add key response missing data');
      }
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

      if (response.statusCode < 200 || response.statusCode > 299) {
        final String detail = response.body.isNotEmpty
            ? _extractErrorMessage(response.body)
            : response.reasonPhrase ?? 'Unknown failure';
        throw Exception(
            'Remove key failed (HTTP ${response.statusCode}): $detail');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Remove key response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Failed to remove key');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Remove key response missing data');
      }
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

      if (response.statusCode < 200 || response.statusCode > 299) {
        final String detail = response.body.isNotEmpty
            ? _extractErrorMessage(response.body)
            : response.reasonPhrase ?? 'Unknown failure';
        throw Exception(
            'Update account failed (HTTP ${response.statusCode}): $detail');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Update account response malformed');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Failed to update account');
      }
      final Map<String, dynamic>? data =
          decoded['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Update account response missing data');
      }
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

  /// Extract error message from response body
  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
        return decoded['error'] as String;
      }
      return body;
    } on FormatException catch (e) {
      debugPrint('MarketplaceOpenApi._extractErrorMessage decode failed: $e');
      return body;
    }
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

  factory IcpayClientConfig.fromJson(Map<String, dynamic> json) {
    // The token shortcode is the canonical token id used to charge callers.
    // It MUST come from the backend payments config (single source: the
    // server's ICPAY_TOKEN_SHORTCODE); never silently shadowed by a client-side
    // literal fallback. If it is absent the server config is incomplete — fail
    // loudly (the fully-unconfigured case already surfaces as HTTP 503 in
    // getIcpayConfig).
    final shortcode = json['shortcode'] as String?;
    if (shortcode == null || shortcode.isEmpty) {
      throw FormatException(
        'ICPay config is missing the required "shortcode" field — the backend '
        'payments config is incomplete.',
      );
    }
    return IcpayClientConfig(
      publishableKey: json['publishableKey'] as String? ?? '',
      shortcode: shortcode,
      apiUrl: json['apiUrl'] as String? ?? 'https://api.icpay.org',
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
      language: json['language'] as String? ?? 'typescript',
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
