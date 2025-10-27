import 'dart:async';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';

// Mock implementation of MarketplaceOpenApiService for testing
class MockMarketplaceOpenApiService {
  final Map<String, MarketplaceScript> _mockScripts = {};
  final Map<String, ScriptRecord> _mockScriptRecords = {};
  int _scriptIdCounter = 1;

  // Add mock test data
  void addMockTestData() {
    // Add some test scripts
    final testScripts = [
      MarketplaceScript(
        id: 'test-script-1',
        title: 'Test Script 1',
        description: 'A test script for development',
        category: 'Development',
        tags: const ['test', 'development'],
        authorId: 'test-author-1',
        authorName: 'Test Author',
        price: 0.0,
        currency: 'ICP',
        downloads: 10,
        rating: 4.5,
        reviewCount: 2,
        luaSource: '-- Test script 1\nfunction init() return {}, {} end\nfunction view(state) return {type="text", text="Hello World"} end\nfunction update(msg, state) return state, {} end',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        version: '1.0.0',
      ),
      MarketplaceScript(
        id: 'test-script-2',
        title: 'Another Test Script',
        description: 'Another test script for testing',
        category: 'Testing',
        tags: const ['test', 'testing'],
        authorId: 'test-author-2',
        authorName: 'Another Test Author',
        price: 1.0,
        currency: 'ICP',
        downloads: 5,
        rating: 3.0,
        reviewCount: 1,
        luaSource: '-- Test script 2\nfunction init() return {}, {} end\nfunction view(state) return {type="text", text="Another test"} end\nfunction update(msg, state) return state, {} end',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        version: '1.0.0',
      ),
    ];

    for (final script in testScripts) {
      _mockScripts[script.id] = script;
    }
  }

  // Clear mock data
  void clearMockData() {
    _mockScripts.clear();
    _mockScriptRecords.clear();
    _scriptIdCounter = 1;
  }

