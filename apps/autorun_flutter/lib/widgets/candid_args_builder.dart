import 'package:flutter/material.dart';
import '../models/canister_method.dart';
import '../utils/candid_type_classifier.dart';

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
      // W7-11: route every Candid-type branch through `classifyCandidType`,
      // the single source of truth. The previous literal-by-literal switch
      // used raw `type == '...'` (case-sensitive) and only listed
      // nat/nat64/int/int64 + float64/float — nat8/16/32, int8/16/32, and
      // float32 silently fell through to the text default. That behaviour
      // is preserved verbatim (only the 4 historic integer literals and
      // float64 are routed to numeric parsing; other numeric widths still
      // fall through to `return value`).
      switch (classifyCandidType(type)) {
        case CandidTypeKind.text:
          return value;
        case CandidTypeKind.nat:
        case CandidTypeKind.nat64:
        case CandidTypeKind.int:
        case CandidTypeKind.int64:
          return int.parse(value);
        case CandidTypeKind.float64:
          return double.parse(value);
        case CandidTypeKind.boolean:
          return value.toLowerCase() == 'true';
        case CandidTypeKind.principal:
          // Validate principal format
          if (RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
            return value;
          }
          return null;
        case CandidTypeKind.vec:
        case CandidTypeKind.record:
        case CandidTypeKind.variant:
          // For complex types, try to parse as JSON
          return _parseJsonValue(value);
        case CandidTypeKind.nat8:
        case CandidTypeKind.nat16:
        case CandidTypeKind.nat32:
        case CandidTypeKind.int8:
        case CandidTypeKind.int16:
        case CandidTypeKind.int32:
        case CandidTypeKind.float32:
        case CandidTypeKind.opt:
        case CandidTypeKind.unknown:
          // Default to treating as text (historic fall-through).
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
            Flexible(
              child: Text(
                '(${arg.type})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
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
    // W7-11: route through `classifyCandidType` — single source of truth.
    // historic fall-through semantics preserved: only nat/int/nat64/int64
    // get the integer keyboard, only float64 gets the decimal keyboard,
    // every other numeric width (nat8/16/32, int8/16/32, float32) falls
    // through to the multi-line JSON editor like before.
    final kind = classifyCandidType(arg.type);
    switch (kind) {
      case CandidTypeKind.boolean:
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
      case CandidTypeKind.text:
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case CandidTypeKind.principal:
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'aaaaa-aa',
          ),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case CandidTypeKind.nat:
      case CandidTypeKind.int:
      case CandidTypeKind.nat64:
      case CandidTypeKind.int64:
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case CandidTypeKind.float64:
        return TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) => _updateArg(arg.name, value),
        );
      case CandidTypeKind.nat8:
      case CandidTypeKind.nat16:
      case CandidTypeKind.nat32:
      case CandidTypeKind.int8:
      case CandidTypeKind.int16:
      case CandidTypeKind.int32:
      case CandidTypeKind.float32:
      case CandidTypeKind.vec:
      case CandidTypeKind.record:
      case CandidTypeKind.variant:
      case CandidTypeKind.opt:
      case CandidTypeKind.unknown:
        // For complex types (vec, record, variant), use text area
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: _getPlaceholderForType(arg.type),
            helperText: 'Enter JSON format for complex types',
          ),
          maxLines: kind == CandidTypeKind.record ? 3 : 1,
          onChanged: (value) => _updateArg(arg.name, value),
        );
    }
  }

  Widget _buildHelpText(CanisterArg arg) {
    // W7-11: route through `classifyCandidType` — single source of truth.
    String helpText = '';
    switch (classifyCandidType(arg.type)) {
      case CandidTypeKind.principal:
        helpText = 'Enter a valid principal ID (e.g., aaaaa-aa)';
      case CandidTypeKind.nat:
      case CandidTypeKind.nat64:
        helpText = 'Enter a non-negative integer';
      case CandidTypeKind.boolean:
        helpText = 'Select true or false';
      case CandidTypeKind.vec:
        helpText = 'Enter array format: [item1, item2, ...]';
      case CandidTypeKind.record:
        helpText = 'Enter JSON object format: {"field": "value"}';
      case CandidTypeKind.variant:
        helpText = 'Enter variant format: {"variant_name": value}';
      case CandidTypeKind.text:
      case CandidTypeKind.int:
      case CandidTypeKind.nat8:
      case CandidTypeKind.nat16:
      case CandidTypeKind.nat32:
      case CandidTypeKind.int8:
      case CandidTypeKind.int16:
      case CandidTypeKind.int32:
      case CandidTypeKind.int64:
      case CandidTypeKind.float32:
      case CandidTypeKind.float64:
      case CandidTypeKind.opt:
      case CandidTypeKind.unknown:
        break;
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
    // W7-11: route through `classifyCandidType` — single source of truth.
    switch (classifyCandidType(type)) {
      case CandidTypeKind.vec:
        return '[]';
      case CandidTypeKind.record:
        return '{}';
      case CandidTypeKind.variant:
        return '{"tag": "value"}';
      case CandidTypeKind.boolean:
      case CandidTypeKind.text:
      case CandidTypeKind.principal:
      case CandidTypeKind.nat:
      case CandidTypeKind.int:
      case CandidTypeKind.nat8:
      case CandidTypeKind.nat16:
      case CandidTypeKind.nat32:
      case CandidTypeKind.nat64:
      case CandidTypeKind.int8:
      case CandidTypeKind.int16:
      case CandidTypeKind.int32:
      case CandidTypeKind.int64:
      case CandidTypeKind.float32:
      case CandidTypeKind.float64:
      case CandidTypeKind.opt:
      case CandidTypeKind.unknown:
        return '';
    }
  }
}