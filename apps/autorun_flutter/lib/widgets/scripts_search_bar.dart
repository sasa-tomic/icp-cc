import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
///
/// CR-7: when the recent-searches dropdown is visible, ↑/↓ navigates the
/// highlight and Enter selects — fully keyboard-reachable.
class ScriptsSearchBar extends StatefulWidget {
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
  State<ScriptsSearchBar> createState() => _ScriptsSearchBarState();
}

class _ScriptsSearchBarState extends State<ScriptsSearchBar> {
  int _highlightedIndex = -1;

  List<String> get _visibleSearches => widget.recentSearches.take(5).toList();

  @override
  void initState() {
    super.initState();
    widget.searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.searchFocusNode.hasFocus) {
      _resetHighlight();
    }
  }

  void _resetHighlight() {
    if (_highlightedIndex != -1) {
      setState(() => _highlightedIndex = -1);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.showRecentSearches || _visibleSearches.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final searches = _visibleSearches;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % searches.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = _highlightedIndex <= 0
            ? searches.length - 1
            : _highlightedIndex - 1;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _highlightedIndex >= 0 &&
        _highlightedIndex < searches.length) {
      widget.onSelectRecentSearch(searches[_highlightedIndex]);
      _resetHighlight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _resetHighlight();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: _buildConsolidatedSearchBar(context),
        ),
        if (widget.activeFilterCount > 0) _buildActiveFilterChips(),
        if (widget.showRecentSearches && widget.recentSearches.isNotEmpty)
          _buildRecentSearchesDropdown(context),
        if (widget.isSearching) const LinearProgressIndicator(minHeight: 2),
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
              children: widget.activeFilters
                  .map((filter) => _ActiveFilterChip(
                        label: filter.label,
                        onDismiss: filter.onDismiss,
                      ))
                  .toList(),
            ),
          ),
          if (widget.activeFilters.length > 1) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: widget.onClearAllFilters,
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
    final searches = _visibleSearches;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
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
            ...searches.asMap().entries.map((entry) {
              final index = entry.key;
              final query = entry.value;
              final isHighlighted = index == _highlightedIndex;
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(query),
                tileColor: isHighlighted
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12)
                    : null,
                onTap: () {
                  widget.onSelectRecentSearch(query);
                  _resetHighlight();
                },
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => widget.onRemoveRecentSearch(query),
                  tooltip: 'Remove',
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildConsolidatedSearchBar(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: Row(
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
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                onChanged: (value) {
                  _resetHighlight();
                  widget.onSearchChanged(value);
                },
                decoration: InputDecoration(
                  hintText: 'Search scripts...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: widget.searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            widget.searchController.clear();
                            widget.onSearchChanged('');
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
          _buildFilterButton(context, widget.activeFilterCount),
        ],
      ),
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
            onPressed: widget.onFilterButtonPressed,
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
