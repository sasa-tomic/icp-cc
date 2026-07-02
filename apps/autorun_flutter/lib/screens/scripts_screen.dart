import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../controllers/script_controller.dart';
import '../controllers/account_controller.dart';
import '../models/account.dart';
import '../models/script_record.dart';
import '../models/marketplace_script.dart';
import '../models/script_list_item.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/download_history_service.dart';
import '../services/favorites_service.dart';
import '../services/script_integrity_service.dart';
import '../services/search_history_service.dart';
import '../services/onboarding_progress_service.dart';
import '../services/secure_storage_readiness.dart';

import '../rust/native_bridge.dart';
import '../widgets/connectivity_scope.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/offline_banner.dart';
import '../widgets/script_app_host.dart';
import '../widgets/quick_upload_dialog.dart';
import '../widgets/script_details_dialog.dart';
import '../widgets/profile_scope.dart';
import '../widgets/animated_fab.dart';
import '../widgets/page_transitions.dart';
import '../widgets/script_execution_bottom_sheet.dart';
import '../widgets/script_row_menus.dart';
import '../widgets/scripts_empty_state.dart';
import '../widgets/scripts_list_item_tile.dart';
import '../widgets/scripts_search_bar.dart';
import 'script_creation_screen.dart';
import 'download_history_screen.dart';
import 'account_registration_wizard.dart';
import 'account_registration_prompt_dialog.dart';
import 'script_editor_dialog.dart';
import 'script_filter_sheet.dart';
import 'unified_setup_wizard.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => ScriptsScreenState();
}

class ScriptsScreenState extends State<ScriptsScreen> {
  late final ScriptController _controller;
  final RustScriptBridge _bridge = RustScriptBridge(const RustBridgeLoader());

  ScriptAppRuntime _runtimeFor(ScriptRecord r) => ScriptAppRuntime(_bridge);

  final MarketplaceOpenApiService _marketplaceService =
      MarketplaceOpenApiService();
  final DownloadHistoryService _downloadHistoryService =
      DownloadHistoryService();
  final SearchHistoryService _searchHistoryService = SearchHistoryService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<MarketplaceScript> _marketplaceScripts = [];
  List<String> _categories = [];
  final Set<String> _downloadingScriptIds = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  Set<String> _downloadedScriptIds = {};
  // KEY FIX: Initialize marketplace loading to true to prevent showing
  // empty state before marketplace data arrives for new users
  bool _isMarketplaceLoading = true;
  bool _isLoadingMore = false;
  bool _isSearching = false;
  int _offset = 0;
  bool _hasMore = true;

  String _selectedCategory = 'All';
  final String _sortBy = 'createdAt';
  final String _sortOrder = 'desc';
  String _searchQuery = '';
  List<ScriptRecord> _filteredLocalScripts = [];
  ScriptSortOption _allScriptsSortOption = ScriptSortOption.lastRun;
  bool _allScriptsSortAscending = false;
  bool _showDownloadedOnly = false;
  bool _showFavoritesOnly = false;
  Set<String> _favoriteScriptIds = {};
  final FavoritesService _favoritesService = FavoritesService();
  List<String> _recentSearches = [];
  bool _showRecentSearches = false;

