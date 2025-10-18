import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef UiEventHandler = void Function(Map<String, dynamic> msg);

class UiV1Renderer extends StatelessWidget {
  const UiV1Renderer({super.key, required this.ui, required this.onEvent});
  final Map<String, dynamic> ui; // root node { type, props?, children? }
  final UiEventHandler onEvent;

  @override
  Widget build(BuildContext context) {
    return _buildNode(context, ui);
  }

  Widget _buildNode(BuildContext context, Map<String, dynamic> node) {
    final String type = (node['type'] as String? ?? '').trim();
    if (type.isEmpty) {
      return _error('UI node missing type');
    }
    final Map<String, dynamic> props = (node['props'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rawChildren = (node['children'] as List<dynamic>?) ?? const <dynamic>[];
    final List<Widget> children = rawChildren
        .whereType<Map<String, dynamic>>()
        .map((m) => _buildNode(context, m))
        .toList(growable: false);

    switch (type) {
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
      case 'row':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
      case 'section':
        final String title = (props['title'] ?? '').toString();
        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                ...children,
              ],
            ),
          ),
        );
      case 'text':
        final String text = (props['text'] ?? '').toString();
        final bool copyable = (props['copy'] as bool?) ?? false;
        final String copyLabel = (props['copy_label'] ?? 'Copy').toString();
        final String copyValue = (props['copy_value'] ?? text).toString();
        if (!copyable && (props['copy_value'] == null)) {
          return Text(text);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Expanded(child: Text(text)),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: copyLabel,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyValue));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$copyLabel to clipboard')));
              },
            ),
          ],
        );
      case 'button':
        final String label = (props['label'] ?? 'Run').toString();
        final bool disabled = (props['disabled'] as bool?) ?? false;
        final Map<String, dynamic>? onPress = props['on_press'] as Map<String, dynamic>?;
        return Padding(
          padding: const EdgeInsets.all(4),
          child: FilledButton(
            onPressed: disabled || onPress == null ? null : () => onEvent(onPress),
            child: Text(label),
          ),
        );
      case 'list':
        final dynamic rawItems = props['items'];
        final List<dynamic> items;
        if (rawItems == null) {
          items = const <dynamic>[];
        } else if (rawItems is List<dynamic>) {
          items = rawItems;
        } else {
          return _error('List items must be an array');
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final dynamic item = items[index];
            if (item is Map<String, dynamic>) {
              final String title = (item['title'] ?? '').toString();
              final String? subtitle = (item['subtitle'] as String?);
              final bool copyable = (item['copy'] as bool?) ?? false;
              final String copyLabel = (item['copy_label'] ?? 'Copy').toString();
              final String copyValue = (item['copy_value'] ?? (subtitle?.isNotEmpty == true ? subtitle! : title)).toString();
              return ListTile(
                title: Text(title),
                subtitle: (subtitle == null || subtitle.isEmpty) ? null : Text(subtitle),
                trailing: (copyable || item.containsKey('copy_value'))
                    ? IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: copyLabel,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: copyValue));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$copyLabel to clipboard')));
                        },
                      )
                    : null,
              );
            }
            return ListTile(title: Text(item.toString()));
          },
        );
      default:
        return _error('Unsupported node type: $type');
    }
  }

  Widget _error(String message) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB00020)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFB00020))),
    );
  }
}
