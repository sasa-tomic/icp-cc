import 'package:flutter/material.dart';

import '../models/script_list_item.dart';

/// Filter bottom sheet containing category and sort options.
class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.sortOption,
    required this.sortAscending,
    required this.showDownloadedOnly,
    required this.showFavoritesOnly,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onDownloadedFilterChanged,
    required this.onFavoritesFilterChanged,
    required this.onReset,
  });

  final List<String> categories;
  final String selectedCategory;
  final ScriptSortOption sortOption;
  final bool sortAscending;
  final bool showDownloadedOnly;
  final bool showFavoritesOnly;
  final ValueChanged<String> onCategoryChanged;
  final void Function(ScriptSortOption, bool) onSortChanged;
  final ValueChanged<bool> onDownloadedFilterChanged;
  final ValueChanged<bool> onFavoritesFilterChanged;
  final VoidCallback onReset;

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _selectedCategory;
  late ScriptSortOption _sortOption;
  late bool _sortAscending;
  late bool _showDownloadedOnly;
  late bool _showFavoritesOnly;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.selectedCategory;
    _sortOption = widget.sortOption;
    _sortAscending = widget.sortAscending;
    _showDownloadedOnly = widget.showDownloadedOnly;
    _showFavoritesOnly = widget.showFavoritesOnly;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                TextButton.icon(
                  onPressed: widget.onReset,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Category',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.categories.map((category) {
                final isSelected = category == _selectedCategory;
                return FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category;
                    });
                    widget.onCategoryChanged(category);
                  },
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.primary,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'Source',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            FilterChip(
              label: const Text('Downloaded'),
              selected: _showDownloadedOnly,
              onSelected: (selected) {
                setState(() {
                  _showDownloadedOnly = selected;
                });
                widget.onDownloadedFilterChanged(selected);
              },
              selectedColor: colorScheme.primaryContainer,
              checkmarkColor: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Favorites'),
              selected: _showFavoritesOnly,
              onSelected: (selected) {
                setState(() {
                  _showFavoritesOnly = selected;
                });
                widget.onFavoritesFilterChanged(selected);
              },
              selectedColor: colorScheme.primaryContainer,
              checkmarkColor: colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Sort by',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ScriptSortOption>(
                    initialValue: _sortOption,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: ScriptSortOption.values
                        .map((opt) => DropdownMenuItem(
                              value: opt,
                              child: Text(opt.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _sortOption = value;
                        });
                        widget.onSortChanged(_sortOption, _sortAscending);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _sortAscending = !_sortAscending;
                    });
                    widget.onSortChanged(_sortOption, _sortAscending);
                  },
                  icon: Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                  tooltip: _sortAscending ? 'Ascending' : 'Descending',
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