  @override
  void initState() {
    super.initState();
    _controller = ScriptController(ScriptRepository.instance)
      ..addListener(_onChanged);
    _controller.ensureLoaded();
    _initializeMarketplace();
    _loadCategories();
    _loadDownloadedScripts();
    _initializeMarketplaceData();
    _loadRecentSearches();
    _loadFavorites();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoritesService.getAllFavorites();
    if (mounted) {
      setState(() {
        _favoriteScriptIds = favorites;
      });
    }
    // Listen for future changes
    _favoritesService.favoritesStream.listen((favorites) {
      if (mounted) {
        setState(() {
          _favoriteScriptIds = favorites;
        });
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    final searches = await _searchHistoryService.getRecentSearches();
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && _recentSearches.isNotEmpty) {
      setState(() {
        _showRecentSearches = true;
      });
    } else {
      setState(() {
        _showRecentSearches = false;
      });
    }
  }

  void _selectRecentSearch(String query) {
    _searchController.text = query;
    _searchQuery = query;
    _showRecentSearches = false;
    _searchFocusNode.unfocus();
    _addSearchToHistory(query);
    _loadMarketplaceScripts();
  }

  Future<void> _addSearchToHistory(String query) async {
    if (query.trim().isNotEmpty) {
      await _searchHistoryService.addSearchQuery(query);
      await _loadRecentSearches();
    }
  }

  Future<void> _clearSearchHistory() async {
    await _searchHistoryService.clearHistory();
    await _loadRecentSearches();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search history cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _initializeMarketplaceData() async {
    await _loadSavedCategory();
    await _loadMarketplaceScripts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // Update filtered local scripts when controller's scripts change
    _updateFilteredLocalScripts();
    setState(() {});
  }

  void _updateFilteredLocalScripts() {
    final allScripts = _controller.scripts;
    if (_searchQuery.isEmpty) {
      _filteredLocalScripts = allScripts;
    } else {
      final queryLower = _searchQuery.toLowerCase();
      _filteredLocalScripts = allScripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(queryLower);
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(queryLower) ?? false;
        return titleMatch || authorMatch;
      }).toList();
    }
  }

  void createNewScript() {
    _showCreateSheet();
  }

  void focusSearch() {
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  Future<void> refreshContent() async {
    await _controller.refresh();
    await _refreshMarketplaceScripts();
  }

  Future<void> _initializeMarketplace() async {
    // No initialization needed for open API service
  }

  Future<void> _loadMarketplaceScripts({bool isLoadMore = false}) async {
    if (isLoadMore && (_isLoadingMore || !_hasMore)) return;
    if (!isLoadMore && _isMarketplaceLoading) return;

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _isMarketplaceLoading = true;
        _offset = 0;
        _marketplaceScripts.clear();
      }
    });

