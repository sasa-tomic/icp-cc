import 'package:flutter/material.dart';

import '../utils/candid_form_model.dart';
import '../utils/candid_json_validate.dart';
import '../utils/candid_type_classifier.dart';

class ArgsEditor extends StatefulWidget {
  const ArgsEditor({
    super.key,
    required this.useAuto,
    required this.argTypes,
    required this.controller,
    required this.onToggle,
  });
  final bool useAuto;
  final List<String> argTypes;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;
  // Note: parent listens to controller and shows errors; keeping API minimal

  @override
  State<ArgsEditor> createState() => _ArgsEditorState();
}

class _ArgsEditorState extends State<ArgsEditor> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.argTypes.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void didUpdateWidget(covariant ArgsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.argTypes.length != widget.argTypes.length) {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = List<TextEditingController>.generate(
        widget.argTypes.length,
        (_) => TextEditingController(),
      );
      _rebuildJson();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildJson() {
    try {
      final model = CandidFormModel(widget.argTypes);
      if (!model.isSupportedByForm || !widget.useAuto) {
        return;
      }
      final List<dynamic> values = <dynamic>[];
      for (int i = 0; i < widget.argTypes.length; i += 1) {
        values.add(_controllers[i].text.trim());
      }
      widget.controller.text = model.buildJson(values);
    } catch (e, st) {
      debugPrint('bookmarks._rebuildJson failed (user falls back to raw JSON): '
          '$e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = CandidFormModel(widget.argTypes);

    // No header here - parent already shows "Input" with JSON/Form toggle
    // This simplifies the UX by avoiding redundant "Arguments" label

    if (!widget.useAuto ||
        widget.argTypes.isEmpty ||
        !model.isSupportedByForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!model.isSupportedByForm)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  'Some argument types are not supported by form. Use raw JSON.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ),
          TextField(
            key: const Key('argsJsonField'),
            controller: widget.controller,
            decoration: const InputDecoration(
              labelText: 'Args JSON',
              hintText:
                  '[] for multiple args; object/array/scalar for single arg',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 8,
          ),
        ],
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.argTypes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final String t = widget.argTypes[index];
        final String label = 'Arg ${index + 1} ($t)';
        // W7-11: route through `classifyCandidType` — single source of
        // truth. Replaces a triple `lower.contains('int'|'float'|'nat')`
        // substring check (which would over-match e.g. 'print') and a
        // triple `lower.startsWith('record'|'vec'|'opt')` prefix check
        // with one exhaustive switch on the classified kind.
        final kind = classifyCandidType(t);
        final TextInputType inputType = kind.isNumeric
            ? TextInputType.number
            : TextInputType.text;
        final String? hint = switch (kind) {
          CandidTypeKind.record => 'JSON object or array matching record fields',
          CandidTypeKind.vec => 'JSON array for vector values',
          CandidTypeKind.opt => 'Value or null',
          _ => null,
        };
        return TextField(
          key: Key('argField_$index'),
          controller: _controllers[index],
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          keyboardType: inputType,
          onChanged: (_) {
            _rebuildJson();
            // Best-effort live validation comparing built JSON vs expected types
            try {
              final model = CandidFormModel(widget.argTypes);
              final List<dynamic> values =
                  _controllers.map((c) => c.text.trim()).toList();
              final jsonStr = model.buildJson(values);
              validateJsonArgs(
                  resolvedArgTypes: widget.argTypes, jsonText: jsonStr);
              // Bubble up? The parent shows errors from main controller text; skip here.
            } catch (e) {
              debugPrint('bookmarks live validation skipped: $e');
            }
          },
        );
      },
    );
  }
}
