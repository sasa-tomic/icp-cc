import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../models/script_template.dart';
import '../models/marketplace_script.dart';
import '../models/script_list_item.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/download_history_service.dart';
import '../services/script_integrity_service.dart';

import '../rust/native_bridge.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/modern_empty_state.dart';
import '../widgets/script_app_host.dart';
import '../widgets/script_editor.dart';
import '../widgets/quick_upload_dialog.dart';
import '../widgets/marketplace_search_bar.dart';
import '../widgets/script_details_dialog.dart';
import '../widgets/animated_fab.dart';
import '../widgets/page_transitions.dart';
import 'script_creation_screen.dart';
import 'download_history_screen.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => ScriptsScreenState();
}

enum ScriptSourceFilter { all, local, marketplace }

class ScriptsScreenState extends State<ScriptsScreen> {
  late final ScriptController _controller;
  final ScriptAppRuntime _appRuntime =
      ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));

  ScriptSourceFilter _sourceFilter = ScriptSourceFilter.all;

  final MarketplaceOpenApiService _marketplaceService =
      MarketplaceOpenApiService();
  final DownloadHistoryService _downloadHistoryService =
      DownloadHistoryService();
  final TextEditingController _searchController = TextEditingController();

  List<MarketplaceScript> _marketplaceScripts = [];
  List<String> _categories = [];
  final Set<String> _downloadingScriptIds = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  Set<String> _downloadedScriptIds = {};
  bool _isMarketplaceLoading = false;
  bool _isLoadingMore = false;
  bool _isSearching = false;
  String? _marketplaceError;
  int _offset = 0;
  bool _hasMore = true;

  String _selectedCategory = 'All';
  final String _sortBy = 'createdAt';
  final String _sortOrder = 'desc';
  String _searchQuery = '';
  ScriptSortOption _allScriptsSortOption = ScriptSortOption.lastRun;
  bool _allScriptsSortAscending = false;

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
  }

  Future<void> _initializeMarketplaceData() async {
    await _loadSavedCategory();
    await _loadMarketplaceScripts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
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
    try {
      // No initialization needed for open API service
    } catch (e) {
      setState(() {
        _marketplaceError = 'Failed to initialize marketplace: $e';
      });
    }
  }

  Future<void> _loadMarketplaceScripts({bool isLoadMore = false}) async {
    if (isLoadMore && (_isLoadingMore || !_hasMore)) return;
    if (!isLoadMore && _isMarketplaceLoading) return;

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _isMarketplaceLoading = true;
        _marketplaceError = null;
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
      setState(() {
        _marketplaceError = _formatErrorMessage(e.toString());
      });
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

  String _formatErrorMessage(String error) {
    // Provide user-friendly messages for common errors
    if (error.contains('HTTP 404') || error.contains('Not Found')) {
      return 'Marketplace is currently unavailable\n\nThe script marketplace server is not responding. This may be due to maintenance or deployment issues. Please try again later.\n\nTechnical details: $error';
    }
    if (error.contains('Connection refused') ||
        error.contains('Network is unreachable')) {
      return 'Network connection failed\n\nUnable to connect to the marketplace. Please check your internet connection and try again.\n\nTechnical details: $error';
    }
    if (error.contains('Connection timeout')) {
      return 'Connection timeout\n\nThe marketplace is taking too long to respond. Please check your connection and try again.\n\nTechnical details: $error';
    }
    // Return the original error for other cases
    return error;
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
    setState(() => _isSearching = true);
    _debouncedSearch();
  }

  void _debouncedSearch() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchController.text == _searchQuery) {
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

      final luaSource =
          await _marketplaceService.downloadScript(script.id, version: version);

      final integrityService = ScriptIntegrityService();
      final sha256Checksum = integrityService.computeChecksum(luaSource);

      final effectiveVersion = version ?? script.version ?? '1.0.0';
      final titleSuffix =
          version != null ? ' (Marketplace v$version)' : ' (Marketplace)';

      final createdScript = await _controller.createScript(
        title: '${script.title}$titleSuffix',
        emoji: '📦',
        luaSourceOverride: luaSource,
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
        integrityService.verifyChecksum(record.luaSource, checksum,
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

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(record.title)),
        body: ScriptAppHost(
            runtime: _appRuntime,
            script: record.luaSource,
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

  String _formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    }
    return 'Just now';
  }

  String _formatRunCount(int count) {
    if (count == 0) return 'Not run yet';
    if (count == 1) return 'Run once';
    return 'Run $count times';
  }

  Widget _buildSourceBadge(ScriptRecord record, bool isCompactScreen) {
    final isFromMarketplace = record.isFromMarketplace;
    final backgroundColor = isFromMarketplace
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isFromMarketplace
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final borderColor = isFromMarketplace
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
        : Theme.of(context).colorScheme.outlineVariant;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompactScreen ? 4 : 6,
        vertical: isCompactScreen ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        isFromMarketplace ? 'Marketplace' : 'Local',
        style: TextStyle(
          fontSize: isCompactScreen ? 8 : 10,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _publishToMarketplace(ScriptRecord record) async {
    // Show quick upload dialog with pre-filled data
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

  void _viewInMarketplace(ScriptRecord record) {
    final marketplaceTitle = record.metadata['marketplace_title'] as String? ??
        record.title.replaceAll(' (Marketplace)', '');

    setState(() {
      _sourceFilter = ScriptSourceFilter.marketplace;
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
        luaSourceOverride: record.luaSource,
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
    await Clipboard.setData(ClipboardData(text: record.luaSource));

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
    final scripts = _controller.scripts;

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
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'download_history',
                child: Row(
                  children: [
                    Icon(Icons.history),
                    SizedBox(width: 12),
                    Text('Download History'),
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
              _buildSearchBar(),
              _buildSourceFilterChips(),
              _buildCategoryFilter(),
              _buildAllScriptsSortDropdown(),
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

  Widget _buildSourceFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: ScriptSourceFilter.values.map((filter) {
          final isSelected = _sourceFilter == filter;
          final label = switch (filter) {
            ScriptSourceFilter.all => 'All',
            ScriptSourceFilter.local => 'Local',
            ScriptSourceFilter.marketplace => 'Marketplace',
          };
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _sourceFilter = filter;
                });
              },
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              checkmarkColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }).toList(),
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

    final filteredItems = hybridItems.where((item) {
      switch (_sourceFilter) {
        case ScriptSourceFilter.all:
          return true;
        case ScriptSourceFilter.local:
          return item.source == ScriptSource.local;
        case ScriptSourceFilter.marketplace:
          return item.source == ScriptSource.marketplace ||
              item.isFromMarketplace;
      }
    }).toList();

    final sortedItems = ScriptListItem.sortItems(
      filteredItems,
      _allScriptsSortOption,
      ascending: _allScriptsSortAscending,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isBusy && localScripts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (sortedItems.isEmpty && !_controller.isBusy) {
          return ModernEmptyState(
            icon: Icons.code_rounded,
            title: _sourceFilter == ScriptSourceFilter.local
                ? 'No Local Scripts'
                : _sourceFilter == ScriptSourceFilter.marketplace
                    ? 'No Marketplace Scripts'
                    : 'Your Script Library is Empty',
            subtitle: _sourceFilter == ScriptSourceFilter.local
                ? 'Create your first script to get started'
                : 'Create your first script or browse the marketplace',
            action: _showCreateSheet,
            actionLabel: 'Create Script',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await _controller.refresh();
            await _refreshMarketplaceScripts();
          },
          child: ListView.separated(
            padding: const EdgeInsets.only(
              bottom: 100,
              top: 8,
              left: 8,
              right: 8,
            ),
            itemCount: sortedItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = sortedItems[index];
              return _buildAllScriptsListItem(item);
            },
          ),
        );
      },
    );
  }

  Widget _buildAllScriptsSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Sort by:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<ScriptSortOption>(
            value: _allScriptsSortOption,
            underline: const SizedBox(),
            items: ScriptSortOption.values
                .map((opt) => DropdownMenuItem(
                      value: opt,
                      child: Text(opt.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  if (_allScriptsSortOption == value) {
                    _allScriptsSortAscending = !_allScriptsSortAscending;
                  } else {
                    _allScriptsSortOption = value;
                    _allScriptsSortAscending = false;
                  }
                });
              }
            },
          ),
          IconButton(
            icon: Icon(
              _allScriptsSortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _allScriptsSortAscending = !_allScriptsSortAscending;
              });
            },
            tooltip: _allScriptsSortAscending ? 'Ascending' : 'Descending',
          ),
        ],
      ),
    );
  }

  Widget _buildAllScriptsListItem(ScriptListItem item) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;

    return ListTile(
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
          _buildHybridSourceBadge(item, isCompactScreen),
          const SizedBox(width: 8),
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
          if (!item.isInstalled && item.source == ScriptSource.marketplace)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompactScreen ? 4 : 6,
                vertical: isCompactScreen ? 1 : 2,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Available',
                style: TextStyle(
                  fontSize: isCompactScreen ? 8 : 10,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w500,
                ),
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
      trailing: item.source == ScriptSource.local && item.localScript != null
          ? _buildLocalScriptMenu(item.localScript!)
          : item.source == ScriptSource.marketplace &&
                  item.marketplaceScript != null
              ? _buildMarketplaceScriptMenu(item.marketplaceScript!)
              : null,
      onTap: () => _handleAllScriptsItemTap(item),
    );
  }

  Widget _buildLocalScriptMenu(ScriptRecord record) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => _handleLocalScriptMenuAction(value, record),
      itemBuilder: (context) => [
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
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20),
              SizedBox(width: 12),
              Text('Delete'),
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
        if (!_isPublishedToMarketplace(record))
          const PopupMenuItem(
            value: 'publish',
            child: Row(
              children: [
                Icon(Icons.upload, size: 20),
                SizedBox(width: 12),
                Text('Publish to Marketplace'),
              ],
            ),
          ),
      ],
    );
  }

  void _handleLocalScriptMenuAction(String action, ScriptRecord record) {
    switch (action) {
      case 'run':
        _runScript(record);
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
      case 'publish':
        _publishToMarketplace(record);
        break;
    }
  }

  Widget _buildMarketplaceScriptMenu(MarketplaceScript script) {
    final isDownloaded = _downloadedScriptIds.contains(script.id);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => _handleMarketplaceScriptMenuAction(value, script),
      itemBuilder: (context) => [
        if (isDownloaded)
          const PopupMenuItem(
            value: 'view_in_library',
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 20),
                SizedBox(width: 12),
                Text('View in Library'),
              ],
            ),
          ),
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
    );
  }

  void _handleMarketplaceScriptMenuAction(
      String action, MarketplaceScript script) {
    switch (action) {
      case 'share':
        _shareScript(context, script);
        break;
      case 'view_in_library':
        setState(() {
          _sourceFilter = ScriptSourceFilter.local;
        });
        break;
    }
  }

  Widget _buildHybridSourceBadge(ScriptListItem item, bool isCompactScreen) {
    final isMarketplace = item.isFromMarketplace;
    final backgroundColor = isMarketplace
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isMarketplace
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final borderColor = isMarketplace
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
        : Theme.of(context).colorScheme.outlineVariant;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompactScreen ? 4 : 6,
        vertical: isCompactScreen ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        isMarketplace ? 'Marketplace' : 'Local',
        style: TextStyle(
          fontSize: isCompactScreen ? 8 : 10,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _buildItemSubtitle(ScriptListItem item) {
    final parts = <String>[];

    if (item.author != null) {
      parts.add(item.author!);
    }
    if (item.version != null) {
      parts.add('v${item.version}');
    }
    if (item.runCount > 0) {
      parts.add('${item.runCount} runs');
    }
    if (item.source == ScriptSource.marketplace && item.downloads > 0) {
      parts.add('${item.downloads} downloads');
    }
    parts.add('Updated ${_formatRelativeTime(item.updatedAt)}');

    return parts.join(' • ');
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

  void _handleAllScriptsItemTap(ScriptListItem item) {
    if (item.source == ScriptSource.local && item.localScript != null) {
      showDialog<void>(
        context: context,
        builder: (_) => _ScriptEditorDialog(
          controller: _controller,
          record: item.localScript!,
        ),
      );
    } else if (item.source == ScriptSource.marketplace &&
        item.marketplaceScript != null) {
      _showScriptDetails(context, item.marketplaceScript!);
    }
  }

  Widget _buildSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: MarketplaceSearchBar(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          ),
        ),
        if (_isSearching) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) => _onCategoryChanged(category),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              checkmarkColor: Theme.of(context).colorScheme.primary,
            ),
          );
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