    try {
      final result = await _marketplaceService.searchScripts(
        query: _searchQuery.isEmpty ? null : _searchQuery,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        limit: MarketplaceOpenApiService.defaultSearchLimit,
        offset: _offset,
      );

      setState(() {
        if (isLoadMore) {
          _marketplaceScripts.addAll(result.scripts);
        } else {
          _marketplaceScripts = result.scripts;
        }
        _hasMore = result.hasMore;
        _offset += result.scripts.length;
      });
    } catch (e) {
      debugPrint('Failed to load marketplace scripts: $e');
    } finally {
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = false;
        } else {
          _isMarketplaceLoading = false;
        }
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      _categories = ['All', ..._marketplaceService.getCategories()];
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  Future<void> _refreshMarketplaceScripts() async {
    await _loadMarketplaceScripts();
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;

    // Filter local scripts by query
    final allScripts = _controller.scripts;
    if (query.isEmpty) {
      _filteredLocalScripts = allScripts;
    } else {
      final queryLower = query.toLowerCase();
      _filteredLocalScripts = allScripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(queryLower);
        // Also check author for marketplace-downloaded scripts
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(queryLower) ?? false;
        return titleMatch || authorMatch;
      }).toList();
    }

    setState(() => _isSearching = true);
    _debouncedSearch();
  }

  void _debouncedSearch() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchController.text == _searchQuery) {
        _addSearchToHistory(_searchQuery);
        _loadMarketplaceScripts();
        setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _loadSavedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCategory = prefs.getString('last_selected_category');
    if (savedCategory != null && mounted) {
      setState(() {
        _selectedCategory = savedCategory;
      });
    }
  }

  void _onCategoryChanged(String category) async {
    setState(() {
      _selectedCategory = category;
    });
    // Persist category selection
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_category', category);
    _loadMarketplaceScripts();
  }

  Future<void> _loadDownloadedScripts() async {
    try {
      // Load from download history service
      final downloadHistory =
          await _downloadHistoryService.getDownloadHistory();
      final downloadedIds =
          downloadHistory.map((record) => record.marketplaceScriptId).toSet();

      setState(() {
        _downloadedScriptIds = downloadedIds;
      });
    } catch (e) {
      debugPrint('Failed to load downloaded scripts: $e');
    }
  }

  Future<void> _downloadScript(MarketplaceScript script,
      {String? version}) async {
    if (_downloadingScriptIds.contains(script.id)) return;

    setState(() {
      _downloadingScriptIds.add(script.id);
      _downloadProgress[script.id] = 0.0;
    });

    try {
      final progressUpdates = [0.3, 0.6, 0.9];
      for (final progress in progressUpdates) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            _downloadProgress[script.id] = progress;
          });
        }
      }

      final bundle =
          await _marketplaceService.downloadScript(script.id, version: version);

      final integrityService = ScriptIntegrityService();
      final sha256Checksum = integrityService.computeChecksum(bundle);

      final effectiveVersion = version ?? script.version ?? '1.0.0';
      final titleSuffix =
          version != null ? ' (Marketplace v$version)' : ' (Marketplace)';

      final createdScript = await _controller.createScript(
        title: '${script.title}$titleSuffix',
        emoji: '📦',
        bundleOverride: bundle,
        metadata: {
          'marketplace_id': script.id,
          'marketplace_title': script.title,
          'marketplace_author': script.authorName,
          'marketplace_version': effectiveVersion,
          'downloaded_at': DateTime.now().toIso8601String(),
          'sha256_checksum': sha256Checksum,
        },
      );

      if (!mounted) return;

      await _downloadHistoryService.addToHistory(
        marketplaceScriptId: script.id,
        title: script.title,
        authorName: script.authorName ?? 'Unknown',
        version: effectiveVersion,
        localScriptId: createdScript.id,
      );

      setState(() {
        _downloadedScriptIds.add(script.id);
      });

      // Record first script interaction for GettingStartedCard
      await OnboardingProgressService().recordFirstScriptInteraction();

      if (mounted) {
        final versionText = version != null ? ' v$version' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${script.title}"$versionText added to your library!',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Run',
              textColor: Colors.white,
              onPressed: () => _runScript(createdScript),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingScriptIds.remove(script.id);
          _downloadProgress.remove(script.id);
        });
      }
    }
  }

  void _showScriptDetails(BuildContext context, MarketplaceScript script) {
    showDialog(
      context: context,
      builder: (context) => ScriptDetailsDialog(
        script: script,
        onDownload: script.price == 0 ? () => _downloadScript(script) : null,
        isDownloading: _downloadingScriptIds.contains(script.id),
        isDownloaded: _downloadedScriptIds.contains(script.id),
      ),
    );
  }

  Future<void> _runScript(ScriptRecord record) async {
    final checksum = record.metadata['sha256_checksum'] as String?;
    if (checksum != null) {
      final integrityService = ScriptIntegrityService();
      try {
        integrityService.verifyChecksum(record.bundle, checksum,
            scriptId: record.id);
      } on ScriptIntegrityException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Script integrity check failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    await _controller.recordScriptRun(record.id);

    await OnboardingProgressService().recordFirstScriptInteraction();

    if (!mounted) return;
    await showScriptExecutionBottomSheet(
      context: context,
      script: record,
      runtime: _runtimeFor(record),
      onExpand: () => _expandScriptToFullScreen(record),
    );
  }

  void _expandScriptToFullScreen(ScriptRecord record) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(record.title)),
        body: ScriptAppHost(
            runtime: _runtimeFor(record),
            script: record.bundle,
            initialArg: const <String, dynamic>{}),
      ),
    ));
  }

  Future<void> _confirmAndDeleteScript(ScriptRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete script'),
          content: Text('Delete "${record.title}"? This cannot be undone.'),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _controller.deleteScript(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Script deleted')));
    }
  }

  Future<void> _showCreateSheet() async {
    // Use script creation screen with custom transition
    final ScriptRecord? rec = await Navigator.of(context).push<ScriptRecord>(
      CustomPageRoute.scaleFade(
        ScriptCreationScreen(
          controller: _controller,
        ),
      ),
    );
    if (mounted && rec != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Script created successfully!',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'Publish',
              textColor: Colors.white,
              onPressed: () => _publishToMarketplace(rec),
            ),
          ),
        );
      }
    }
  }

  Future<void> _publishToMarketplace(ScriptRecord record) async {
    // Check if user has a registered account
    final profileController = ProfileScope.of(context, listen: false);
    final profile = profileController.activeProfile;

    if (profile?.username == null) {
      // User doesn't have an account - show registration prompt
      final shouldRegister = await _showAccountRegistrationPrompt();
      if (!shouldRegister) {
        // User declined to register
        return;
      }

      // Navigate to registration wizard
      if (!mounted) return;
      final Account? account = await Navigator.push<Account>(
        context,
        MaterialPageRoute<Account>(
          builder: (context) => AccountRegistrationWizard(
            keypair: profile!.primaryKeypair,
            accountController: AccountController(
              profileController: profileController,
            ),
            initialDisplayName: profile.name,
          ),
        ),
      );

      // If registration successful, update profile username
      if (account != null && mounted) {
        await profileController.updateProfileUsername(
          profileId: profile!.id,
          username: account.username,
        );
      } else {
        // Registration cancelled or failed
        return;
      }
    }

    // Proceed with upload
    if (!mounted) return;
    final bool? uploaded = await showDialog<bool>(
      context: context,
      builder: (context) => QuickUploadDialog(
        script: record,
      ),
    );

    if (uploaded == true) {
      // Refresh downloaded scripts to include the newly published one
      await _loadDownloadedScripts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Script published successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// Shows a prompt asking user to register for marketplace publishing
  /// Returns true if user wants to register, false if dismissed
  Future<bool> _showAccountRegistrationPrompt() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AccountRegistrationPromptDialog(),
    );
    return result ?? false;
  }

  void _viewInMarketplace(ScriptRecord record) {
    final marketplaceTitle = record.metadata['marketplace_title'] as String? ??
        record.title.replaceAll(' (Marketplace)', '');

    setState(() {
      _searchController.text = marketplaceTitle;
      _searchQuery = marketplaceTitle;
    });
    _loadMarketplaceScripts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Searching marketplace for "$marketplaceTitle"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _duplicateScript(ScriptRecord record) async {
    try {
      final newScript = await _controller.createScript(
        title: '${record.title} (Copy)',
        emoji: record.emoji,
        imageUrl: record.imageUrl,
        bundleOverride: record.bundle,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Script duplicated as "${newScript.title}"'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Scroll to the new script (implementation depends on your list view)
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to duplicate script: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyScriptSource(ScriptRecord record) async {
    await copyScriptSourceToClipboard(record);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script source code copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use filtered local scripts (updated in _onChanged and _onSearchChanged)
    final scripts = _filteredLocalScripts;

    // WU-1: when the user dismissed the first-run wizard without creating a
    // profile, the library empty-state must offer "Set Up Profile" instead of
    // the keypair-dependent Create / Browse CTAs. Lookup is defensive: in
    // production a ProfileScope is always present, but unit tests often pump
    // ScriptsScreen without one, so a missing scope is treated as "no gating"
    // (legacy behavior). dependOnInheritedWidgetOfExactType keeps this reactive.
    final profileScope =
        context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    final profileController = profileScope?.notifier;
    final hasProfile =
        profileController == null || profileController.profiles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scripts'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'download_history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DownloadHistoryScreen(),
                  ),
                );
              } else if (value == 'clear_search_history') {
                _clearSearchHistory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'download_history',
                child: Row(
                  children: [
                    Icon(Icons.history),
                    SizedBox(width: 12),
                    Text('Download History'),
                  ],
                ),
              ),
              PopupMenuItem(
                enabled: _recentSearches.isNotEmpty,
                value: 'clear_search_history',
                child: Row(
                  children: [
                    Icon(
                      Icons.clear_all,
                      color: _recentSearches.isNotEmpty
                          ? null
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Clear Search History',
                      style: TextStyle(
                        color: _recentSearches.isNotEmpty
                            ? null
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              OfflineBanner(
                isOnline: ConnectivityScope.of(context).isOnline,
                onDismiss: () => ConnectivityScope.of(context, listen: false)
                    .dismissBanner(),
              ),
              _buildSearchBar(),
              Expanded(
                child: _buildUnifiedListView(scripts, hasProfile: hasProfile),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 90,
            child: ShortcutTooltip(
              label: 'New Script',
              shortcut: DesktopShortcuts.getShortcutLabel('new'),
              child: AnimatedFab(
                heroTag: 'scripts_fab',
                onPressed: _controller.isBusy ? null : _showCreateSheet,
                icon: const Icon(Icons.add_rounded),
                label: 'New Script',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedListView(List<ScriptRecord> localScripts,
      {required bool hasProfile}) {
    final lastRunMap = <String, DateTime>{};
    for (final s in localScripts) {
      if (s.lastRunAt != null) {
        lastRunMap[s.id] = s.lastRunAt!;
      }
    }

    final hybridItems = ScriptListItem.createHybridList(
      localScripts: localScripts,
      marketplaceScripts: _marketplaceScripts,
      installedMarketplaceIds: _downloadedScriptIds,
      runCounts: {for (final s in localScripts) s.id: s.runCount},
      lastRunAt: lastRunMap,
    );

    var sortedItems = ScriptListItem.sortItems(
      hybridItems,
      _allScriptsSortOption,
      ascending: _allScriptsSortAscending,
    );

    if (_showDownloadedOnly) {
      sortedItems = sortedItems.where((item) {
        if (item.source == ScriptSource.local && item.localScript != null) {
          return item.localScript!.isFromMarketplace;
        }
        return item.isInstalled;
      }).toList();
    }

    if (_showFavoritesOnly) {
      sortedItems = sortedItems.where((item) {
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

    final displayedItems = sortedItems;

    final isLoadingAnything = _controller.isBusy || _isMarketplaceLoading;
    final hasNoContent = localScripts.isEmpty && displayedItems.isEmpty;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (isLoadingAnything && hasNoContent) {
          return const Center(child: CircularProgressIndicator());
        }

        if (displayedItems.isEmpty && !isLoadingAnything) {
          final kind = _showDownloadedOnly
              ? ScriptsEmptyStateKind.downloadedFilter
              : _showFavoritesOnly
                  ? ScriptsEmptyStateKind.favoritesFilter
                  : ScriptsEmptyStateKind.library;
          return ScriptsEmptyState(
            kind: kind,
            hasProfile: hasProfile,
            onCreateScript: _showCreateSheet,
            onBrowseMarketplace: _browseMarketplaceFromEmptyState,
            onSetupProfile: _openSetupWizard,
            onClearDownloadedFilter: _clearDownloadedFilter,
            onClearFavoritesFilter: _clearFavoritesFilter,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await _controller.refresh();
            await _refreshMarketplaceScripts();
          },
          child: CustomScrollView(
            slivers: [
              ..._buildUnifiedListContent(
                displayedItems: displayedItems,
                isLoadingAnything: isLoadingAnything,
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildUnifiedListContent({
    required List<ScriptListItem> displayedItems,
    required bool isLoadingAnything,
  }) {
    if (displayedItems.isEmpty && !isLoadingAnything) {
      return [];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAllScriptsListItem(displayedItems[index]),
          childCount: displayedItems.length,
        ),
      ),
    ];
  }

  Widget _buildAllScriptsListItem(ScriptListItem item) {
    final isLocalScript =
        item.source == ScriptSource.local && item.localScript != null;
    return ScriptsListItemTile(
      item: item,
      onTap: () => _handleAllScriptsItemTap(item),
      onLongPress: () =>
          showScriptContextMenuSheet(context, item, _contextMenuActionsFor(item)),
      onSecondaryTapUp: (details) => showScriptContextMenuPopup(
        context,
        item,
        details.globalPosition,
        _contextMenuActionsFor(item),
        canPublish:
            item.localScript != null && !item.localScript!.isFromMarketplace,
        isDownloaded: item.marketplaceScript != null &&
            _downloadedScriptIds.contains(item.marketplaceScript!.id),
      ),
      trailing: isLocalScript
          ? LocalScriptRowMenu(
              record: item.localScript!,
              isFavorite: _favoriteScriptIds.contains(item.localScript!.id),
              onRun: () => _runScript(item.localScript!),
              onEdit: () => _editScript(item.localScript!),
              onPublish: () => _publishToMarketplace(item.localScript!),
              onConfirmDelete: () => _confirmAndDeleteScript(item.localScript!),
              onDuplicate: () => _duplicateScript(item.localScript!),
              onCopySource: () => _copyScriptSource(item.localScript!),
              onViewInMarketplace: () => _viewInMarketplace(item.localScript!),
              onToggleFavorite: () => _toggleFavorite(item.localScript!.id),
            )
          : item.source == ScriptSource.marketplace &&
                  item.marketplaceScript != null
              ? MarketplaceScriptRowMenu(
                  script: item.marketplaceScript!,
                  isDownloaded: _downloadedScriptIds
                      .contains(item.marketplaceScript!.id),
                  isDownloading: _downloadingScriptIds
                      .contains(item.marketplaceScript!.id),
                  isFavorite:
                      _favoriteScriptIds.contains(item.marketplaceScript!.id),
                  onViewDetails: () =>
                      _showScriptDetails(context, item.marketplaceScript!),
                  onDownload: () => _downloadScript(item.marketplaceScript!),
                  onShare: () => _shareScript(context, item.marketplaceScript!),
                  onToggleFavorite: () =>
                      _toggleFavorite(item.marketplaceScript!.id),
                )
              : null,
    );
  }

  /// Builds the bundle of callbacks the extracted context-menu helpers dispatch
  /// to. Each closure captures the specific record/script on [item]; the menu
  /// code only invokes the ones valid for the item's source.
  ScriptContextMenuActions _contextMenuActionsFor(ScriptListItem item) {
    return ScriptContextMenuActions(
      onRun: () => _runScript(item.localScript!),
      onEdit: () => _editScript(item.localScript!),
      onDuplicate: () => _duplicateScript(item.localScript!),
      onDelete: () => _confirmAndDeleteScript(item.localScript!),
      onPublish: () => _publishToMarketplace(item.localScript!),
      onCopySource: () => _copyScriptSource(item.localScript!),
      onViewDetails: () => _showScriptDetails(context, item.marketplaceScript!),
      onDownload: () => _downloadScript(item.marketplaceScript!),
      onShare: () => _shareScript(context, item.marketplaceScript!),
      isDownloading: item.marketplaceScript != null &&
          _downloadingScriptIds.contains(item.marketplaceScript!.id),
    );
  }

  /// ONE-TAP EXECUTION (#34): Single tap on local script runs immediately.
  /// Edit is accessible via overflow menu or long-press context menu.
  void _handleAllScriptsItemTap(ScriptListItem item) {
    if (item.source == ScriptSource.local && item.localScript != null) {
      // Record first script interaction for GettingStartedCard
      OnboardingProgressService().recordFirstScriptInteraction();
      // ONE-TAP: Run script immediately on tap
      _runScript(item.localScript!);
    } else if (item.source == ScriptSource.marketplace &&
        item.marketplaceScript != null) {
      _showScriptDetails(context, item.marketplaceScript!);
    }
  }

  /// Opens the script editor for editing.
  /// This is now a secondary action, accessible via overflow menu or long-press.
  void _editScript(ScriptRecord record) {
    OnboardingProgressService().recordFirstScriptInteraction();
    showDialog<void>(
      context: context,
      builder: (_) => ScriptEditorDialog(
        controller: _controller,
        record: record,
      ),
    );
  }

  Widget _buildSearchBar() {
    return ScriptsSearchBar(
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSearchChanged: _onSearchChanged,
      activeFilterCount: _getActiveFilterCount(),
      activeFilters: _getActiveFilters(),
      onClearAllFilters: _clearAllFilters,
      onFilterButtonPressed: () => _showFilterPopover(context),
      showRecentSearches: _showRecentSearches,
      recentSearches: _recentSearches,
      onSelectRecentSearch: _selectRecentSearch,
      onRemoveRecentSearch: (query) async {
        await _searchHistoryService.removeSearchQuery(query);
        await _loadRecentSearches();
      },
      isSearching: _isSearching,
    );
  }

  /// Returns a list of active filters with their labels and dismiss callbacks.
  List<ScriptsActiveFilter> _getActiveFilters() {
    final filters = <ScriptsActiveFilter>[];

    // Category filter (not 'All')
    if (_selectedCategory != 'All') {
      filters.add(ScriptsActiveFilter(
        label: _selectedCategory,
        onDismiss: () {
          setState(() {
            _selectedCategory = 'All';
          });
          _loadMarketplaceScripts();
        },
      ));
    }

    // Sort filter (not default 'lastRun')
    if (_allScriptsSortOption != ScriptSortOption.lastRun) {
      filters.add(ScriptsActiveFilter(
        label: 'Sort: ${_allScriptsSortOption.label}',
        onDismiss: () {
          setState(() {
            _allScriptsSortOption = ScriptSortOption.lastRun;
            _allScriptsSortAscending = false;
          });
        },
      ));
    }

    // Downloaded filter
    if (_showDownloadedOnly) {
      filters.add(ScriptsActiveFilter(
        label: 'Downloaded',
        onDismiss: _clearDownloadedFilter,
      ));
    }

    // Favorites filter
    if (_showFavoritesOnly) {
      filters.add(ScriptsActiveFilter(
        label: 'Favorites',
        onDismiss: _clearFavoritesFilter,
      ));
    }

    return filters;
  }

  /// Clears all active filters and refreshes marketplace scripts.
  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'All';
      _allScriptsSortOption = ScriptSortOption.lastRun;
      _allScriptsSortAscending = false;
      _showDownloadedOnly = false;
      _showFavoritesOnly = false;
    });
    _loadMarketplaceScripts();
  }

  /// Clears the "Downloaded" filter to show all scripts.
  void _clearDownloadedFilter() {
    setState(() {
      _showDownloadedOnly = false;
    });
  }

  /// Clears the "Favorites" filter to show all scripts.
  void _clearFavoritesFilter() {
    setState(() {
      _showFavoritesOnly = false;
    });
  }

  /// Toggles the favorite status of a script.
  Future<void> _toggleFavorite(String scriptId) async {
    await _favoritesService.toggleFavorite(scriptId);
    // The _favoriteScriptIds set will be updated via the favoritesStream
    // listener in _loadFavorites(), which triggers setState.
  }

  /// Re-opens the first-run [UnifiedSetupWizard] from the library empty-state.
  ///
  /// Used when the user dismissed the wizard without creating a profile: rather
  /// than dead-ending them on keypair-dependent CTAs, this gives them a direct
  /// path back to profile creation. Mirrors [showFirstRunSetupIfNeeded] in
  /// `main.dart` without introducing a circular import on the app entry point.
  Future<void> _openSetupWizard() async {
    final profileController = ProfileScope.of(context, listen: false);
    final accountController =
        AccountController(profileController: profileController);
    await Navigator.of(context).push<UnifiedSetupResult>(
      MaterialPageRoute<UnifiedSetupResult>(
        fullscreenDialog: true,
        builder: (_) => UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness: SecureStorageReadiness(),
        ),
      ),
    );
  }

  /// Clears all filters and refreshes marketplace scripts.
  /// Used as secondary action in empty state to help users discover marketplace.
  void _browseMarketplaceFromEmptyState() {
    setState(() {
      _showDownloadedOnly = false;
      _showFavoritesOnly = false;
      _selectedCategory = 'All';
      _searchQuery = '';
      _searchController.clear();
    });
    _loadMarketplaceScripts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing marketplace scripts...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Returns the number of active (non-default) filters.
  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedCategory != 'All') count++;
    if (_allScriptsSortOption != ScriptSortOption.lastRun) count++;
    if (_showDownloadedOnly) count++;
    if (_showFavoritesOnly) count++;
    return count;
  }

  /// Shows the filter popover with category and sort options.
  void _showFilterPopover(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FilterBottomSheet(
        categories: _categories,
        selectedCategory: _selectedCategory,
        sortOption: _allScriptsSortOption,
        sortAscending: _allScriptsSortAscending,
        showDownloadedOnly: _showDownloadedOnly,
        showFavoritesOnly: _showFavoritesOnly,
        onCategoryChanged: (category) {
          _onCategoryChanged(category);
          Navigator.of(context).pop();
        },
        onSortChanged: (option, ascending) {
          setState(() {
            _allScriptsSortOption = option;
            _allScriptsSortAscending = ascending;
          });
        },
        onDownloadedFilterChanged: (value) {
          setState(() {
            _showDownloadedOnly = value;
          });
        },
        onFavoritesFilterChanged: (value) {
          setState(() {
            _showFavoritesOnly = value;
          });
        },
        onReset: () {
          setState(() {
            _selectedCategory = 'All';
            _allScriptsSortOption = ScriptSortOption.lastRun;
            _allScriptsSortAscending = false;
            _showDownloadedOnly = false;
            _showFavoritesOnly = false;
          });
          Navigator.of(context).pop();
          _loadMarketplaceScripts();
        },
      ),
    );
  }

  void _shareScript(BuildContext context, MarketplaceScript script) async {
    // For now, just copy the script URL to clipboard
    // In a real implementation, you would generate a shareable link
    final shareUrl = '${AppConfig.marketplaceWebUrl}/scripts/${script.id}';

    // Capture context before async operation
    final messenger = ScaffoldMessenger.of(context);

    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Script link copied to clipboard!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

/// Copies a script's TypeScript bundle to the system clipboard.
///
/// "Copy Source" is a clipboard action (not a file export): the bundle the
/// author wrote is placed on the clipboard verbatim. Extracted as a top-level
/// function so the behavior is unit-testable without pumping the full screen.
Future<void> copyScriptSourceToClipboard(ScriptRecord record) {
  return Clipboard.setData(ClipboardData(text: record.bundle));
}
