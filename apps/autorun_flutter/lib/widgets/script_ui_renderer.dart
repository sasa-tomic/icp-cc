import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/script_runner.dart';

class ScriptUiRenderer extends StatefulWidget {
  const ScriptUiRenderer({super.key, required this.runner, required this.uiSpec});
  final ScriptRunner runner;
  final Map<String, dynamic> uiSpec; // { action:"ui", ui:{ type:"list", items:[], buttons:[] } }

  @override
  State<ScriptUiRenderer> createState() => _ScriptUiRendererState();
}

class _ScriptUiRendererState extends State<ScriptUiRenderer> {
  bool _busy = false;
  dynamic _lastResult;
  String? _error;

  List<dynamic> get _items => ((widget.uiSpec['ui'] as Map<String, dynamic>?)?['items'] as List<dynamic>? ?? const <dynamic>[]);
  List<dynamic> get _buttons => ((widget.uiSpec['ui'] as Map<String, dynamic>?)?['buttons'] as List<dynamic>? ?? const <dynamic>[]);

  Future<void> _runAction(Map<String, dynamic> action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await widget.runner.performAction(action);
      if (!mounted) return;
      if (!res.ok) {
        setState(() { _error = res.error ?? 'Unknown error'; });
      } else {
        setState(() { _lastResult = res.result; });
      }
    } catch (e, st) {
      // Fail fast, surface details
      debugPrint('performAction failed: $e\n$st');
      if (mounted) setState(() { _error = '$e'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_items.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(12),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                if (item is Map<String, dynamic>) {
                  final title = (item['title'] ?? '').toString();
                  final subtitle = item.containsKey('subtitle') ? (item['subtitle'] ?? '').toString() : null;
                  return ListTile(
                    title: Text(title),
                    subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
                  );
                }
                return ListTile(title: Text(item.toString()));
              },
            ),
          ),
        if (_buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buttons.map((b) {
                if (b is Map<String, dynamic>) {
                  final label = (b['label'] ?? 'Run').toString();
                  return FilledButton.icon(
                    onPressed: _busy ? null : () => _runAction(b['on_press'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
                    icon: _busy ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.play_arrow),
                    label: Text(label),
                  );
                }
                return const SizedBox.shrink();
              }).cast<Widget>().toList(),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (_lastResult != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectionArea(child: Text(JsonEncoder.withIndent('  ').convert(_lastResult))),
          ),
      ],
    );
  }
}