// Legacy script creation components replaced by improved versions

/// Improved script editor dialog with syntax highlighting and improved UX
class _ScriptEditorDialog extends StatefulWidget {
  const _ScriptEditorDialog({required this.controller, required this.record});
  final ScriptController controller;
  final ScriptRecord record;

  @override
  State<_ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _ScriptEditorDialogState extends State<_ScriptEditorDialog> {
  bool _saving = false;
  late final ValueNotifier<String> _codeNotifier;

  @override
  void initState() {
    super.initState();
    _codeNotifier = ValueNotifier<String>(widget.record.luaSource);
  }

  @override
  void dispose() {
    _codeNotifier.dispose();
    super.dispose();
  }

  void _onCodeChanged(String code) {
    _codeNotifier.value = code;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateSource(
        id: widget.record.id,
        luaSource: _codeNotifier.value,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompactScreen = screenSize.width < 400;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: screenSize.width,
        height: screenSize.height,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            // Compact Header
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isCompactScreen ? 12 : 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                    size: isCompactScreen ? 18 : 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.record.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: isCompactScreen ? 14 : 16,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (!isCompactScreen) ...[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 16),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  if (isCompactScreen) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),

            // Maximized Editor
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isCompactScreen ? 4 : 8),
                child: ScriptEditor(
                  initialCode: widget.record.luaSource,
                  onCodeChanged: _onCodeChanged,
                  language: 'lua',
                  showIntegrations: !isCompactScreen,
                  minLines: isCompactScreen ? 20 : 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptDetailsDialog extends StatefulWidget {
  const _ScriptDetailsDialog({required this.controller, required this.record});
  final ScriptController controller;
  final ScriptRecord record;

  @override
  State<_ScriptDetailsDialog> createState() => _ScriptDetailsDialogState();
}

class _NewScriptDetailsDialog extends StatefulWidget {
  const _NewScriptDetailsDialog(
      {required this.controller, required this.luaSource});
  final ScriptController controller;
  final String luaSource;

  @override
  State<_NewScriptDetailsDialog> createState() =>
      _NewScriptDetailsDialogState();
}

class _NewScriptDetailsDialogState extends State<_NewScriptDetailsDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'My first script');
    _emojiController = TextEditingController(text: '🧪');
    _imageUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final rec = await widget.controller.createScript(
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty
            ? null
            : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty
            ? null
            : _imageUrlController.text.trim(),
        luaSourceOverride: widget.luaSource,
      );
      if (!mounted) return;
      Navigator.of(context).pop(rec);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name your script'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiController,
                decoration: const InputDecoration(
                    labelText: 'Emoji (optional)',
                    border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    border: OutlineInputBorder()),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Provide either an emoji or an image URL',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _isSubmitting ? null : _save,
            child: const Text('Create script')),
      ],
    );
  }
}

