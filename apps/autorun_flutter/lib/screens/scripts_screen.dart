import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../models/script_template.dart';
import '../models/marketplace_script.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/download_history_service.dart';

import '../rust/native_bridge.dart';
import '../widgets/modern_empty_state.dart';
import '../widgets/script_app_host.dart';
import '../widgets/script_editor.dart';
import '../widgets/quick_upload_dialog.dart';
import '../widgets/marketplace_search_bar.dart';
import '../widgets/script_card.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/error_display.dart';
import '../widgets/script_details_dialog.dart';
import '../widgets/animated_fab.dart';


import '../widgets/page_transitions.dart';
import 'script_creation_screen.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> with TickerProviderStateMixin {
  late final ScriptController _controller;
  late final TabController _tabController;
  final ScriptAppRuntime _appRuntime = ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
  
  // Marketplace properties
  final MarketplaceOpenApiService _marketplaceService = MarketplaceOpenApiService();
  final DownloadHistoryService _downloadHistoryService = DownloadHistoryService();
  final TextEditingController _searchController = TextEditingController();
  
  List<MarketplaceScript> _marketplaceScripts = [];
  List<String> _categories = [];
  final Set<String> _downloadingScriptIds = <String>{};
  Set<String> _downloadedScriptIds = {};
  bool _isMarketplaceLoading = false;
  bool _isLoadingMore = false;
  String? _marketplaceError;
  int _offset = 0;
  bool _hasMore = true;

  String _selectedCategory = 'All';
  final String _sortBy = 'createdAt';
  final String _sortOrder = 'desc';
  String _searchQuery = '';


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _controller = ScriptController(ScriptRepository())..addListener(_onChanged);
    _controller.ensureLoaded();
    _initializeMarketplace();
    _loadMarketplaceScripts();
    _loadCategories();
    _loadDownloadedScripts();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  // Marketplace methods
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
    if (error.contains('Connection refused') || error.contains('Network is unreachable')) {
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
    _debouncedSearch();
  }

  void _debouncedSearch() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchController.text == _searchQuery) {
        _loadMarketplaceScripts();
      }
    });
  }

  void _onCategoryChanged(String category) {
    setState(() {
      _selectedCategory = category;
    });
    _loadMarketplaceScripts();
  }

  

  Future<void> _loadDownloadedScripts() async {
    try {
      // Load from download history service
      final downloadHistory = await _downloadHistoryService.getDownloadHistory();
      final downloadedIds = downloadHistory
          .map((record) => record.marketplaceScriptId)
          .toSet();
      
      setState(() {
        _downloadedScriptIds = downloadedIds;
      });
    } catch (e) {
      debugPrint('Failed to load downloaded scripts: $e');
    }
  }

  Future<void> _downloadScript(MarketplaceScript script) async {
    if (_downloadingScriptIds.contains(script.id)) return;

    setState(() {
      _downloadingScriptIds.add(script.id);
    });

    try {
      // Download script source
      final luaSource = await _marketplaceService.downloadScript(script.id);

      // Create local script with marketplace metadata
      final createdScript = await _controller.createScript(
        title: '${script.title} (Marketplace)',
        emoji: '📦',
        luaSourceOverride: luaSource,
        metadata: {
          'marketplace_id': script.id,
          'marketplace_title': script.title,
          'marketplace_author': script.authorName,
          'marketplace_version': script.version ?? '1.0.0',
          'downloaded_at': DateTime.now().toIso8601String(),
        },
      );

      if (!mounted) return;

      // Add to download history
      await _downloadHistoryService.addToHistory(
        marketplaceScriptId: script.id,
        title: script.title,
        authorName: script.authorName,
        version: script.version,
        localScriptId: createdScript.id,
      );

      // Update downloaded state
      setState(() {
        _downloadedScriptIds.add(script.id);
      });

      // Show success feedback and switch to My Scripts tab
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${script.title}" added to your library!',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View Scripts',
            textColor: Colors.white,
            onPressed: () {
              _tabController.animateTo(0); // Switch to My Scripts tab
            },
          ),
        ),
      );

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

  void _showUploadScriptDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const QuickUploadDialog(),
    );
  }

  

  Future<void> _runScript(ScriptRecord record) async {
    // Launch persistent app host for TEA-style scripts
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(record.title)),
        body: ScriptAppHost(runtime: _appRuntime, script: record.luaSource, initialArg: const <String, dynamic>{}),
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
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _controller.deleteScript(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Script deleted')));
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
    // Check if script has marketplace metadata
    return record.metadata.containsKey('marketplace_id');
  }

  Future<void> _publishToMarketplace(ScriptRecord record) async {
    // Show quick upload dialog with pre-filled data
    final bool? uploaded = await showDialog<bool>(
      context: context,
      builder: (context) => QuickUploadDialog(
        script: record,
      ),
    );
    
    if (uploaded == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script published successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _viewInMarketplace(ScriptRecord record) {
    // Switch to marketplace tab
    _tabController.animateTo(1);
    
    // Show a snackbar to indicate the action
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to Marketplace to find "${record.title}"'),
        duration: const Duration(seconds: 2),
      ),
    );
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
      body: Stack(
        children: [
          Column(
            children: [
              // Tab bar
              Container(
                color: Theme.of(context).colorScheme.surface,
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(icon: Icon(Icons.code), text: 'My Scripts'),
                    Tab(icon: Icon(Icons.store), text: 'Marketplace'),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                ),
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMyScriptsTab(scripts),
                    _buildMarketplaceTab(),
                  ],
                ),
              ),
            ],
          ),
          // Positioned FAB above navigation bar with better spacing
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 90, // Better spacing from navigation bar
            child: _tabController.index == 0 
              ? AnimatedFab(
                  heroTag: 'scripts_fab',
                  onPressed: _controller.isBusy ? null : _showCreateSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: 'New Script',
                )
              : AnimatedFab(
                  heroTag: 'marketplace_fab',
                  onPressed: () => _showUploadScriptDialog(context),
                  icon: const Icon(Icons.upload_rounded),
                  label: 'Upload Script',
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyScriptsTab(List<ScriptRecord> scripts) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isBusy && scripts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (scripts.isEmpty && !_controller.isBusy) {
          return ModernEmptyState(
            icon: Icons.code_rounded,
            title: 'Your Script Library is Empty',
            subtitle: 'Start building amazing ICP scripts with our intuitive editor and powerful marketplace',
            action: _showCreateSheet,
            actionLabel: 'Create Your First Script',
          );
        }

        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: ListView.separated(
            padding: EdgeInsets.only(
              bottom: 100, // Consistent space for FAB
              top: 8,
              left: 8,
              right: 8,
            ),
            itemCount: scripts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final ScriptRecord rec = scripts[index];
              final screenWidth = MediaQuery.of(context).size.width;
              final isCompactScreen = screenWidth < 380;
              
              return Dismissible(
                key: ValueKey<String>(rec.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: const <Widget>[
                      Icon(Icons.delete),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  await _controller.deleteScript(rec.id);
                  return false;
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isCompactScreen ? 12 : 16,
                      vertical: 4,
                    ),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: isCompactScreen ? 20 : 24,
                          child: Text(
                            (rec.emoji ?? '📜').characters.first,
                            style: TextStyle(
                              fontSize: isCompactScreen ? 16 : 20,
                            ),
                          ),
                        ),
                        if (_isPublishedToMarketplace(rec))
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: isCompactScreen ? 14 : 16,
                              height: isCompactScreen ? 14 : 16,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(
                                Icons.cloud_upload,
                                size: isCompactScreen ? 8 : 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                rec.title,
                                style: TextStyle(
                                  fontSize: isCompactScreen ? 14 : 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (_isPublishedToMarketplace(rec)) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompactScreen ? 4 : 6, 
                                  vertical: isCompactScreen ? 1 : 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  'Published',
                                  style: TextStyle(
                                    fontSize: isCompactScreen ? 8 : 10,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: isCompactScreen ? 2 : 4),
                        Text(
                          'Updated ${rec.updatedAt.toLocal()}',
                          style: TextStyle(
                            fontSize: isCompactScreen ? 11 : 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      showDialog<void>(
                        context: context,
                                  builder: (_) => _ScriptEditorDialog(controller: _controller, record: rec),
                      );
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Quick action buttons - only show on larger screens
                        if (!isCompactScreen) ...[
                          IconButton(
                            tooltip: 'Run Script',
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _runScript(rec),
                          ),
                          
                          // Quick publish button for scripts not yet published
                          if (!_isPublishedToMarketplace(rec))
                            IconButton(
                              tooltip: 'Publish to Marketplace',
                              icon: const Icon(Icons.cloud_upload),
                              onPressed: () => _publishToMarketplace(rec),
                            ),
                        ],
                        
                        // More actions menu - always show
                        PopupMenuButton<int>(
                          tooltip: 'More Actions',
                          icon: Icon(
                            Icons.more_vert,
                            size: isCompactScreen ? 20 : 24,
                          ),
                          itemBuilder: (BuildContext context) {
                            final List<PopupMenuEntry<int>> items = [
                              const PopupMenuItem<int>(value: 1, child: Text('Edit details…')),
                              const PopupMenuItem<int>(value: 2, child: Text('Edit code…')),
                            ];
                            
                            if (!_isPublishedToMarketplace(rec)) {
                              items.add(const PopupMenuItem<int>(value: 3, child: Text('Publish to Marketplace')));
                            } else {
                              items.add(const PopupMenuItem<int>(value: 4, child: Text('View in Marketplace')));
                            }
                            
                            items.add(const PopupMenuItem<int>(value: 5, child: Text('Duplicate')));
                            items.add(const PopupMenuItem<int>(value: 6, child: Text('Export')));
                            items.add(const PopupMenuDivider());
                            items.add(const PopupMenuItem<int>(value: 7, child: Text('Delete')));
                            
                            return items;
                          },
                          onSelected: (int value) {
                            switch (value) {
                              case 1:
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => _ScriptDetailsDialog(controller: _controller, record: rec),
                                );
                                break;
                              case 2:
                                showDialog<void>(
                                  context: context,
                        builder: (_) => _ScriptEditorDialog(controller: _controller, record: rec),
                                );
                                break;
                              case 3:
                                _publishToMarketplace(rec);
                                break;
                              case 4:
                                _viewInMarketplace(rec);
                                break;
                              case 5:
                                _duplicateScript(rec);
                                break;
                              case 6:
                                _exportScript(rec);
                                break;
                              case 7:
                                _confirmAndDeleteScript(rec);
                                break;
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMarketplaceTab() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryFilter(),
        Expanded(
          child: _buildMarketplaceContent(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: MarketplaceSearchBar(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onClear: () {
          _searchController.clear();
          _onSearchChanged('');
        },
      ),
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

  Widget _buildMarketplaceContent() {
    if (_isMarketplaceLoading && _marketplaceScripts.isEmpty) {
      return const LoadingIndicator(message: 'Loading scripts...');
    }

    if (_marketplaceError != null && _marketplaceScripts.isEmpty) {
      return ErrorDisplay(
        error: _marketplaceError!,
        onRetry: _refreshMarketplaceScripts,
      );
    }

    if (_marketplaceScripts.isEmpty) {
      return ModernEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No Scripts Found',
        subtitle: 'Try adjusting your search terms or browse different categories to discover amazing scripts',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshMarketplaceScripts,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.extentAfter < 200 &&
              _hasMore &&
              !_isLoadingMore) {
            _loadMarketplaceScripts(isLoadMore: true);
          }
          return false;
        },
        child:         GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            childAspectRatio: 1.0,
            crossAxisSpacing: 16.0,
            mainAxisSpacing: 16.0,
          ),
          itemCount: _marketplaceScripts.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _marketplaceScripts.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final script = _marketplaceScripts[index];
            final isDownloading = _downloadingScriptIds.contains(script.id);
            final isDownloaded = _downloadedScriptIds.contains(script.id);
            
            return Stack(
              children: [
                ScriptCard(
                  script: script,
                  onTap: () => _showScriptDetails(context, script),
                  onDownload: script.price == 0 ? () => _downloadScript(script) : null,
                  isDownloading: isDownloading,
                  isDownloaded: isDownloaded,
                  onQuickPreview: () => _showScriptDetails(context, script),
                  onShare: () => _shareScript(context, script),
                ),
                // Download progress overlay
                if (isDownloading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Downloading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Downloaded indicator
                if (isDownloaded && !isDownloading)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _shareScript(BuildContext context, MarketplaceScript script) {
    // For now, just copy the script URL to clipboard
    // In a real implementation, you would generate a shareable link
    final shareUrl = 'https://icp-marketplace.com/scripts/${script.id}';
    
    Clipboard.setData(ClipboardData(text: shareUrl)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script link copied to clipboard!'),
          backgroundColor: Colors.green,
        ),
      );
    });
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
     final safeAreaPadding = MediaQuery.of(context).padding;
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
               padding: EdgeInsets.symmetric(horizontal: isCompactScreen ? 12 : 16, vertical: 8),
               decoration: BoxDecoration(
                 color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:0.5),
                 border: Border(
                   bottom: BorderSide(
                     color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
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
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  const _NewScriptDetailsDialog({required this.controller, required this.luaSource});
  final ScriptController controller;
  final String luaSource;

  @override
  State<_NewScriptDetailsDialog> createState() => _NewScriptDetailsDialogState();
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
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
        luaSourceOverride: widget.luaSource,
      );
      if (!mounted) return;
      Navigator.of(context).pop(rec);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiController,
                decoration: const InputDecoration(labelText: 'Emoji (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(labelText: 'Image URL (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Provide either an emoji or an image URL', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _isSubmitting ? null : _save, child: const Text('Create script')),
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
    _imageUrlController = TextEditingController(text: widget.record.imageUrl ?? '');
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
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiController,
                decoration: const InputDecoration(labelText: 'Emoji (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(labelText: 'Image URL (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Provide either an emoji or an image URL', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _isSubmitting ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Dialog for selecting a script template when creating a new script
class _ScriptTemplateSelectionDialog extends StatefulWidget {
  @override
  State<_ScriptTemplateSelectionDialog> createState() => _ScriptTemplateSelectionDialogState();
}

class _ScriptTemplateSelectionDialogState extends State<_ScriptTemplateSelectionDialog> {
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
                    ButtonSegment(value: 'intermediate', label: Text('Intermediate')),
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
                          Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No templates found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search or filters',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    final defaultTemplate = ScriptTemplates.templates.firstWhere(
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getLevelColor(template.level, colorScheme),
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
                              Icon(Icons.star, size: 16, color: Colors.amber[600]),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
