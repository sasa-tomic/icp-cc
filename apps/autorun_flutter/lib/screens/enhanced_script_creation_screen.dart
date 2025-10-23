import 'package:flutter/material.dart';
import '../controllers/script_controller.dart';
import '../models/script_template.dart';
import '../widgets/enhanced_script_editor.dart';

/// Enhanced script creation flow with improved UX and separated concerns
class EnhancedScriptCreationScreen extends StatefulWidget {
  const EnhancedScriptCreationScreen({
    super.key,
    required this.controller,
    this.initialTemplate,
  });

  final ScriptController controller;
  final ScriptTemplate? initialTemplate;

  @override
  State<EnhancedScriptCreationScreen> createState() => _EnhancedScriptCreationScreenState();
}

class _EnhancedScriptCreationScreenState extends State<EnhancedScriptCreationScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late final TextEditingController _imageUrlController;

  String _currentCode = '';
  bool _isCreating = false;
  ScriptTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Initialize with template or defaults
    _selectedTemplate = widget.initialTemplate ?? ScriptTemplates.templates.first;
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
          tabs: const [
            Tab(
              icon: Icon(Icons.code),
              text: 'CODE EDITOR',
            ),
            Tab(
              icon: Icon(Icons.info_outline),
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
      floatingActionButton: _selectedTemplate == null
          ? FloatingActionButton.extended(
              onPressed: _showTemplateSelection,
              icon: const Icon(Icons.library_books),
              label: const Text('Choose Template'),
            )
          : null,
    );
  }

  Widget _buildCodeEditorTab() {
    return Column(
      children: [
        // Template selector (collapsed when template is selected)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _selectedTemplate != null ? 80 : 120,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _selectedTemplate?.title ?? 'Choose a Template',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      if (_selectedTemplate != null)
                        TextButton.icon(
                          onPressed: _showTemplateSelection,
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Change'),
                                                  ),
                    ],
                  ),
                  if (_selectedTemplate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _selectedTemplate!.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showTemplateSelection,
                        icon: const Icon(Icons.library_books),
                        label: const Text('Browse Templates'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Enhanced code editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: EnhancedScriptEditor(
              initialCode: _currentCode,
              onCodeChanged: _onCodeChanged,
              language: 'lua',
              showIntegrations: true,
              minLines: 20,
            ),
          ),
        ),
      ],
    );
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
  }

  void _showTemplateSelection() {
    showDialog<ScriptTemplate>(
      context: context,
      builder: (_) => _EnhancedTemplateSelectionDialog(
        onTemplateSelected: _onTemplateSelected,
        initialTemplate: _selectedTemplate,
      ),
    );
  }
}

/// Enhanced template selection dialog
class _EnhancedTemplateSelectionDialog extends StatefulWidget {
  const _EnhancedTemplateSelectionDialog({
    required this.onTemplateSelected,
    this.initialTemplate,
  });

  final Function(ScriptTemplate) onTemplateSelected;
  final ScriptTemplate? initialTemplate;

  @override
  State<_EnhancedTemplateSelectionDialog> createState() => _EnhancedTemplateSelectionDialogState();
}

class _EnhancedTemplateSelectionDialogState extends State<_EnhancedTemplateSelectionDialog> {
  String _selectedLevel = 'all';
  String _searchQuery = '';

  List<ScriptTemplate> get _filteredTemplates {
    var templates = ScriptTemplates.templates;

    // Filter by level
    if (_selectedLevel != 'all') {
      templates = templates.where((t) => t.level == _selectedLevel).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      templates = ScriptTemplates.search(_searchQuery);
    }

    return templates;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.library_books, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Choose a Template',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select a template to get started with your Lua script',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),

            // Search and Filter
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search templates...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'beginner', label: Text('Beginner')),
                    ButtonSegment(value: 'intermediate', label: Text('Intermediate')),
                    ButtonSegment(value: 'advanced', label: Text('Advanced')),
                  ],
                  selected: {_selectedLevel},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() => _selectedLevel = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Template Grid
            Expanded(
              child: _filteredTemplates.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No templates found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search or filters',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _filteredTemplates.length,
                      itemBuilder: (context, index) {
                        final template = _filteredTemplates[index];
                        return _EnhancedTemplateCard(
                          template: template,
                          onTap: () {
                            widget.onTemplateSelected(template);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),

            // Footer
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
                TextButton.icon(
                  onPressed: () {
                    // Use default template
                    final defaultTemplate = ScriptTemplates.templates.firstWhere(
                      (t) => t.id == 'hello_world',
                    );
                    widget.onTemplateSelected(defaultTemplate);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.bolt),
                  label: const Text('Start with Default'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Enhanced template card widget
class _EnhancedTemplateCard extends StatelessWidget {
  const _EnhancedTemplateCard({
    required this.template,
    required this.onTap,
  });

  final ScriptTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    template.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getLevelColor(template.level, colorScheme),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                template.level.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (template.isRecommended) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.star, size: 12, color: Colors.amber[600]),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Description
              Expanded(
                child: Text(
                  template.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Tags
              const SizedBox(height: 8),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: template.tags.take(2).map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 8,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getLevelColor(String level, ColorScheme colorScheme) {
    switch (level) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'advanced':
        return Colors.red;
      default:
        return colorScheme.primary;
    }
  }
}