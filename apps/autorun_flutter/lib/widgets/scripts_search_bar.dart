import 'package:flutter/material.dart';

/// A label + dismiss-callback pair describing one active filter chip rendered
/// below the Scripts search bar.
class ScriptsActiveFilter {
  const ScriptsActiveFilter({
    required this.label,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onDismiss;
}

/// The consolidated search/filter bar for the Scripts screen.
///
/// Pure extraction of the `ScriptsScreenState._buildSearchBar` family of
/// methods (`_buildConsolidatedSearchBar`, `_buildFilterButton`,
/// `_buildActiveFilterChips`, `_buildRecentSearchesDropdown`). All state
/// (filter values, recent searches, searching flag) and all side effects
/// (search-history mutation, filter popover, marketplace reload) stay in the
/// caller; this widget only renders what it is given.
class ScriptsSearchBar extends StatelessWidget {
  const ScriptsSearchBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.activeFilterCount,
    required this.activeFilters,
    required this.onClearAllFilters,
    required this.onFilterButtonPressed,
    required this.showRecentSearches,
    required this.recentSearches,
    required this.onSelectRecentSearch,
    required this.onRemoveRecentSearch,
    required this.isSearching,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final int activeFilterCount;
  final List<ScriptsActiveFilter> activeFilters;
  final VoidCallback onClearAllFilters;
  final VoidCallback onFilterButtonPressed;
  final bool showRecentSearches;
  final List<String> recentSearches;
  final ValueChanged<String> onSelectRecentSearch;
  final ValueChanged<String> onRemoveRecentSearch;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: _buildConsolidatedSearchBar(context),
        ),
        if (activeFilterCount > 0) _buildActiveFilterChips(),
        if (showRecentSearches && recentSearches.isNotEmpty)
          _buildRecentSearchesDropdown(context),
        if (isSearching) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildActiveFilterChips() {
    return Container(
      key: const Key('active_filter_chips'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: activeFilters
                  .map((filter) => _ActiveFilterChip(
                        label: filter.label,
                        onDismiss: filter.onDismiss,
                      ))
                  .toList(),
            ),
          ),
          if (activeFilters.length > 1) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onClearAllFilters,
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

  Widget _buildRecentSearchesDropdown(BuildContext context) {
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
          ...(recentSearches.take(5).map((query) => ListTile(
                dense: true,
                leading: Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(query),
                onTap: () => onSelectRecentSearch(query),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => onRemoveRecentSearch(query),
                  tooltip: 'Remove',
                ),
              ))),
        ],
      ),
    );
  }

  Widget _buildConsolidatedSearchBar(BuildContext context) {
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
              controller: searchController,
              focusNode: searchFocusNode,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search scripts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
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
        _buildFilterButton(context, activeFilterCount),
      ],
    );
  }

  /// Filter button with a badge showing the active filter count.
  Widget _buildFilterButton(BuildContext context, int activeCount) {
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
            onPressed: onFilterButtonPressed,
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
