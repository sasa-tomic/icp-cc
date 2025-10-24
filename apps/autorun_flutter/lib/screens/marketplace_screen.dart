import 'package:flutter/material.dart';
import '../models/marketplace_script.dart';
import '../services/marketplace_open_api_service.dart';
import '../widgets/marketplace_search_bar.dart';
import '../widgets/script_card.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/error_display.dart';
import 'script_upload_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final MarketplaceOpenApiService _marketplaceService = MarketplaceOpenApiService();
  final TextEditingController _searchController = TextEditingController();

  List<MarketplaceScript> _scripts = [];
  List<String> _categories = [];
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
    _initializeMarketplace();
    _loadScripts();
    _loadCategories();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Script Marketplace'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              final parts = value.split('_');
              if (parts.length == 2) {
                _onSortChanged(parts[0], parts[1]);
              }
            },
            itemBuilder: (context) => [
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadScriptDialog(context),
        child: const Icon(Icons.add),
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
            crossAxisCount: 2,
            childAspectRatio: 0.75,
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
            return ScriptCard(
              script: script,
              onTap: () => _showScriptDetails(context, script),
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
    Navigator.pushNamed(
      context,
      '/script_details',
      arguments: script,
    );
  }

  void _showUploadScriptDialog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ScriptUploadScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}