import 'package:flutter/material.dart';
import '../models/canister_method.dart';

/// Widget for building arguments for canister method calls
class CandidArgsBuilder extends StatefulWidget {
  const CandidArgsBuilder({
    super.key,
    required this.method,
    required this.args,
    required this.onChanged,
  });

  final CanisterMethod method;
  final Map<String, dynamic> args;
  final Function(Map<String, dynamic>) onChanged;

  @override
  State<CandidArgsBuilder> createState() => _CandidArgsBuilderState();
}

class _CandidArgsBuilderState extends State<CandidArgsBuilder> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final arg in widget.method.args) {
      _controllers[arg.name] = TextEditingController(
        text: _valueToString(widget.args[arg.name]),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _valueToString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  void _updateArg(String argName, String value) {
    final newArgs = Map<String, dynamic>.from(widget.args);
    final parsedValue = _parseValue(value, _getArgType(argName));

    if (parsedValue != null) {
      newArgs[argName] = parsedValue;
    } else {
      newArgs.remove(argName);
    }

    widget.onChanged(newArgs);
  }

  String _getArgType(String argName) {
    final arg = widget.method.args.firstWhere((a) => a.name == argName);
    return arg.type;
  }

  dynamic _parseValue(String value, String type) {
    if (value.trim().isEmpty) return null;

    try {
      // Handle different Candid types
      if (type == 'text' || type == 'string') {
        return value;
      } else if (type == 'nat' || type == 'nat64' || type == 'int' || type == 'int64') {
        return int.parse(value);
      } else if (type == 'float64' || type == 'float') {
        return double.parse(value);
      } else if (type == 'bool') {
        return value.toLowerCase() == 'true';
      } else if (type == 'principal') {
        // Validate principal format
        if (RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
          return value;
        }
        return null;
      } else if (type.startsWith('vec') || type.startsWith('record') || type.startsWith('variant')) {
        // For complex types, try to parse as JSON
        return _parseJsonValue(value);
      } else {
        // Default to treating as text
        return value;
      }
    } catch (e) {
      // If parsing fails, return null
      return null;
    }
  }

  dynamic _parseJsonValue(String value) {
    try {
      // Try to parse as JSON
      if (value.startsWith('{') || value.startsWith('[')) {
        return value; // Keep as JSON string for now
      }
      return value;
    } catch (e) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.method.args.isEmpty) {
      return const Center(
        child: Text(
          'No arguments required for this method',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: widget.method.args.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final arg = widget.method.args[index];
        final controller = _controllers[arg.name]!;

        return _buildArgField(arg, controller);
      },
    );
  }

  Widget _buildArgField(CanisterArg arg, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              arg.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '(${arg.type})',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (arg.optional) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'optional',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _buildInputField(arg, controller),
        if (arg.defaultValue != null) ...[
          const SizedBox(height: 4),
          Text(
            'Default: ${arg.defaultValue}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 4),
        _buildHelpText(arg),
      ],
    );
  }

  Widget _buildInputField(CanisterArg arg, TextEditingController controller) {
    switch (arg.type.toLowerCase()) {
      case 'bool':
      case 'boolean':
        return DropdownButtonFormField<bool>(
          initialValue: controller.text.isEmpty ? null : controller.text.toLowerCase() == 'true',
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem<bool>(value: true, child: Text('true')),
            DropdownMenuItem<bool>(value: false, child: Text('false')),
          ],
          onChanged: (value) {
            controller.text = value?.toString() ?? '';
            _updateArg(arg.name, controller.text);
          },
        );
      case 'text':
      case 'string':
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case 'principal':
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'aaaaa-aa',
          ),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case 'nat':
      case 'int':
      case 'nat64':
      case 'int64':
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case 'float64':
      case 'float':
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      default:
        // For complex types (vec, record, variant), use text area
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: _getPlaceholderForType(arg.type),
            helperText: 'Enter JSON format for complex types',
          ),
          maxLines: arg.type.startsWith('record') ? 3 : 1,
          onChanged: (value) => _updateArg(arg.name, value),
        );
    }
  }

  Widget _buildHelpText(CanisterArg arg) {
    String helpText = '';

    switch (arg.type.toLowerCase()) {
      case 'principal':
        helpText = 'Enter a valid principal ID (e.g., aaaaa-aa)';
        break;
      case 'nat':
      case 'nat64':
        helpText = 'Enter a non-negative integer';
        break;
      case 'bool':
      case 'boolean':
        helpText = 'Select true or false';
        break;
      default:
        if (arg.type.startsWith('vec')) {
          helpText = 'Enter array format: [item1, item2, ...]';
        } else if (arg.type.startsWith('record')) {
          helpText = 'Enter JSON object format: {"field": "value"}';
        } else if (arg.type.startsWith('variant')) {
          helpText = 'Enter variant format: {"variant_name": value}';
        }
    }

    if (helpText.isNotEmpty) {
      return Text(
        helpText,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _getPlaceholderForType(String type) {
    if (type.startsWith('vec')) {
      return '[]';
    } else if (type.startsWith('record')) {
      return '{}';
    } else if (type.startsWith('variant')) {
      return '{"tag": "value"}';
    }
    return '';
  }
}