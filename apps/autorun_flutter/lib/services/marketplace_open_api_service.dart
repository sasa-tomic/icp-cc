import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/marketplace_script.dart';
import '../models/purchase_record.dart';

// Flag to control debug output in tests
bool suppressDebugOutput = false;

class MarketplaceOpenApiService {
  static final MarketplaceOpenApiService _instance = MarketplaceOpenApiService._internal();
  factory MarketplaceOpenApiService() => _instance;
  MarketplaceOpenApiService._internal();

  final String _baseUrl = 'http://localhost:3000/v1'; // Local API server URL
  final Duration _timeout = const Duration(seconds: 30);
  static const int defaultSearchLimit = 20;

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
      final uri = Uri.parse('$_baseUrl/scripts/search').replace(queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (category != null) 'category': category,
        if (canisterId != null) 'canister_id': canisterId,
        if (minRating != null) 'min_rating': minRating.toString(),
        if (maxPrice != null) 'max_price': maxPrice.toString(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
        'limit': limit.toString(),
        'offset': offset.toString(),
      });

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body);
      final scripts = (data['scripts'] as List)
          .map((script) => MarketplaceScript.fromJson(script))
          .toList();

      return MarketplaceSearchResult(
        scripts: scripts,
        total: data['total'] ?? 0,
        hasMore: (data['hasMore'] ?? false) as bool,
        offset: offset,
        limit: limit,
      );

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Search scripts failed: $e');
      rethrow;
    }
  }

  // Get script details by ID
  Future<MarketplaceScript> getScriptDetails(String scriptId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/scripts/$scriptId'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          throw Exception('Script not found');
        }
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body);
      return MarketplaceScript.fromJson(data);

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script details failed: $e');
      rethrow;
    }
  }

  // Get featured scripts
  Future<List<MarketplaceScript>> getFeaturedScripts({int limit = 10}) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/scripts/featured?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body) as List;
      return data.map((script) => MarketplaceScript.fromJson(script)).toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get featured scripts failed: $e');
      return [];
    }
  }

  // Get trending scripts
  Future<List<MarketplaceScript>> getTrendingScripts({int limit = 10}) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/scripts/trending?limit=$limit'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body) as List;
      return data.map((script) => MarketplaceScript.fromJson(script)).toList();

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

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body) as List;
      return data.map((script) => MarketplaceScript.fromJson(script)).toList();

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

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body) as List;
      return data.map((review) => ScriptReview.fromJson(review)).toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get script reviews failed: $e');
      rethrow;
    }
  }

  // Get marketplace categories
  List<String> getCategories() {
    return const [
      'All',
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
    final regex = RegExp(r'^[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{3}$');
    return regex.hasMatch(canisterId);
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

      if (!script.isPublic || !script.isApproved) {
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
      final response = await http
          .get(Uri.parse('$_baseUrl/stats'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body);
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

      final uri = Uri.parse('$_baseUrl/scripts/compatible').replace(queryParameters: {
        'canister_ids': canisterIds.join(','),
        'limit': limit.toString(),
      });

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body) as List;
      return data.map((script) => MarketplaceScript.fromJson(script)).toList();

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Get compatible scripts failed: $e');
      rethrow;
    }
  }

  // Validate script syntax (service that checks if Lua code is valid)
  Future<ScriptValidationResult> validateScript(String luaSource) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/scripts/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'lua_source': luaSource}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body);
      return ScriptValidationResult.fromJson(data);

    } catch (e) {
      if (!suppressDebugOutput) debugPrint('Validate script failed: $e');
      return ScriptValidationResult(
        isValid: false,
        errors: [e.toString()],
      );
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
      totalScripts: json['total_scripts'] ?? 0,
      totalAuthors: json['total_authors'] ?? 0,
      totalDownloads: json['total_downloads'] ?? 0,
      averageRating: (json['average_rating'] ?? 0.0).toDouble(),
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