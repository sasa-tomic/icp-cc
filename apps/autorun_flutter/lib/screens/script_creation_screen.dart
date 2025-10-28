import 'package:flutter/material.dart';
import '../controllers/script_controller.dart';
import '../models/script_template.dart';
import '../widgets/script_editor.dart';

/// Script creation flow with improved UX and separated concerns
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

class _ScriptCreationScreenState extends State<ScriptCreationScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;

  String _currentCode = '';
  bool _isCreating = false;
  ScriptTemplate? _selectedTemplate;
  late List<ScriptTemplate> _availableTemplates;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Create available templates list (built-in + any provided template not in built-ins)
    _availableTemplates = List<ScriptTemplate>.from(ScriptTemplates.templates);

    // Initialize with template or defaults
    if (widget.initialTemplate != null) {
      // Find matching template from the templates list to avoid duplicate instances
      final matchingTemplate = ScriptTemplates.templates.where((t) => t.id == widget.initialTemplate!.id);
      if (matchingTemplate.isNotEmpty) {
        _selectedTemplate = matchingTemplate.first;
      } else {
        // Add the provided template to available templates if not already present
        _availableTemplates = [widget.initialTemplate!, ...ScriptTemplates.templates];
        _selectedTemplate = widget.initialTemplate!;
      }
    } else {
      _selectedTemplate = ScriptTemplates.templates.first;
    }
    _currentCode = _selectedTemplate!.luaSource;

    // Initialize details with template values
    _titleController = TextEditingController(text: _selectedTemplate!.title);
    _emojiController = TextEditingController(text: _selectedTemplate!.emoji);
    _imageUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _emojiController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _onTemplateSelected(ScriptTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _currentCode = template.luaSource;

      // Update details controllers
      _titleController.text = template.title;
      _emojiController.text = template.emoji;
    });
  }

  void _onCodeChanged(String code) {
    _currentCode = code;
  }

  Future<void> _createScript() async {
    if (_isCreating) return;

    // Validate code first
    if (_currentCode.trim().isEmpty) {
      _showError('Lua source cannot be empty');
      return;
    }

    // Validate title
    if (_titleController.text.trim().isEmpty) {
      _showError('Title is required');
      _tabController.animateTo(1); // Switch to details tab
      return;
    }

    setState(() => _isCreating = true);

    try {
      final rec = await widget.controller.createScript(
        title: _titleController.text.trim(),
        emoji: _emojiController.text.trim().isEmpty ? null : _emojiController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Script'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Semantics(
                label: 'CODE EDITOR',
                child: const Icon(Icons.code),
              ),
              text: 'CODE EDITOR',
            ),
            Tab(
              icon: Semantics(
                label: 'DETAILS',
                child: const Icon(Icons.info_outline),
              ),
              text: 'DETAILS',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createScript,
            child: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('CREATE'),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCodeEditorTab(),
          _buildDetailsTab(),
        ],
      ),
    );
  }

  Widget _buildCodeEditorTab() {
    return Column(
      children: [
        // Compact template selector
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Template:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<ScriptTemplate>(
                  value: _selectedTemplate,
                  decoration: const InputDecoration(
                    hintText: 'Choose template',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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
        ),

        // Maximized code editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ScriptEditor(
              key: ValueKey(_selectedTemplate?.id ?? 'default'),
              initialCode: _currentCode,
              onCodeChanged: _onCodeChanged,
              language: 'lua',
              showIntegrations: true,
              minLines: 25,
            ),
          ),
        ),
      ],
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

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Script Details',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure the metadata for your script. These details will be displayed in the script list and help organize your collection.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Details form
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Enter a descriptive title for your script',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emojiController,
                    decoration: const InputDecoration(
                      labelText: 'Emoji',
                      hintText: 'Choose an emoji to represent your script',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.emoji_emotions),
                    ),
                    textInputAction: TextInputAction.next,
                    maxLength: 2,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Image URL',
                      hintText: 'Optional: local:// or https:// path to an image',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.image),
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),

                  // Helper text
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Provide either an emoji or an image URL (not both). Emojis are displayed as small icons, while images can provide more visual identity.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Template info card
          if (_selectedTemplate != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Template Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          _selectedTemplate!.emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedTemplate!.title,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedTemplate!.description,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: _selectedTemplate!.tags.map((tag) {
                                  return Chip(
                                    label: Text(
                                      tag,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                                                      );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }}
