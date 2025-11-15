import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'result_display.dart';

typedef UiEventHandler = void Function(Map<String, dynamic> msg);

/// Convert mixed-type list items to Map format for EnhancedResultList
List<Map<String, dynamic>> _normalizeItemsForEnhancedList(List<dynamic> items) {
  return items.map((item) {
    if (item is Map<String, dynamic>) {
      return item;
    }

    // Convert primitive types to map format
    if (item == null) {
      return {
        'title': 'null',
        'subtitle': 'Null value',
        'data': {'original': null}
      };
    }

    if (item is String) {
      return {
        'title': item,
        'subtitle': 'String value',
        'data': {'original': item, 'type': 'string'}
      };
    }

    if (item is num) {
      return {
        'title': item.toString(),
        'subtitle': 'Number value',
        'data': {'original': item, 'type': 'number'}
      };
    }

    if (item is bool) {
      return {
        'title': item.toString(),
        'subtitle': 'Boolean value',
        'data': {'original': item, 'type': 'boolean'}
      };
    }

    // Fallback for other types
    return {
      'title': item.toString(),
      'subtitle': '${item.runtimeType} value',
      'data': {'original': item}
    };
  }).cast<Map<String, dynamic>>().toList();
}

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
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
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
      case 'text_field':
        final String label = (props['label'] ?? '').toString();
        final String value = (props['value'] ?? '').toString();
        final String placeholder = (props['placeholder'] ?? '').toString();
        final bool enabled = (props['enabled'] as bool?) ?? true;
        final bool obscure = (props['obscure'] as bool?) ?? false;
        final String? keyboardType = props['keyboard_type'] as String?;
        final Map<String, dynamic>? onChange = props['on_change'] as Map<String, dynamic>?;
        final Map<String, dynamic>? onSubmit = props['on_submit'] as Map<String, dynamic>?;

        return Padding(
          padding: const EdgeInsets.all(4),
          child: TextFormField(
            initialValue: value,
            enabled: enabled,
            obscureText: obscure,
            keyboardType: _getKeyboardType(keyboardType),
            decoration: InputDecoration(
              labelText: label.isEmpty ? null : label,
              hintText: placeholder.isEmpty ? null : placeholder,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChange != null ? (newValue) {
              final msg = Map<String, dynamic>.from(onChange);
              msg['value'] = newValue;
              onEvent(msg);
            } : null,
            onFieldSubmitted: onSubmit != null ? (newValue) {
              final msg = Map<String, dynamic>.from(onSubmit);
              msg['value'] = newValue;
              onEvent(msg);
            } : null,
          ),
        );
      case 'toggle':
        final String label = (props['label'] ?? '').toString();
        final bool value = (props['value'] as bool?) ?? false;
        final bool enabled = (props['enabled'] as bool?) ?? true;
        final Map<String, dynamic>? onChange = props['on_change'] as Map<String, dynamic>?;

        return Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Switch(
                value: value,
                onChanged: enabled && onChange != null ? (newValue) {
                  final msg = Map<String, dynamic>.from(onChange);
                  msg['value'] = newValue;
                  onEvent(msg);
                } : null,
              ),
            ],
          ),
        );
      case 'select':
        final String label = (props['label'] ?? '').toString();
        final String value = (props['value'] ?? '').toString();
        final List<dynamic> options = (props['options'] as List<dynamic>?) ?? <dynamic>[];
        final bool enabled = (props['enabled'] as bool?) ?? true;
        final Map<String, dynamic>? onChange = props['on_change'] as Map<String, dynamic>?;

        return Padding(
          padding: const EdgeInsets.all(4),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: label.isEmpty ? null : label,
              border: const OutlineInputBorder(),
            ),
            items: options.map((option) {
              final String optionValue = (option is Map<String, dynamic>)
                  ? (option['value'] ?? '').toString()
                  : option.toString();
              final String optionLabel = (option is Map<String, dynamic>)
                  ? (option['label'] ?? optionValue).toString()
                  : option.toString();
              return DropdownMenuItem<String>(
                value: optionValue,
                child: Text(optionLabel),
              );
            }).toList(),
            initialValue: value.isEmpty ? null : value,
            onChanged: enabled && onChange != null ? (newValue) {
              if (newValue != null) {
                final msg = Map<String, dynamic>.from(onChange);
                msg['value'] = newValue;
                onEvent(msg);
              }
            } : null,
          ),
        );
      case 'image':
        final String src = (props['src'] ?? '').toString();
        final double? width = (props['width'] as num?)?.toDouble();
        final double? height = (props['height'] as num?)?.toDouble();
        final BoxFit fit = _getBoxFit(props['fit'] as String?);

        if (src.isEmpty) {
          return _error('Image widget requires src property');
        }

        Widget imageWidget;
        if (src.startsWith('local://')) {
          // For local resources, we'd need to implement asset loading
          imageWidget = Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image, size: 32, color: Colors.grey),
                  SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Local image\n${src.substring(7)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Network image
          imageWidget = Image.network(
            src,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, size: 32, color: Colors.red),
                      SizedBox(height: 4),
                      Text('Failed to load',
                           textAlign: TextAlign.center,
                           style: TextStyle(fontSize: 12, color: Colors.red)),
                    ],
                  ),
                ),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          );
        }

        return Padding(
          padding: const EdgeInsets.all(4),
          child: imageWidget,
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

        // Check if we should use the enhanced list view
        final bool enhanced = (props['enhanced'] as bool?) ?? false;
        final bool searchable = (props['searchable'] as bool?) ?? true;
        final String title = (props['title'] ?? 'Results').toString();

        if (enhanced) {
          return EnhancedResultList(
            items: _normalizeItemsForEnhancedList(items),
            title: title,
            searchable: searchable,
            onEvent: onEvent,
          );
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
      case 'result_display':
        final dynamic data = props['data'];
        final String? title = props['title'] as String?;
        final String? error = props['error'] as String?;
        final bool isExpandable = (props['expandable'] as bool?) ?? true;
        final bool initiallyExpanded = (props['expanded'] as bool?) ?? false;

        return ResultDisplay(
          data: data,
          title: title,
          error: error,
          isExpandable: isExpandable,
          initiallyExpanded: initiallyExpanded,
        );
      default:
        return _error('Unsupported node type: $type');
    }
  }

  TextInputType _getKeyboardType(String? type) {
    switch (type) {
      case 'email':
        return TextInputType.emailAddress;
      case 'phone':
        return TextInputType.phone;
      case 'url':
        return TextInputType.url;
      case 'number':
        return TextInputType.number;
      case 'multiline':
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  BoxFit _getBoxFit(String? fit) {
    switch (fit) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      case 'contain':
        return BoxFit.contain;
      case 'fitHeight':
        return BoxFit.fitHeight;
      case 'fitWidth':
        return BoxFit.fitWidth;
      case 'scaleDown':
        return BoxFit.scaleDown;
      default:
        return BoxFit.cover;
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
