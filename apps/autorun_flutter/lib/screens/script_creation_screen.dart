import 'package:flutter/material.dart';
import '../controllers/script_controller.dart';
import '../models/script_template.dart';
import '../widgets/script_editor.dart';

class ScriptCreationScreen extends StatefulWidget {
  const ScriptCreationScreen({
    super.key,
    required this.controller,
    this.initialTemplate,
  });

  final ScriptController controller;
  final ScriptTemplate? initialTemplate;

  @override
  State<ScriptCreationScreen> createState() => _ScriptCreationScreenState();
}

class _ScriptCreationScreenState extends State<ScriptCreationScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;
  final _scrollController = ScrollController();

  String _currentCode = '';
  bool _isCreating = false;
  ScriptTemplate? _selectedTemplate;
  late List<ScriptTemplate> _availableTemplates;

  @override
  void initState() {
    super.initState();

    _availableTemplates = List<ScriptTemplate>.from(ScriptTemplates.templates);

    if (widget.initialTemplate != null) {
      final matchingTemplate = ScriptTemplates.templates
          .where((t) => t.id == widget.initialTemplate!.id);
      if (matchingTemplate.isNotEmpty) {
        _selectedTemplate = matchingTemplate.first;
      } else {
        _availableTemplates = [
          widget.initialTemplate!,
          ...ScriptTemplates.templates
        ];
        _selectedTemplate = widget.initialTemplate!;
      }
    } else {
      _selectedTemplate = ScriptTemplates.templates.first;
    }

    _currentCode = _selectedTemplate!.luaSource;

    _titleController = TextEditingController(text: _selectedTemplate!.title);
    _emojiController = TextEditingController(text: _selectedTemplate!.emoji);
    _imageUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTemplateSelected(ScriptTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _currentCode = template.luaSource;

      _titleController.text = template.title;
      _emojiController.text = template.emoji;
    });
  }

  void _onCodeChanged(String code) {
    _currentCode = code;
  }

  Future<void> _createScript() async {
    if (_isCreating) return;

    if (_currentCode.trim().isEmpty) {
      _showError('Lua source cannot be empty');
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      _showError('Title is required');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final rec = await widget.controller.createScript(
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty
            ? null
            : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty
            ? null
            : _imageUrlController.text.trim(),
        luaSourceOverride: _currentCode,
      );

      if (!mounted) return;
      Navigator.of(context).pop(rec);
    } catch (e) {
      if (mounted) {
        _showError('Failed to create script: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'advanced':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Script'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTemplateSelector(),
                  const SizedBox(height: 16),
                  _buildDetailsForm(),
                  const SizedBox(height: 16),
                  _buildCodeEditor(),
                ],
              ),
            ),
          ),
          _buildBottomButton(),
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Template',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<ScriptTemplate>(
              initialValue: _selectedTemplate,
              decoration: const InputDecoration(
                hintText: 'Choose template',
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              items: _availableTemplates.map((template) {
                return DropdownMenuItem<ScriptTemplate>(
                  value: template,
                  child: Row(
                    children: [
                      Text(
                        template.emoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          template.title,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: _getLevelColor(template.level),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          template.level.toUpperCase().substring(0, 1),
                          style: const TextStyle(
                            fontSize: 7,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (ScriptTemplate? template) {
                if (template != null) {
                  _onTemplateSelected(template);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                hintText: 'Enter a descriptive title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _emojiController,
                    decoration: const InputDecoration(
                      labelText: 'Emoji',
                      hintText: '🧪',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.emoji_emotions),
                    ),
                    maxLength: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Image URL',
                      hintText: 'local:// or https://',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.image),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.code, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Lua Source',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 350,
              child: ScriptEditor(
                key: ValueKey(_selectedTemplate?.id ?? 'default'),
                initialCode: _currentCode,
                onCodeChanged: _onCodeChanged,
                language: 'lua',
                showIntegrations: true,
                minLines: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: FilledButton(
          onPressed: _isCreating ? null : _createScript,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create Script'),
        ),
      ),
    );
  }
}
