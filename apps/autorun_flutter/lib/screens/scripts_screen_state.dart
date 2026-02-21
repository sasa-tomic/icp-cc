import 'package:flutter/foundation.dart';
import '../models/script_list_item.dart';
import '../models/script_record.dart';
import '../models/marketplace_script.dart';

/// Enumeration of all possible view states for the ScriptsScreen.
/// This provides a single source of truth for what should be displayed.
enum ScriptsView {
  /// Initial loading state - showing spinner
  loading,

  /// Content is available to display
  content,

  /// Search results are being shown
  searchResults,

  /// Search returned no results
  searchEmpty,

  /// No content at all (local and marketplace both empty)
  empty,

  /// Downloaded filter active but no downloads
  emptyDownloaded,

  /// Favorites filter active but no favorites
  emptyFavorites,
}

/// Encapsulates all state management for ScriptsScreen.
///
/// This class provides a clean separation between business logic and UI,
/// using a state machine approach to determine what view should be shown.
///
/// Key principle: New users should see marketplace content, not empty states.
/// The loading state persists until we have content to show OR both sources
/// confirm they are empty.
class ScriptsViewMachine extends ChangeNotifier {
  // ============================================
  // Loading State
  // ============================================

  bool _isLoadingLocal = true;
  bool _isLoadingMarketplace = true;
  bool _isSearching = false;
  bool _isLoadingMore = false;

  bool get isLoadingLocal => _isLoadingLocal;
  bool get isLoadingMarketplace => _isLoadingMarketplace;
  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;

  /// True if any loading operation is in progress
  bool get isAnyLoading =>
      _isLoadingLocal || _isLoadingMarketplace || _isSearching;

  // ============================================
  // Content State
  // ============================================

  List<ScriptRecord> _localScripts = [];
  List<MarketplaceScript> _marketplaceScripts = [];
  Set<String> _downloadedScriptIds = {};
  Set<String> _favoriteScriptIds = {};

  List<ScriptRecord> get localScripts => List.unmodifiable(_localScripts);
  List<MarketplaceScript> get marketplaceScripts =>
      List.unmodifiable(_marketplaceScripts);
  Set<String> get downloadedScriptIds => Set.unmodifiable(_downloadedScriptIds);
  Set<String> get favoriteScriptIds => Set.unmodifiable(_favoriteScriptIds);

  // ============================================
  // Filter State
  // ============================================

  String _selectedCategory = 'All';
  ScriptSortOption _sortOption = ScriptSortOption.lastRun;
  bool _sortAscending = false;
  bool _showDownloadedOnly = false;
  bool _showFavoritesOnly = false;
  String _searchQuery = '';

  String get selectedCategory => _selectedCategory;
  ScriptSortOption get sortOption => _sortOption;
  bool get sortAscending => _sortAscending;
  bool get showDownloadedOnly => _showDownloadedOnly;
  bool get showFavoritesOnly => _showFavoritesOnly;
  String get searchQuery => _searchQuery;

  /// Returns count of non-default filter settings
  int get activeFilterCount {
    int count = 0;
    if (_selectedCategory != 'All') count++;
    if (_sortOption != ScriptSortOption.lastRun) count++;
    if (_showDownloadedOnly) count++;
    if (_showFavoritesOnly) count++;
    return count;
  }

  // ============================================
  // Computed View State
  // ============================================

  /// Determines the current view based on state.
  /// This is the single source of truth for what to display.
  ScriptsView get currentView {
    // If we're searching and still loading, show loading
    if (_isSearching) {
      return ScriptsView.loading;
    }

    // Get filtered items to determine what we'd show
    final filteredItems = _getFilteredItemsInternal();

    // If loading AND no content yet, show loading
    // This is critical: don't show empty state while loading
    if (isAnyLoading && filteredItems.isEmpty) {
      return ScriptsView.loading;
    }

    // Done loading, determine based on filters and content
    if (filteredItems.isEmpty) {
      // Check which filter is causing empty results
      if (_showDownloadedOnly) {
        return ScriptsView.emptyDownloaded;
      }
      if (_showFavoritesOnly) {
        return ScriptsView.emptyFavorites;
      }
      // Search with no results
      if (_searchQuery.isNotEmpty) {
        return ScriptsView.searchEmpty;
      }
      // Truly empty - no local or marketplace content
      return ScriptsView.empty;
    }

    // We have content
    if (_searchQuery.isNotEmpty) {
      return ScriptsView.searchResults;
    }

    return ScriptsView.content;
  }

