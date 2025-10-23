import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef UiEventHandler = void Function(Map<String, dynamic> msg);

/// Widget for displaying canister call results with various formatting options
class ResultDisplay extends StatelessWidget {
  const ResultDisplay({
    super.key,
    required this.data,
    this.title,
    this.error,
    this.isExpandable = true,
    this.initiallyExpanded = false,
  });

  final dynamic data;
  final String? title;
  final String? error;
  final bool isExpandable;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (isExpandable)
                    _buildExpandButton(context),
                ],
              ),
            ),
          if (error != null)
            _buildErrorSection(context)
          else
            _buildDataSection(context),
        ],
      ),
    );
  }

  Widget _buildExpandButton(BuildContext context) {
    return ExpandIcon(
      isExpanded: initiallyExpanded,
      onPressed: (bool expanded) {
        // In a real implementation, you'd want to manage the expansion state
        // For now, this is just a visual indicator
      },
    );
  }

  Widget _buildErrorSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: error!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Error'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDataActions(context),
          const SizedBox(height: 12),
          _buildDataContent(context),
        ],
      ),
    );
  }

  Widget _buildDataActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (data is Map || data is List)
          TextButton.icon(
            onPressed: () => _exportAsJson(context),
            icon: const Icon(Icons.code, size: 16),
            label: const Text('JSON'),
          ),
        if (data is Map)
          TextButton.icon(
            onPressed: () => _exportAsCsv(context),
            icon: const Icon(Icons.table_chart, size: 16),
            label: const Text('CSV'),
          ),
        TextButton.icon(
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy'),
        ),
      ],
    );
  }

  Widget _buildDataContent(BuildContext context) {
    if (data == null) {
      return const Text('No data');
    }

    // Handle different data types
    if (data is Map) {
      return _buildMapDisplay(context, data);
    } else if (data is List) {
      return _buildListDisplay(context, data);
    } else if (data is String) {
      return _buildStringDisplay(context, data);
    } else if (data is num) {
      return _buildNumberDisplay(context, data);
    } else {
      return _buildGenericDisplay(context, data);
    }
  }

  Widget _buildMapDisplay(BuildContext context, Map<String, dynamic> map) {
    if (map.isEmpty) {
      return const Text('Empty object', style: TextStyle(fontStyle: FontStyle.italic));
    }

    // Check if this looks like a table-like structure
    if (_isTableLike(map)) {
      return _buildTableDisplay(context, map);
    }

    // Regular map display
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: map.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '${entry.key}:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: _buildValueDisplay(context, entry.value),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildListDisplay(BuildContext context, List list) {
    if (list.isEmpty) {
      return const Text('Empty array', style: TextStyle(fontStyle: FontStyle.italic));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.asMap().entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[${entry.key}]: ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: _buildValueDisplay(context, entry.value),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildValueDisplay(BuildContext context, dynamic value) {
    if (value is Map || value is List) {
      return ExpansionTile(
        title: Text(
          value is Map ? 'Object (${value.length} keys)' : 'Array (${value.length} items)',
          style: const TextStyle(fontSize: 14),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
            child: SelectableText(
              _formatValue(value),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    } else {
      return SelectableText(
        _formatValue(value),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      );
    }
  }

  Widget _buildStringDisplay(BuildContext context, String text) {
    // Check if it's a long string that might benefit from expansion
    if (text.length > 200) {
      return ExpansionTile(
        title: Text(
          'String (${text.length} characters)',
          style: const TextStyle(fontSize: 14),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      );
    }

    // Check if it might be a JSON string
    try {
      final parsed = json.decode(text);
      return _buildValueDisplay(context, parsed);
    } catch (_) {
      // Not JSON, display as regular text
      return SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      );
    }
  }

  Widget _buildNumberDisplay(BuildContext context, num number) {
    return SelectableText(
      number.toString(),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildGenericDisplay(BuildContext context, dynamic value) {
    return SelectableText(
      value.toString(),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
    );
  }

  Widget _buildTableDisplay(BuildContext context, Map<String, dynamic> map) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Table View (${map.length} rows)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: map.keys.map((key) {
              return DataColumn(
                label: Text(
                  key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            rows: [
              DataRow(
                cells: map.values.map((value) {
                  return DataCell(
                    Text(
                      _formatValue(value),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isTableLike(Map<String, dynamic> map) {
    // Consider it table-like only if it has many entries and all values are primitives
    // Small objects (like user profiles) should use regular map display
    return map.length >= 5 && map.values.every((value) =>
        value is String || value is num || value is bool || value == null);
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    return json.encode(value);
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _formatValue(data)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data copied to clipboard')),
    );
  }

  void _exportAsJson(BuildContext context) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    Clipboard.setData(ClipboardData(text: jsonString));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copied to clipboard')),
    );
  }

  void _exportAsCsv(BuildContext context) {
    if (data is Map) {
      final map = data as Map<String, dynamic>;
      final csv = [
        map.keys.join(','), // Header
        map.values.map((v) => _formatValue(v)).join(','), // Row
      ].join('\n');

      Clipboard.setData(ClipboardData(text: csv));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
    }
  }
}

/// Enhanced result list with filtering and search capabilities
class EnhancedResultList extends StatefulWidget {
  const EnhancedResultList({
    super.key,
    required this.items,
    this.title = 'Results',
    this.searchable = true,
    this.onEvent,
  });

  final List<Map<String, dynamic>> items;
  final String title;
  final bool searchable;
  final UiEventHandler? onEvent;

  @override
  State<EnhancedResultList> createState() => _EnhancedResultListState();
}

class _EnhancedResultListState extends State<EnhancedResultList> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      if (_searchController.text.isEmpty) {
        _filteredItems = widget.items;
      } else {
        final query = _searchController.text.toLowerCase();
        _filteredItems = widget.items.where((item) {
          return item.values.any((value) =>
              value.toString().toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${_filteredItems.length}/${widget.items.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (widget.searchable && widget.items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search results...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_filteredItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No results found',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return ListTile(
                    title: Text(item['title']?.toString() ?? 'Item ${index + 1}'),
                    subtitle: item['subtitle'] != null
                        ? Text(
                            item['subtitle'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => _handleItemAction(context, action, item),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.copy, size: 16),
                              SizedBox(width: 8),
                              Text('Copy'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16),
                              SizedBox(width: 8),
                              Text('View Details'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _handleItemAction(BuildContext context, String action, Map<String, dynamic> item) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: json.encode(item)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item copied to clipboard')),
        );
        // Trigger event for test purposes
        widget.onEvent?.call({
          'type': 'copy',
          'item': item,
          'action': 'copy'
        });
        break;
      case 'details':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(item['title']?.toString() ?? 'Details'),
            content: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(item),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        break;
    }
  }
}