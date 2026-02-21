import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/candid_args.dart';

class CandidSmartForm extends StatefulWidget {
  const CandidSmartForm({
    super.key,
    required this.argTypes,
    required this.onJsonChanged,
    this.initialJson,
  });

  final List<String> argTypes;
  final ValueChanged<String> onJsonChanged;
  final String? initialJson;

  @override
  State<CandidSmartForm> createState() => CandidSmartFormState();
}

class CandidSmartFormState extends State<CandidSmartForm> {
  late List<_FieldController> _controllers;
  bool _hasErrors = false;

  bool get hasErrors => _hasErrors;

  @override
  void initState() {
    super.initState();
    _controllers = _createControllers();
    _emitJson();
  }

  @override
  void didUpdateWidget(covariant CandidSmartForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.argTypes != widget.argTypes) {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = _createControllers();
      _emitJson();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<_FieldController> _createControllers() {
    return widget.argTypes.asMap().entries.map((e) {
      return _FieldControllerFactory.create(
          e.value, null, e.key, _onFieldChanged);
    }).toList();
  }

  void _onFieldChanged() {
    _emitJson();
  }

  void _emitJson() {
    final json = getJson();
    widget.onJsonChanged(json);
  }

  String getJson() {
    if (widget.argTypes.isEmpty) {
      return '';
    }
    _validateAll();
    try {
      if (widget.argTypes.length == 1) {
        final value = _controllers.first.toJsonValue();
        return const JsonEncoder.withIndent(null).convert(value);
      }
      final values = _controllers.map((c) => c.toJsonValue()).toList();
      return const JsonEncoder.withIndent(null).convert(values);
    } catch (_) {
      return '';
    }
  }

  void _validateAll() {
    bool hasError = false;
    for (final c in _controllers) {
      if (!c.isValid()) {
        hasError = true;
      }
    }
    if (hasError != _hasErrors) {
      setState(() {
        _hasErrors = hasError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.argTypes.isEmpty) {
      return const Text('No input required');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.argTypes.length; i++) ...[
          _controllers[i].buildWidget(context),
          if (i < widget.argTypes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

abstract class _FieldController {
  _FieldController(this.label, this.onChanged);

  final String? label;
  final VoidCallback onChanged;

  void dispose();
  Widget buildWidget(BuildContext context);
  dynamic toJsonValue();
  bool isValid();

  String get displayLabel => label ?? typeLabel;
  String get typeLabel;
}

class _FieldControllerFactory {
  static _FieldController create(
      String type, String? label, int index, VoidCallback onChanged) {
    final t = type.trim().toLowerCase();

    if (t.startsWith('variant')) {
      return _VariantFieldController(type, label, onChanged);
    }
    if (t == 'bool') {
      return _BoolFieldController(label, onChanged);
    }
    if (t.startsWith('record')) {
      return _RecordFieldController(type, label, onChanged);
    }
    if (t.startsWith('opt')) {
      final inner = _extractInner(type, 'opt');
      return _OptFieldController(inner, label, onChanged);
    }
    if (t.startsWith('vec')) {
      return _VecFieldController(type, label, onChanged);
    }
    if (t == 'text' || t == 'principal') {
      return _TextFieldController(label, onChanged);
    }
    if (_isNumericType(t)) {
      return _NumberFieldController(type, label, onChanged);
    }
    return _JsonFieldController(type, label, onChanged);
  }

  static bool _isNumericType(String t) {
    return t == 'nat' ||
        t == 'int' ||
        t.startsWith('nat8') ||
        t.startsWith('nat16') ||
        t.startsWith('nat32') ||
        t.startsWith('nat64') ||
        t.startsWith('int8') ||
        t.startsWith('int16') ||
        t.startsWith('int32') ||
        t.startsWith('int64') ||
        t == 'float32' ||
        t == 'float64';
  }
}

class _TextFieldController extends _FieldController {
  _TextFieldController(super.label, super.onChanged);

  final controller = TextEditingController();

  @override
  String get typeLabel => 'text';

  @override
  void dispose() {
    controller.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() => controller.text;

  @override
  bool isValid() => true;
}

class _NumberFieldController extends _FieldController {
  _NumberFieldController(this.type, super.label, super.onChanged);

  final String type;
  final controller = TextEditingController();
  String? _error;

  @override
  String get typeLabel => type;

  @override
  void dispose() {
    controller.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
          ],
          onChanged: (_) {
            _validate();
            onChanged();
          },
        ),
      ],
    );
  }

  void _validate() {
    final text = controller.text.trim();
    if (text.isEmpty) {
      _error = null;
      return;
    }
    final num? value = num.tryParse(text);
    if (value == null) {
      _error = 'Invalid number';
    } else {
      _error = null;
    }
  }

  @override
  dynamic toJsonValue() {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final lower = type.toLowerCase();
    if (lower == 'nat' || lower == 'int') {
      final num? value = num.tryParse(text);
      if (value != null && (text.length > 18)) {
        return text;
      }
      return value ?? 0;
    }
    return num.tryParse(text) ?? 0;
  }

  @override
  bool isValid() => _error == null;
}

class _BoolFieldController extends _FieldController {
  _BoolFieldController(super.label, super.onChanged);

  bool value = false;

  @override
  String get typeLabel => 'bool';

  @override
  void dispose() {}

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        Switch(
          value: value,
          onChanged: (v) {
            value = v;
            onChanged();
          },
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() => value;

  @override
  bool isValid() => true;
}

class _VariantFieldController extends _FieldController {
  _VariantFieldController(this.type, super.label, super.onChanged) {
    _cases = _parseVariantCases(type);
    if (_cases.isNotEmpty) {
      _selectedCase = _cases.first.name;
    }
  }

  final String type;
  late List<VariantCase> _cases;
  String? _selectedCase;

  @override
  String get typeLabel => 'variant';

  @override
  void dispose() {}

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: _selectedCase,
          isExpanded: true,
          items: _cases.map((c) {
            return DropdownMenuItem<String>(
              value: c.name,
              child: Text(c.name),
            );
          }).toList(),
          onChanged: (v) {
            _selectedCase = v;
            onChanged();
          },
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() {
    if (_selectedCase == null) return {};
    final selected = _cases.firstWhere(
      (c) => c.name == _selectedCase,
      orElse: () => _cases.first,
    );
    return {selected.name: null};
  }

  @override
  bool isValid() => true;
}

class _RecordFieldController extends _FieldController {
  _RecordFieldController(this.type, super.label, super.onChanged) {
    _fields = parseRecordType(type);
    _controllers = _fields.asMap().entries.map((e) {
      return _FieldControllerFactory.create(
          e.value.icType, e.value.name, e.key, onChanged);
    }).toList();
  }

  final String type;
  late List<RecordFieldSpec> _fields;
  late List<_FieldController> _controllers;

  @override
  String get typeLabel => 'record';

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _controllers.length; i++) ...[
                _controllers[i].buildWidget(context),
                if (i < _controllers.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() {
    final map = <String, dynamic>{};
    for (int i = 0; i < _fields.length; i++) {
      map[_fields[i].name] = _controllers[i].toJsonValue();
    }
    return map;
  }

  @override
  bool isValid() {
    for (final c in _controllers) {
      if (!c.isValid()) return false;
    }
    return true;
  }
}

class _OptFieldController extends _FieldController {
  _OptFieldController(this.innerType, super.label, super.onChanged);

  final String innerType;
  bool isNull = true;
  late _FieldController innerController =
      _FieldControllerFactory.create(innerType, label, 0, onChanged);

  @override
  String get typeLabel => 'opt';

  @override
  void dispose() {
    innerController.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildLabel(context, displayLabel),
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
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Checkbox(
              value: !isNull,
              onChanged: (v) {
                isNull = !(v ?? false);
                onChanged();
              },
            ),
            const Text('Has value'),
          ],
        ),
        if (!isNull) innerController.buildWidget(context),
      ],
    );
  }

  @override
  dynamic toJsonValue() {
    if (isNull) return null;
    return innerController.toJsonValue();
  }

  @override
  bool isValid() {
    if (isNull) return true;
    return innerController.isValid();
  }
}

class _VecFieldController extends _FieldController {
  _VecFieldController(this.type, super.label, super.onChanged);

  final String type;
  final controller = TextEditingController();

  @override
  String get typeLabel => type;

  @override
  void dispose() {
    controller.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: '[ item1, item2, ... ]',
            helperText: 'Enter JSON array',
          ),
          maxLines: 2,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() {
    final text = controller.text.trim();
    if (text.isEmpty) return [];
    try {
      return json.decode(text);
    } catch (_) {
      return text;
    }
  }

  @override
  bool isValid() => true;
}

class _JsonFieldController extends _FieldController {
  _JsonFieldController(this.type, super.label, super.onChanged);

  final String type;
  final controller = TextEditingController();

  @override
  String get typeLabel => type;

  @override
  void dispose() {
    controller.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context, displayLabel),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'JSON format',
            helperText: 'Enter value in JSON format',
          ),
          maxLines: 3,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  @override
  dynamic toJsonValue() {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    try {
      return json.decode(text);
    } catch (_) {
      return text;
    }
  }

  @override
  bool isValid() => true;
}

class VariantCase {
  const VariantCase({required this.name, this.type});
  final String name;
  final String? type;
}

List<VariantCase> _parseVariantCases(String variantType) {
  final s = variantType.trim();
  final lbrace = s.indexOf('{');
  final rbrace = s.lastIndexOf('}');
  if (lbrace < 0 || rbrace <= lbrace) return const <VariantCase>[];
  final body = s.substring(lbrace + 1, rbrace);
  final parts =
      body.split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  final out = <VariantCase>[];
  for (final part in parts) {
    final idx = part.indexOf(':');
    if (idx <= 0) {
      out.add(VariantCase(name: part, type: null));
    } else {
      final name = part.substring(0, idx).trim();
      final ty = part.substring(idx + 1).trim();
      out.add(VariantCase(name: name, type: ty));
    }
  }
  return out;
}

String _extractInner(String original, String prefix) {
  final s = original.trim();
  final lt = s.indexOf('<');
  final gt = s.lastIndexOf('>');
  if (lt >= 0 && gt > lt) {
    return s.substring(lt + 1, gt).trim();
  }
  final lower = s.toLowerCase();
  final idx = lower.indexOf(prefix) + prefix.length;
  return s.substring(idx).trim();
}

Widget _buildLabel(BuildContext context, String label) {
  return Text(
    label,
    style: TextStyle(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}
