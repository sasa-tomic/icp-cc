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

import '../rust/native_bridge.dart';
import '../widgets/connectivity_scope.dart';
import '../widgets/hover_reveal_actions.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/modern_empty_state.dart';
import '../widgets/offline_banner.dart';
import '../widgets/script_app_host.dart';
import '../widgets/quick_upload_dialog.dart';
import '../widgets/script_details_dialog.dart';
import '../widgets/profile_scope.dart';
import '../widgets/animated_fab.dart';
import '../widgets/page_transitions.dart';
import '../widgets/script_execution_bottom_sheet.dart';
import 'script_creation_screen.dart';
import 'download_history_screen.dart';
import 'account_registration_wizard.dart';
import 'account_registration_prompt_dialog.dart';
import 'script_context_menu.dart';
import 'script_editor_dialog.dart';
import 'script_filter_sheet.dart';

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
          ),
        );
      }
    }
  }

  bool _isPublishedToMarketplace(ScriptRecord record) {
    return record.metadata.containsKey('marketplace_id');
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

  Future<void> _exportScript(ScriptRecord record) async {
    // For now, just copy the source code to clipboard
    // In a real implementation, you might want to export as a file
    await Clipboard.setData(ClipboardData(text: record.bundle));

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
                child: _buildUnifiedListView(scripts),
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

  Widget _buildUnifiedListView(List<ScriptRecord> localScripts) {
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
          if (_showDownloadedOnly) {
            return ModernEmptyState(
              icon: Icons.download_outlined,
              title: "You haven't downloaded any scripts yet",
              subtitle: 'Browse the marketplace to find scripts to download',
              action: _clearDownloadedFilter,
              actionLabel: 'Browse Marketplace',
            );
          }
          if (_showFavoritesOnly) {
            return ModernEmptyState(
              icon: Icons.star_outline,
              title: "You haven't favorited any scripts yet",
              subtitle: 'Tap the star icon on scripts to add them to favorites',
              action: _clearFavoritesFilter,
              actionLabel: 'Browse Scripts',
            );
          }
          return ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Create your first script or browse the marketplace',
            action: _showCreateSheet,
            actionLabel: 'Create Script',
            secondaryAction: _browseMarketplaceFromEmptyState,
            secondaryActionLabel: 'Browse Marketplace',
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;
    final isLocalScript =
        item.source == ScriptSource.local && item.localScript != null;
    // Normal mode with selection mode entry via long-press
    return GestureDetector(
      onLongPress: () => _showScriptContextMenu(item),
      onSecondaryTapUp: (details) => _showScriptContextMenuAt(
        item,
        details.globalPosition,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompactScreen ? 12 : 16,
          vertical: 4,
        ),
        leading: CircleAvatar(
          radius: isCompactScreen ? 20 : 24,
          child: Text(
            (item.emoji ?? (item.isFromMarketplace ? '📦' : '📜')).isNotEmpty
                ? (item.emoji ?? (item.isFromMarketplace ? '📦' : '📜'))[0]
                : '📜',
            style: TextStyle(
              fontSize: isCompactScreen ? 16 : 20,
            ),
          ),
        ),
        title: Row(
          children: [
            // Source indicator as small color-coded icon
            _buildSourceIcon(item, isCompactScreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: isCompactScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Available indicator as subtle download icon
            if (!item.isInstalled && item.source == ScriptSource.marketplace)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.download_outlined,
                  size: isCompactScreen ? 14 : 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isCompactScreen ? 2 : 4),
            Text(
              _buildItemSubtitle(item),
              style: TextStyle(
                fontSize: isCompactScreen ? 11 : 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: isLocalScript
            ? _buildLocalScriptMenu(item.localScript!)
            : item.source == ScriptSource.marketplace &&
                    item.marketplaceScript != null
                ? _buildMarketplaceScriptMenu(item.marketplaceScript!)
                : null,
        onTap: () => _handleAllScriptsItemTap(item),
      ),
    );
  }

  void _showScriptContextMenu(ScriptListItem item) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ScriptContextMenuSheet(
        item: item,
        onRun: item.source == ScriptSource.local && item.localScript != null
            ? () => _runScript(item.localScript!)
            : null,
        onEdit: item.source == ScriptSource.local && item.localScript != null
            ? () => _editScript(item.localScript!)
            : null,
        onDuplicate:
            item.source == ScriptSource.local && item.localScript != null
                ? () => _duplicateScript(item.localScript!)
                : null,
        onDelete: item.source == ScriptSource.local && item.localScript != null
            ? () => _confirmAndDeleteScript(item.localScript!)
            : null,
        onPublish: item.source == ScriptSource.local && item.localScript != null
            ? () => _publishToMarketplace(item.localScript!)
            : null,
        onViewDetails: item.source == ScriptSource.marketplace &&
                item.marketplaceScript != null
            ? () => _showScriptDetails(context, item.marketplaceScript!)
            : null,
        onDownload: item.source == ScriptSource.marketplace &&
                item.marketplaceScript != null &&
                !_downloadedScriptIds.contains(item.marketplaceScript!.id)
            ? () => _downloadScript(item.marketplaceScript!)
            : null,
        isDownloading: item.source == ScriptSource.marketplace &&
                item.marketplaceScript != null
            ? _downloadingScriptIds.contains(item.marketplaceScript!.id)
            : false,
        isDownloaded: item.isInstalled,
      ),
    );
  }

  void _showScriptContextMenuAt(ScriptListItem item, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _buildContextMenuItems(item),
    ).then((value) {
      if (value != null) {
        _handleContextMenuAction(value, item);
      }
    });
  }

  List<PopupMenuEntry<String>> _buildContextMenuItems(ScriptListItem item) {
    final items = <PopupMenuEntry<String>>[];

    if (item.source == ScriptSource.local && item.localScript != null) {
      final record = item.localScript!;
      final canPublish = !_isPublishedToMarketplace(record);

      items.addAll([
        const PopupMenuItem(
          value: 'run',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 20),
              SizedBox(width: 12),
              Text('Run'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 12),
              Text('Edit'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 20),
              SizedBox(width: 12),
              Text('Duplicate'),
            ],
          ),
        ),
        if (canPublish)
          const PopupMenuItem(
            value: 'publish',
            child: Row(
              children: [
                Icon(Icons.share, size: 20),
                SizedBox(width: 12),
                Text('Share to Marketplace'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 12),
              Text('Copy Source'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ]);
    } else if (item.source == ScriptSource.marketplace &&
        item.marketplaceScript != null) {
      final isDownloaded =
          _downloadedScriptIds.contains(item.marketplaceScript!.id);

      items.addAll([
        const PopupMenuItem(
          value: 'view_details',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20),
              SizedBox(width: 12),
              Text('View Details'),
            ],
          ),
        ),
        if (!isDownloaded)
          PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                const Icon(Icons.download, size: 20),
                const SizedBox(width: 12),
                Text(
                    'Download${item.marketplaceScript!.price > 0 ? ' (${item.marketplaceScript!.price} credits)' : ''}'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share, size: 20),
              SizedBox(width: 12),
              Text('Share'),
            ],
          ),
        ),
      ]);
    }

    return items;
  }

  void _handleContextMenuAction(String action, ScriptListItem item) {
    switch (action) {
      case 'run':
        if (item.localScript != null) _runScript(item.localScript!);
        break;
      case 'edit':
        if (item.localScript != null) _editScript(item.localScript!);
        break;
      case 'duplicate':
        if (item.localScript != null) _duplicateScript(item.localScript!);
        break;
      case 'delete':
        if (item.localScript != null) {
          _confirmAndDeleteScript(item.localScript!);
        }
        break;
      case 'publish':
        if (item.localScript != null) _publishToMarketplace(item.localScript!);
        break;
      case 'export':
        if (item.localScript != null) _exportScript(item.localScript!);
        break;
      case 'view_details':
        if (item.marketplaceScript != null) {
          _showScriptDetails(context, item.marketplaceScript!);
        }
        break;
      case 'download':
        if (item.marketplaceScript != null) {
          _downloadScript(item.marketplaceScript!);
        }
        break;
      case 'share':
        if (item.marketplaceScript != null) {
          _shareScript(context, item.marketplaceScript!);
        }
        break;
    }
  }

  Widget _buildLocalScriptMenu(ScriptRecord record) {
    final canPublish = !_isPublishedToMarketplace(record);

    // Build hover-reveal actions for desktop discoverability
    final hoverRevealActions = <Widget>[
      // Run action (visible on hover for desktop, always visible on mobile)
      ScriptActionButton(
        icon: Icons.play_arrow,
        onPressed: () => _runScript(record),
        tooltip: 'Run script',
      ),
      // Edit action (now a secondary action via ONE-TAP change)
      ScriptActionButton(
        icon: Icons.edit,
        onPressed: () => _editScript(record),
        tooltip: 'Edit script',
      ),
      // Publish action (only for unpublished scripts)
      if (canPublish)
        ScriptActionButton(
          icon: Icons.share,
          onPressed: () => _publishToMarketplace(record),
          tooltip: 'Share to Marketplace',
        ),
      // Delete action (destructive)
      ScriptActionButton(
        icon: Icons.delete_outline,
        onPressed: () => _confirmAndDeleteScript(record),
        tooltip: 'Delete script',
        isDestructive: true,
      ),
    ];

    // Always visible: favorite star
    final alwaysVisibleActions = <Widget>[
      _buildFavoriteStarButton(record.id),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hover-reveal actions (Run, Edit, Publish, Delete)
        HoverRevealActions(
          actions: hoverRevealActions,
          alwaysVisibleActions: alwaysVisibleActions,
        ),
        // OVERFLOW MENU: Secondary location for all actions
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleLocalScriptMenuAction(value, record),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 20),
                  SizedBox(width: 12),
                  Text('Duplicate'),
                ],
              ),
            ),
            if (canPublish)
              const PopupMenuItem(
                value: 'publish',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Share to Marketplace'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.copy, size: 20),
                  SizedBox(width: 12),
                  Text('Copy Source'),
                ],
              ),
            ),
            if (!canPublish)
              const PopupMenuItem(
                value: 'view_marketplace',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 20),
                    SizedBox(width: 12),
                    Text('View in Marketplace'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleLocalScriptMenuAction(String action, ScriptRecord record) {
    switch (action) {
      case 'run':
        _runScript(record);
        break;
      case 'edit':
        _editScript(record);
        break;
      case 'publish':
        _publishToMarketplace(record);
        break;
      case 'delete':
        _confirmAndDeleteScript(record);
        break;
      case 'duplicate':
        _duplicateScript(record);
        break;
      case 'export':
        _exportScript(record);
        break;
      case 'view_marketplace':
        _viewInMarketplace(record);
        break;
    }
  }

  Widget _buildMarketplaceScriptMenu(MarketplaceScript script) {
    final isDownloaded = _downloadedScriptIds.contains(script.id);
    final isDownloading = _downloadingScriptIds.contains(script.id);

    // Build hover-reveal actions for desktop discoverability
    final hoverRevealActions = <Widget>[
      // Primary action: Download or View Details
      ScriptActionButton(
        icon: isDownloaded ? Icons.info_outline : Icons.download,
        onPressed: isDownloaded
            ? () => _showScriptDetails(context, script)
            : () => _downloadScript(script),
        tooltip: isDownloaded ? 'View details' : 'Download',
        isLoading: isDownloading,
      ),
    ];

    // Always visible: favorite star
    final alwaysVisibleActions = <Widget>[
      _buildFavoriteStarButton(script.id),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hover-reveal actions (Download/View Details)
        HoverRevealActions(
          actions: hoverRevealActions,
          alwaysVisibleActions: alwaysVisibleActions,
        ),
        // OVERFLOW MENU: Secondary location for all actions
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) =>
              _handleMarketplaceScriptMenuAction(value, script),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view_details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 12),
                  Text('View Details'),
                ],
              ),
            ),
            if (!isDownloaded)
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20),
                    SizedBox(width: 12),
                    Text('Download'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text('Share'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleMarketplaceScriptMenuAction(
      String action, MarketplaceScript script) {
    switch (action) {
      case 'view_details':
        _showScriptDetails(context, script);
        break;
      case 'download':
        _downloadScript(script);
        break;
      case 'share':
        _shareScript(context, script);
        break;
    }
  }

  /// Build a small color-coded source icon.
  /// Blue for local scripts, green for marketplace scripts.
  Widget _buildSourceIcon(ScriptListItem item, bool isCompactScreen) {
    final isMarketplace = item.isFromMarketplace;
    final iconColor = isMarketplace ? Colors.green : Colors.blue;
    final iconSize = isCompactScreen ? 12.0 : 14.0;

    return Icon(
      isMarketplace ? Icons.cloud_outlined : Icons.folder_outlined,
      size: iconSize,
      color: iconColor,
    );
  }

  /// Build simplified subtitle for script list items.
  /// - For marketplace scripts: shows author only
  /// - For local scripts: shows relative date only
  String _buildItemSubtitle(ScriptListItem item) {
    // For downloaded marketplace scripts (local with marketplace metadata)
    if (item.source == ScriptSource.local && item.author != null) {
      return item.author!;
    }

    // For marketplace scripts, show author
    if (item.source == ScriptSource.marketplace) {
      return item.author ?? 'Unknown';
    }

    // For local scripts without author, show relative date
    return _formatRelativeTime(item.updatedAt);
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
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
    final activeFilterCount = _getActiveFilterCount();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: _buildConsolidatedSearchBar(),
        ),
        if (activeFilterCount > 0) _buildActiveFilterChips(),
        if (_showRecentSearches && _recentSearches.isNotEmpty)
          _buildRecentSearchesDropdown(),
        if (_isSearching) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  /// Builds the active filter chips displayed below the search bar.
  Widget _buildActiveFilterChips() {
    final activeFilters = _getActiveFilters();

    return Container(
      key: const Key('active_filter_chips'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: activeFilters.map((filter) {
                return _ActiveFilterChip(
                  label: filter.label,
                  onDismiss: filter.onDismiss,
                );
              }).toList(),
            ),
          ),
          if (activeFilters.length > 1) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear All'),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns a list of active filters with their labels and dismiss callbacks.
  List<_ActiveFilter> _getActiveFilters() {
    final filters = <_ActiveFilter>[];

    // Category filter (not 'All')
    if (_selectedCategory != 'All') {
      filters.add(_ActiveFilter(
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
      filters.add(_ActiveFilter(
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
      filters.add(_ActiveFilter(
        label: 'Downloaded',
        onDismiss: _clearDownloadedFilter,
      ));
    }

    // Favorites filter
    if (_showFavoritesOnly) {
      filters.add(_ActiveFilter(
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

  Widget _buildRecentSearchesDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Recent Searches',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...(_recentSearches.take(5).map((query) => ListTile(
                dense: true,
                leading: Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(query),
                onTap: () => _selectRecentSearch(query),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () async {
                    await _searchHistoryService.removeSearchQuery(query);
                    await _loadRecentSearches();
                  },
                  tooltip: 'Remove',
                ),
              ))),
        ],
      ),
    );
  }

  Widget _buildConsolidatedSearchBar() {
    final activeFilterCount = _getActiveFilterCount();

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search scripts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildFilterButton(activeFilterCount),
      ],
    );
  }

  /// Builds the filter button with a badge showing active filter count.
  Widget _buildFilterButton(int activeCount) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              Icons.tune,
              color: activeCount > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () => _showFilterPopover(context),
            tooltip: 'Filter options',
          ),
        ),
        if (activeCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                '$activeCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
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

  /// Builds a star icon button for toggling favorite status.
  Widget _buildFavoriteStarButton(String scriptId) {
    final isFavorite = _favoriteScriptIds.contains(scriptId);
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_outline,
        color: isFavorite ? Colors.amber : null,
      ),
      onPressed: () => _toggleFavorite(scriptId),
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
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

/// Represents an active filter with its label and dismiss callback.
class _ActiveFilter {
  _ActiveFilter({
    required this.label,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onDismiss;
}

/// A dismissible chip representing an active filter.
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.label,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onDismiss,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.close,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
