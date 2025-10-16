import 'dart:convert';
import 'package:flutter/material.dart';

import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../rust/native_bridge.dart';
import '../widgets/empty_state.dart';
import '../widgets/script_ui_renderer.dart';
import '../widgets/integrations_help.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  late final ScriptController _controller;
  final ScriptRunner _runner = ScriptRunner(RustScriptBridge(const RustBridgeLoader()));

  @override
  void initState() {
    super.initState();
    _controller = ScriptController(ScriptRepository())..addListener(_onChanged);
    _controller.ensureLoaded();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _runScript(ScriptRecord record) async {
    // Minimal first run: no pre-calls, just run Lua with empty input
    final plan = ScriptRunPlan(luaSource: record.luaSource, calls: const <CanisterCallSpec>[], initialArg: const <String, dynamic>{});
    final res = await _runner.run(plan);
    if (!mounted) return;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Run failed: ${res.error}')));
      return;
    }
    final dynamic out = res.result;
    if (out is Map<String, dynamic> && (out['action'] as String?) == 'ui') {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Script UI'),
          content: SingleChildScrollView(
            child: ScriptUiRenderer(runner: _runner, uiSpec: out),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Script result'),
              content: SingleChildScrollView(child: SelectableText(JsonEncoder.withIndent('  ').convert(res.result))),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ],
            ));
  }

  Future<void> _confirmAndDeleteScript(ScriptRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete script'),
          content: Text('Delete "${record.title}"? This cannot be undone.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _controller.deleteScript(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Script deleted')));
    }
  }

  Future<void> _showCreateSheet() async {
    final ScriptRecord? rec = await showModalBottomSheet<ScriptRecord>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ScriptCreateSheet(controller: _controller),
    );
    if (!mounted || rec == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Script created')));
  }

  @override
  Widget build(BuildContext context) {
    final List<ScriptRecord> scripts = _controller.scripts;
    final bool showLoading = _controller.isBusy && scripts.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scripts'),
      ),
      body: Builder(builder: (context) {
        if (showLoading) return const Center(child: CircularProgressIndicator());
        if (scripts.isEmpty) {
          return const EmptyState(
            icon: Icons.code,
            title: 'No scripts yet',
            subtitle: 'Tap "New script" to add a Lua script.',
          );
        }
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            itemCount: scripts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final ScriptRecord rec = scripts[index];
              return Dismissible(
                key: ValueKey<String>(rec.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: const <Widget>[
                      Icon(Icons.delete),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  await _controller.deleteScript(rec.id);
                  return false;
                },
                child: ListTile(
                  leading: CircleAvatar(child: Text((rec.emoji ?? '📜').characters.first)),
                  title: Text(rec.title),
                  subtitle: Text('Updated ${rec.updatedAt.toLocal()}'),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => _ScriptEditorDialog(controller: _controller, record: rec),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Run',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _runScript(rec),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'More',
                        itemBuilder: (BuildContext context) => const <PopupMenuEntry<int>>[
                          PopupMenuItem<int>(value: 1, child: Text('Edit details…')),
                          PopupMenuItem<int>(value: 2, child: Text('Delete')),
                        ],
                        onSelected: (int value) {
                          switch (value) {
                            case 1:
                              showDialog<void>(
                                context: context,
                                builder: (_) => _ScriptDetailsDialog(controller: _controller, record: rec),
                              );
                              break;
                            case 2:
                              _confirmAndDeleteScript(rec);
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller.isBusy ? null : _showCreateSheet,
        icon: const Icon(Icons.add),
        label: const Text('New script'),
      ),
    );
  }
}

// Empty state moved to shared widget

class _ScriptCreateSheet extends StatefulWidget {
  const _ScriptCreateSheet({required this.controller});
  final ScriptController controller;

  @override
  State<_ScriptCreateSheet> createState() => _ScriptCreateSheetState();
}

class _ScriptCreateSheetState extends State<_ScriptCreateSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _emojiController = TextEditingController();
    _imageUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final rec = await widget.controller.createScript(
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(rec);
    } catch (error, stackTrace) {
      debugPrint('Failed to create script: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: <Widget>[
            Text('Create a new script', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (String? value) {
                if ((value ?? '').trim().isEmpty) return 'Title is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emojiController,
              decoration: const InputDecoration(
                labelText: 'Emoji (optional)',
                hintText: 'e.g. 🔍',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _imageUrlController,
              decoration: const InputDecoration(
                labelText: 'Image URL (optional)',
                hintText: 'local:// or https:// path',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            const Text(
              'Provide either an emoji or an image URL',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bolt),
              label: const Text('Create script'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptEditorDialog extends StatefulWidget {
  const _ScriptEditorDialog({required this.controller, required this.record});
  final ScriptController controller;
  final ScriptRecord record;

  @override
  State<_ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _ScriptEditorDialogState extends State<_ScriptEditorDialog> {
  late final TextEditingController _sourceController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(text: widget.record.luaSource);
  }

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateSource(id: widget.record.id, luaSource: _sourceController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit: ${widget.record.title}'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const IntegrationsHelpDialog(),
                    );
                  },
                  icon: const Icon(Icons.extension),
                  label: const Text('Integrations'),
                ),
              ],
            ),
            TextField(
              controller: _sourceController,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: 'Lua source',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.multiline,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ScriptDetailsDialog extends StatefulWidget {
  const _ScriptDetailsDialog({required this.controller, required this.record});
  final ScriptController controller;
  final ScriptRecord record;

  @override
  State<_ScriptDetailsDialog> createState() => _ScriptDetailsDialogState();
}

class _ScriptDetailsDialogState extends State<_ScriptDetailsDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.record.title);
    _emojiController = TextEditingController(text: widget.record.emoji ?? '');
    _imageUrlController = TextEditingController(text: widget.record.imageUrl ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.controller.updateDetails(
        id: widget.record.id,
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit details'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiController,
                decoration: const InputDecoration(labelText: 'Emoji (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(labelText: 'Image URL (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Provide either an emoji or an image URL', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _isSubmitting ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
