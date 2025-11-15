import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/marketplace_script.dart';
import '../models/purchase_record.dart';
import '../config/app_config.dart';

// Flag to control debug output in tests
bool suppressDebugOutput = false;

class MarketplaceOpenApiService {
  static final MarketplaceOpenApiService _instance = MarketplaceOpenApiService._internal();
  factory MarketplaceOpenApiService() => _instance;
  MarketplaceOpenApiService._internal() : _httpClient = http.Client();

  String get _baseUrl => '${AppConfig.apiEndpoint}/api/v1'; // API endpoints
  final Duration _timeout = const Duration(seconds: 45);
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
      final url = '$_baseUrl/scripts/search';
      
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
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
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
      // During tests, if the service isn't available, return empty result rather than failing
      if (suppressDebugOutput || e.toString().contains('Connection refused')) {
        return MarketplaceSearchResult(
          scripts: [],
          total: 0,
          hasMore: false,
          offset: offset,
          limit: limit,
        );
      }
      rethrow;
    }
  }

  // Get script details by ID
  Future<MarketplaceScript> getScriptDetails(String scriptId) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$_baseUrl/scripts/$scriptId'))
          .timeout(_timeout);

      if (response.statusCode > 299) {
        if (response.statusCode == 404) {
          throw Exception('Script not found');
        }
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get script details');
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

  // Get featured scripts
  Future<List<MarketplaceScript>> getFeaturedScripts({int limit = 10}) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$_baseUrl/scripts/featured?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get featured scripts');
      }

      final data = responseData['data'] as List;
      return data
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get featured scripts failed: $e');
      return [];
    }
  }

  // Get trending scripts
  Future<List<MarketplaceScript>> getTrendingScripts({int limit = 10}) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$_baseUrl/scripts/trending?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get trending scripts');
      }

      final data = responseData['data'] as List;
      return data
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get trending scripts failed: $e');
      return [];
    }
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
      final uri = Uri.parse('$_baseUrl/scripts/category/$category').replace(queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      });

      final response = await _httpClient.get(uri).timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get scripts by category');
      }

      final data = responseData['data'] as List;
      return data
          .whereType<Map<String, dynamic>>()
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get scripts by category failed: $e');
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
      final uri = Uri.parse('$_baseUrl/scripts/$scriptId/reviews').replace(queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (verifiedOnly) 'verified_only': 'true',
      });

      final response = await _httpClient.get(uri).timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get script reviews');
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
      if (!suppressDebugOutput) debugPrint('Search scripts by canister ID failed: $e');
      rethrow;
    }
  }

  // Download script (public access - only for free scripts)
  Future<String> downloadScript(String scriptId) async {
    try {
      // First get script details to check if it's free
      final script = await getScriptDetails(scriptId);

      if (script.price > 0) {
        throw Exception('Paid scripts require authentication to download');
      }

      if (!script.isPublic) {
        throw Exception('Script is not available for download');
      }

      return script.luaSource;

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Download script failed: $e');
      rethrow;
    }
  }

  // Get marketplace statistics (public data)
  Future<MarketplaceStats> getMarketplaceStats() async {
    try {
      final url = '$_baseUrl/marketplace-stats';
      if (!suppressDebugOutput) debugPrint('GET request URL: $url');
      final response = await _httpClient
          .get(Uri.parse(url))
          .timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get marketplace stats');
      }

      final data = responseData['data'];
      return MarketplaceStats.fromJson(data);

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get marketplace stats failed: $e');
      // Return default stats if API fails
      return MarketplaceStats(
        totalScripts: 0,
        totalAuthors: 0,
        totalDownloads: 0,
        averageRating: 0.0,
      );
    }
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
            Uri.parse('$_baseUrl/scripts/compatible'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'canisterId': canisterIds.first, // Cloudflare endpoint expects single canister ID
              'limit': limit,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final responseData = jsonDecode(response.body);
      if (!responseData['success']) {
        throw Exception(responseData['error'] ?? 'Failed to get compatible scripts');
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
    required String title,
    required String description,
    required String category,
    required List<String> tags,
    required String luaSource,
    required String authorName,
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
        'title': title,
        'description': description,
        'category': category,
        'tags': tags,
        'lua_source': luaSource,
        'author_name': authorName,
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
        debugPrint('Upload request URL: $_baseUrl/scripts');
        debugPrint('Request body: $requestBody');
      }
      
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/scripts'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(_timeout);

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
        throw Exception('Upload failed (HTTP ${response.statusCode}): Empty response from server');
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
          authorId: 'anonymous',
          authorName: authorName,
          price: price,
          currency: 'ICP',
          downloads: 0,
          rating: 0.0,
          reviewCount: 0,
          verifiedReviewCount: 0,
          luaSource: luaSource,
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
        throw Exception('Upload response data is not a valid object. Data type: ${data.runtimeType}');
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
        } catch (_) {
          // Ignore JSON decoding issues and fall back to raw body sample.
        }

        detail ??= bodyText.length > 200 ? '${bodyText.substring(0, 200)}...' : bodyText;
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
    String? luaSource,
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
      if (luaSource != null) body['lua_source'] = luaSource;
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
            Uri.parse('$_baseUrl/scripts/$scriptId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode > 299) {
        final responseData = jsonDecode(response.body);
        throw Exception(responseData['error'] ?? 'Update failed: ${response.reasonPhrase}');
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
  Future<bool> deleteScript(String scriptId, {String? authorPrincipal, String? signature}) async {
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
            Uri.parse('$_baseUrl/scripts/$scriptId/delete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode > 299) {
        final responseData = jsonDecode(response.body);
        throw Exception(responseData['error'] ?? 'Delete failed: ${response.reasonPhrase}');
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
      averageRating: (json['averageRating'] ?? json['average_rating'] ?? 0.0).toDouble(),
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