class _ScriptDetailsDialogState extends State<_ScriptDetailsDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.record.title);
    _emojiController = TextEditingController(text: widget.record.emoji ?? '');
    _imageUrlController =
        TextEditingController(text: widget.record.imageUrl ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.controller.updateDetails(
        id: widget.record.id,
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty
            ? null
            : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty
            ? null
            : _imageUrlController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit details'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiController,
                decoration: const InputDecoration(
                    labelText: 'Emoji (optional)',
                    border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    border: OutlineInputBorder()),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Provide either an emoji or an image URL',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _isSubmitting ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Dialog for selecting a script template when creating a new script
class _ScriptTemplateSelectionDialog extends StatefulWidget {
  @override
  State<_ScriptTemplateSelectionDialog> createState() =>
      _ScriptTemplateSelectionDialogState();
}

class _ScriptTemplateSelectionDialogState
    extends State<_ScriptTemplateSelectionDialog> {
  String _selectedLevel = 'all';
  String _searchQuery = '';

  List<ScriptTemplate> get _filteredTemplates {
    var templates = ScriptTemplates.templates;

    // Filter by level
    if (_selectedLevel != 'all') {
      templates = templates.where((t) => t.level == _selectedLevel).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      templates = ScriptTemplates.search(_searchQuery);
    }

    return templates;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.library_books, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Choose a Template',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select a template to get started with your Lua script',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),

            // Search and Filter
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search templates...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'beginner', label: Text('Beginner')),
                    ButtonSegment(
                        value: 'intermediate', label: Text('Intermediate')),
                    ButtonSegment(value: 'advanced', label: Text('Advanced')),
                  ],
                  selected: {_selectedLevel},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() => _selectedLevel = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Template Grid
            Expanded(
              child: _filteredTemplates.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No templates found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search or filters',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _filteredTemplates.length,
                      itemBuilder: (context, index) {
                        final template = _filteredTemplates[index];
                        return _TemplateCard(
                          template: template,
                          onTap: () => Navigator.of(context).pop(template),
                        );
                      },
                    ),
            ),

            // Footer
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
                TextButton.icon(
                  onPressed: () {
                    // Use default template
                    final defaultTemplate =
                        ScriptTemplates.templates.firstWhere(
                      (t) => t.id == 'hello_world',
                    );
                    Navigator.of(context).pop(defaultTemplate);
                  },
                  icon: const Icon(Icons.bolt),
                  label: const Text('Start with Default'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget for displaying a script template
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onTap,
  });

  final ScriptTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    template.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    _getLevelColor(template.level, colorScheme),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                template.level.capitalize(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (template.isRecommended) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.star,
                                  size: 16, color: Colors.amber[600]),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Expanded(
                child: Text(
                  template.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Tags
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: template.tags.take(3).map((tag) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getLevelColor(String level, ColorScheme colorScheme) {
    switch (level) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'advanced':
        return Colors.red;
      default:
        return colorScheme.primary;
    }
  }
}

/// Extension to capitalize strings
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
