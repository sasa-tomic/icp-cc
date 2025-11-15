import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/marketplace_script.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/download_history_service.dart';
import '../controllers/script_controller.dart';
import '../services/script_repository.dart';
import '../widgets/marketplace_search_bar.dart';
import '../widgets/script_card.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/error_display.dart';
import '../widgets/script_details_dialog.dart';
import 'download_history_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final MarketplaceOpenApiService _marketplaceService = MarketplaceOpenApiService();
  final DownloadHistoryService _downloadHistoryService = DownloadHistoryService();
  final TextEditingController _searchController = TextEditingController();
  late final ScriptController _scriptController;

  List<MarketplaceScript> _scripts = [];
  List<String> _categories = [];
  final Set<String> _downloadingScriptIds = <String>{};
  Set<String> _downloadedScriptIds = {};
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  int _offset = 0;
  bool _hasMore = true;

  String _selectedCategory = 'All';
  String _sortBy = 'createdAt';
  String _sortOrder = 'desc';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scriptController = ScriptController(ScriptRepository())..addListener(_onChanged);
    _initializeMarketplace();
    _loadScripts();
    _loadCategories();
    _loadDownloadedScripts();
  }

  Future<void> _initializeMarketplace() async {
    try {
      // No initialization needed for open API service
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize marketplace: $e';
      });
    }
  }

  Future<void> _loadScripts({bool isLoadMore = false}) async {
    if (isLoadMore && (_isLoadingMore || !_hasMore)) return;
    if (!isLoadMore && _isLoading) return;

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _error = null;
        _offset = 0;
        _scripts.clear();
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
          _scripts.addAll(result.scripts);
        } else {
          _scripts = result.scripts;
        }
                _hasMore = result.hasMore;
        _offset += result.scripts.length;
      });

    } catch (e) {
      setState(() {
        _error = _formatErrorMessage(e.toString());
      });
    } finally {
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = false;
        } else {
          _isLoading = false;
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

  Future<void> _refreshScripts() async {
    await _loadScripts();
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _debouncedSearch();
  }

  void _debouncedSearch() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchController.text == _searchQuery) {
        _loadScripts();
      }
    });
  }

  void _onCategoryChanged(String category) {
    setState(() {
      _selectedCategory = category;
    });
    _loadScripts();
  }

  void _onSortChanged(String sortBy, String sortOrder) {
    setState(() {
      _sortBy = sortBy;
      _sortOrder = sortOrder;
    });
    _loadScripts();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
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
      final createdScript = await _scriptController.createScript(
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

      // Show success feedback with more options
      if (mounted) {
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
              label: 'View Script',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to scripts tab and scroll to new script
                DefaultTabController.of(context).animateTo(0);
              },
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
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Script Marketplace'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => _navigateToDownloadHistory(context),
            tooltip: 'Download Library',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'download_history') {
                _navigateToDownloadHistory(context);
              } else {
                final parts = value.split('_');
                if (parts.length == 2) {
                  _onSortChanged(parts[0], parts[1]);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'download_history',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline_outlined),
                    SizedBox(width: 8),
                    Text('Download Library'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'createdAt_desc',
                child: Text('Newest First'),
              ),
              const PopupMenuItem(
                value: 'createdAt_asc',
                child: Text('Oldest First'),
              ),
              const PopupMenuItem(
                value: 'rating_desc',
                child: Text('Highest Rated'),
              ),
              const PopupMenuItem(
                value: 'downloads_desc',
                child: Text('Most Downloaded'),
              ),
              const PopupMenuItem(
                value: 'price_asc',
                child: Text('Price: Low to High'),
              ),
              const PopupMenuItem(
                value: 'price_desc',
                child: Text('Price: High to Low'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryFilter(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
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

  Widget _buildContent() {
    if (_isLoading && _scripts.isEmpty) {
      return const LoadingIndicator(message: 'Loading scripts...');
    }

    if (_error != null && _scripts.isEmpty) {
      return ErrorDisplay(
        error: _error!,
        onRetry: _refreshScripts,
      );
    }

    if (_scripts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No scripts found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshScripts,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.extentAfter < 200 &&
              _hasMore &&
              !_isLoadingMore) {
            _loadScripts(isLoadMore: true);
          }
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            childAspectRatio: 1.0,
            crossAxisSpacing: 16.0,
            mainAxisSpacing: 16.0,
          ),
          itemCount: _scripts.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _scripts.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final script = _scripts[index];
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
                  onQuickPreview: () => _showQuickPreview(context, script),
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

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Advanced Search'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search scripts...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (value) {
                Navigator.pop(context);
                _onSearchChanged(value);
              },
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCategory = value;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadScripts();
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
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

  void _navigateToDownloadHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const DownloadHistoryScreen(),
      ),
    );
  }

  void _showQuickPreview(BuildContext context, MarketplaceScript script) {
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

  void _shareScript(BuildContext context, MarketplaceScript script) async {
    // For now, just copy the script URL to clipboard
    // In a real implementation, you would generate a shareable link
    final shareUrl = 'https://icp-marketplace.com/scripts/${script.id}';

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

  @override
  void dispose() {
    _searchController.dispose();
    _scriptController
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }
}