  // Search scripts
  Future<MarketplaceSearchResult> searchScripts({
    String? query,
    String? category,
    List<String>? tags,
    String? canisterId,
    double? minRating,
    double? maxPrice,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
    int limit = 20,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay

    var scripts = _mockScripts.values.toList();

    // Apply filters
    if (query != null && query.isNotEmpty) {
      scripts = scripts.where((script) =>
        script.title.toLowerCase().contains(query.toLowerCase()) ||
        script.description.toLowerCase().contains(query.toLowerCase())
      ).toList();
    }

    if (category != null && category.isNotEmpty) {
      scripts = scripts.where((script) => script.category == category).toList();
    }

    if (minRating != null) {
      scripts = scripts.where((script) => script.rating >= minRating).toList();
    }

    if (maxPrice != null) {
      scripts = scripts.where((script) => script.price <= maxPrice).toList();
    }

    if (tags != null && tags.isNotEmpty) {
      scripts = scripts.where((script) {
        return tags.any((tag) => script.tags.contains(tag));
      }).toList();
    }

    // Apply sorting
    switch (sortBy) {
      case 'title':
        scripts.sort((a, b) => sortOrder == 'asc' 
          ? a.title.compareTo(b.title) 
          : b.title.compareTo(a.title));
        break;
      case 'rating':
        scripts.sort((a, b) => sortOrder == 'asc' 
          ? a.rating.compareTo(b.rating) 
          : b.rating.compareTo(a.rating));
        break;
      case 'downloads':
        scripts.sort((a, b) => sortOrder == 'asc' 
          ? a.downloads.compareTo(b.downloads) 
          : b.downloads.compareTo(a.downloads));
        break;
      case 'createdAt':
      default:
        scripts.sort((a, b) => sortOrder == 'asc' 
          ? a.createdAt.compareTo(b.createdAt) 
          : b.createdAt.compareTo(a.createdAt));
        break;
    }

    // Apply pagination with validation
    final total = scripts.length;
    final validLimit = limit < 0 ? 20 : limit; // Default to 20 for invalid limit
    final validOffset = offset < 0 ? 0 : offset; // Default to 0 for invalid offset
    final hasMore = validOffset + validLimit < total;
    final paginatedScripts = scripts.skip(validOffset).take(validLimit).toList();

    return MarketplaceSearchResult(
      scripts: paginatedScripts,
      total: total,
      hasMore: hasMore,
      offset: offset,
      limit: limit,
    );
  }

  // Get script by ID
  Future<MarketplaceScript?> getScriptById(String scriptId) async {
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate network delay
    return _mockScripts[scriptId];
  }

  // Upload script (returns script ID)
  Future<String> uploadScript(ScriptRecord scriptRecord) async {
    await Future.delayed(const Duration(milliseconds: 200)); // Simulate network delay

    final scriptId = 'mock_script_${_scriptIdCounter++}';
    
    // Create MarketplaceScript from ScriptRecord
    final marketplaceScript = MarketplaceScript(
      id: scriptId,
      title: scriptRecord.title,
      description: scriptRecord.metadata['description'] ?? '',
      category: scriptRecord.metadata['category'] ?? 'Uncategorized',
      tags: List<String>.from(scriptRecord.metadata['tags'] ?? []),
      authorId: 'mock_author_id',
      authorName: scriptRecord.metadata['authorName'] ?? 'Mock Author',
      price: (scriptRecord.metadata['price'] as num?)?.toDouble() ?? 0.0,
      currency: 'ICP',
      downloads: 0,
      rating: 0.0,
      reviewCount: 0,
      luaSource: scriptRecord.luaSource,
      createdAt: scriptRecord.createdAt,
      updatedAt: scriptRecord.updatedAt,
      version: scriptRecord.metadata['version'] as String? ?? '1.0.0',
      isPublic: scriptRecord.metadata['isPublic'] as bool? ?? true,
    );

    _mockScripts[scriptId] = marketplaceScript;
    _mockScriptRecords[scriptId] = scriptRecord;

    return scriptId;
  }

  // Update script
  Future<bool> updateScript(String scriptId, ScriptRecord updatedScript) async {
    await Future.delayed(const Duration(milliseconds: 150)); // Simulate network delay

    if (!_mockScripts.containsKey(scriptId)) {
      return false;
    }

    final existingScript = _mockScripts[scriptId]!;
    final updatedMarketplaceScript = MarketplaceScript(
      id: scriptId,
      title: updatedScript.title,
      description: updatedScript.metadata['description'] ?? existingScript.description,
      category: updatedScript.metadata['category'] ?? existingScript.category,
      tags: List<String>.from(updatedScript.metadata['tags'] ?? existingScript.tags),
      authorId: existingScript.authorId,
      authorName: updatedScript.metadata['authorName'] ?? existingScript.authorName,
      price: (updatedScript.metadata['price'] as num?)?.toDouble() ?? existingScript.price,
      currency: existingScript.currency,
      downloads: existingScript.downloads,
      rating: existingScript.rating,
      reviewCount: existingScript.reviewCount,
      luaSource: updatedScript.luaSource,
      createdAt: existingScript.createdAt,
      updatedAt: updatedScript.updatedAt,
      version: updatedScript.metadata['version'] ?? existingScript.version,
      isPublic: updatedScript.metadata['isPublic'] as bool? ?? existingScript.isPublic,
    );

    _mockScripts[scriptId] = updatedMarketplaceScript;
    _mockScriptRecords[scriptId] = updatedScript;

    return true;
  }

  // Delete script
  Future<bool> deleteScript(String scriptId) async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
    _mockScripts.remove(scriptId);
    _mockScriptRecords.remove(scriptId);
    return true; // Always succeed for mock
  }

  // Get user scripts
  Future<List<MarketplaceScript>> getUserScripts() async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
    return _mockScripts.values.where((script) => 
      script.authorId == 'mock_author_id'
    ).toList();
  }

  // Get marketplace stats
  Future<Map<String, dynamic>> getMarketplaceStats() async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
    
    final scripts = _mockScripts.values.toList();
    final totalDownloads = scripts.fold<int>(0, (sum, script) => sum + script.downloads);
    final averageRating = scripts.isEmpty ? 0.0 : 
      scripts.fold<double>(0, (sum, script) => sum + script.rating) / scripts.length;
    
    final categories = scripts.map((script) => script.category).toSet().toList();

    return {
      'totalScripts': scripts.length,
      'totalDownloads': totalDownloads,
      'categories': categories,
      'averageRating': averageRating,
    };
  }
}

// Mock classes for search result and other data structures
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