  // ============================================
  // Setters (with notification)
  // ============================================

  void setLocalLoading(bool value) {
    if (_isLoadingLocal != value) {
      _isLoadingLocal = value;
      notifyListeners();
    }
  }

  void setMarketplaceLoading(bool value) {
    if (_isLoadingMarketplace != value) {
      _isLoadingMarketplace = value;
      notifyListeners();
    }
  }

  void setSearching(bool value) {
    if (_isSearching != value) {
      _isSearching = value;
      notifyListeners();
    }
  }

  void setLoadingMore(bool value) {
    if (_isLoadingMore != value) {
      _isLoadingMore = value;
      notifyListeners();
    }
  }

  void setLocalScripts(List<ScriptRecord> scripts) {
    _localScripts = List.from(scripts);
    notifyListeners();
  }

  void setMarketplaceScripts(List<MarketplaceScript> scripts) {
    _marketplaceScripts = List.from(scripts);
    notifyListeners();
  }

  void setDownloadedScriptIds(Set<String> ids) {
    _downloadedScriptIds = Set.from(ids);
    notifyListeners();
  }

  void setFavoriteScriptIds(Set<String> ids) {
    _favoriteScriptIds = Set.from(ids);
    notifyListeners();
  }

  void setSelectedCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  void setSortOption(ScriptSortOption option, {required bool ascending}) {
    if (_sortOption != option || _sortAscending != ascending) {
      _sortOption = option;
      _sortAscending = ascending;
      notifyListeners();
    }
  }

  void setShowDownloadedOnly(bool value) {
    if (_showDownloadedOnly != value) {
      _showDownloadedOnly = value;
      notifyListeners();
    }
  }

  void setShowFavoritesOnly(bool value) {
    if (_showFavoritesOnly != value) {
      _showFavoritesOnly = value;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }

  void clearAllFilters() {
    _selectedCategory = 'All';
    _sortOption = ScriptSortOption.lastRun;
    _sortAscending = false;
    _showDownloadedOnly = false;
    _showFavoritesOnly = false;
    _searchQuery = '';
    notifyListeners();
  }

  // ============================================
  // Filtered Items (Internal & Public)
  // ============================================

  /// Internal method to get filtered items for view determination
  List<ScriptListItem> _getFilteredItemsInternal() {
    // Create hybrid list from local and marketplace scripts
    final lastRunMap = <String, DateTime>{};
    for (final s in _localScripts) {
      if (s.lastRunAt != null) {
        lastRunMap[s.id] = s.lastRunAt!;
      }
    }

    var items = ScriptListItem.createHybridList(
      localScripts: _localScripts,
      marketplaceScripts: _marketplaceScripts,
      installedMarketplaceIds: _downloadedScriptIds,
      runCounts: {for (final s in _localScripts) s.id: s.runCount},
      lastRunAt: lastRunMap,
    );

    // Apply sort
    items =
        ScriptListItem.sortItems(items, _sortOption, ascending: _sortAscending);

    // Apply downloaded filter
    if (_showDownloadedOnly) {
      items = items.where((item) {
        if (item.source == ScriptSource.local && item.localScript != null) {
          return item.localScript!.isFromMarketplace;
        }
        return item.isInstalled;
      }).toList();
    }

    // Apply favorites filter
    if (_showFavoritesOnly) {
      items = items.where((item) {
        if (item.source == ScriptSource.local && item.localScript != null) {
          return _favoriteScriptIds.contains(item.localScript!.id);
        }
        if (item.source == ScriptSource.marketplace &&
            item.marketplaceScript != null) {
          return _favoriteScriptIds.contains(item.marketplaceScript!.id);
        }
        return false;
      }).toList();
    }

    return items;
  }

  /// Public method to get filtered items for display
  List<ScriptListItem> getFilteredItems() {
    return _getFilteredItemsInternal();
  }

  /// Check if we have any content (regardless of filters)
  bool get hasAnyContent =>
      _localScripts.isNotEmpty || _marketplaceScripts.isNotEmpty;
}
