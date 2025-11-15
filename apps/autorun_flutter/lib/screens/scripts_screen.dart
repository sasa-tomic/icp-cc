import 'dart:convert';
import 'package:flutter/material.dart';

import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../rust/native_bridge.dart';
import '../widgets/empty_state.dart';
import '../widgets/script_app_host.dart';
import '../widgets/integrations_help.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  late final ScriptController _controller;
  final ScriptAppRuntime _appRuntime = ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));

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
    // Launch persistent app host for TEA-style scripts
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(record.title)),
        body: ScriptAppHost(runtime: _appRuntime, script: record.luaSource, initialArg: const <String, dynamic>{}),
      ),
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
    // Step 1: let user edit a fresh sample Lua script
    final String? editedSource = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ScriptCreateSheet(controller: _controller),
    );
    if (!mounted || editedSource == null) return;
    // Step 2: prompt for details and create the script record
    final ScriptRecord? rec = await showDialog<ScriptRecord>(
      context: context,
      builder: (_) => _NewScriptDetailsDialog(controller: _controller, luaSource: editedSource),
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
        heroTag: 'scripts_fab',
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
  late final TextEditingController _sourceController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'My first script');
    _emojiController = TextEditingController(text: '🧪');
    _imageUrlController = TextEditingController();
    _sourceController = TextEditingController(text: kDefaultSampleLua);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    // Only validate that the Lua source is non-empty (fail-fast)
    if (_sourceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lua source cannot be empty')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      // Return only the edited source; details are collected after Save
      if (!mounted) return;
      Navigator.of(context).pop<String>(_sourceController.text);
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
            Text('New script', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _sourceController,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: 'Lua source (edit first, Save to continue)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              enabled: false,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emojiController,
              decoration: const InputDecoration(
                labelText: 'Emoji (optional)',
                hintText: 'e.g. 🔍',
                border: OutlineInputBorder(),
              ),
              enabled: false,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _imageUrlController,
              decoration: const InputDecoration(
                labelText: 'Image URL (optional)',
                hintText: 'local:// or https:// path',
                border: OutlineInputBorder(),
              ),
              enabled: false,
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
              label: const Text('Continue'),
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
  String? _lintError;
  DateTime _lastEditTs = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(text: widget.record.luaSource);
    _sourceController.addListener(_onChanged);
    // Initial lint
    _scheduleLint();
  }

  @override
  void dispose() {
    _sourceController.removeListener(_onChanged);
    _sourceController.dispose();
    super.dispose();
  }

  void _onChanged() {
    _lastEditTs = DateTime.now();
    _scheduleLint();
  }

  void _scheduleLint() async {
    final DateTime ts = _lastEditTs;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || ts != _lastEditTs) return; // Debounced
    final String src = _sourceController.text;
    // Fail-fast: empty script is an error in runner; report here too
    if (src.trim().isEmpty) {
      setState(() => _lintError = 'Script is empty');
      return;
    }
    final String? out = (RustScriptBridge(const RustBridgeLoader())).luaLint(script: src);
    if (out == null || out.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _lintError = 'Linter unavailable');
      return;
    }
    try {
      final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
      final bool ok = (obj['ok'] as bool?) ?? false;
      if (!mounted) return;
      if (ok) {
        setState(() => _lintError = null);
      } else {
        final List<dynamic> errs = (obj['errors'] as List<dynamic>? ?? const <dynamic>[]);
        final String msg = errs.isNotEmpty ? ((errs.first as Map<String, dynamic>)['message'] as String? ?? 'Invalid script') : 'Invalid script';
        setState(() => _lintError = msg);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _lintError = 'Invalid linter output');
    }
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
                    showDialog<String?>(
                      context: context,
                      builder: (_) => const IntegrationsHelpDialog(),
                    ).then((String? snippet) {
                      if (snippet == null || snippet.isEmpty) return;
                      final TextEditingController c = _sourceController;
                      final int baseOffset = c.selection.baseOffset;
                      final int extentOffset = c.selection.extentOffset;
                      final bool hasSel = baseOffset >= 0 && extentOffset >= 0 && baseOffset != extentOffset;
                      final String before = hasSel ? c.text.replaceRange(baseOffset, extentOffset, '') : c.text;
                      final int insertPos = hasSel ? baseOffset : (c.selection.baseOffset >= 0 ? c.selection.baseOffset : before.length);
                      final String updated = before.substring(0, insertPos) + snippet + before.substring(insertPos);
                      c.text = updated;
                      c.selection = TextSelection.collapsed(offset: insertPos + snippet.length);
                    });
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
            if (_lintError != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _lintError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: _saving || _lintError != null ? null : _save,
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

class _NewScriptDetailsDialog extends StatefulWidget {
  const _NewScriptDetailsDialog({required this.controller, required this.luaSource});
  final ScriptController controller;
  final String luaSource;

  @override
  State<_NewScriptDetailsDialog> createState() => _NewScriptDetailsDialogState();
}

class _NewScriptDetailsDialogState extends State<_NewScriptDetailsDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'My first script');
    _emojiController = TextEditingController(text: '🧪');
    _imageUrlController = TextEditingController();
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
      final rec = await widget.controller.createScript(
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
        luaSourceOverride: widget.luaSource,
      );
      if (!mounted) return;
      Navigator.of(context).pop(rec);
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
      title: const Text('Name your script'),
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
        FilledButton(onPressed: _isSubmitting ? null : _save, child: const Text('Create script')),
      ],
    );
  }
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
