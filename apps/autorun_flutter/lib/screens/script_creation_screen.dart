import 'package:flutter/material.dart';
import '../controllers/script_controller.dart';
import '../models/script_template.dart';
import '../theme/app_design_system.dart';
import '../widgets/script_editor.dart';

/// Blank script template for starting from scratch
class _BlankScriptTemplate extends ScriptTemplate {
  _BlankScriptTemplate()
      : super(
          id: 'blank',
          title: 'Blank Script',
          description:
              'Start with a clean slate and write your script from scratch.',
          emoji: '📄',
          level: 'beginner',
          tags: ['blank', 'empty'],
          preloadedBundle: '''// Blank Script — a minimal TypeScript/QuickJS bundle.
"use strict";
(() => {
  function init() {
    return { state: {}, effects: [] };
  }
  function view(_state) {
    return { type: "text", props: { text: "Hello World" } };
  }
  function update(_msg, state) {
    return { state: state, effects: [] };
  }
  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''',
        );
}

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
  bool _templatesExpanded = true;

  @override
  void initState() {
    super.initState();

    // Build template list: Blank Script first, then all others
    _availableTemplates = [
      _BlankScriptTemplate(),
      ...ScriptTemplates.templates,
    ];

    if (widget.initialTemplate != null) {
      // Check if initial template is in our available templates
      final matchingTemplate = _availableTemplates
          .where((t) => t.id == widget.initialTemplate!.id)
          .firstOrNull;
      if (matchingTemplate != null) {
        _selectedTemplate = matchingTemplate;
      } else {
        _availableTemplates = [
          _BlankScriptTemplate(),
          widget.initialTemplate!,
          ...ScriptTemplates.templates
        ];
        _selectedTemplate = widget.initialTemplate!;
      }
    } else {
      // Default to first template (Hello World, not Blank)
      _selectedTemplate = ScriptTemplates.templates.first;
    }

    _currentCode = _selectedTemplate!.bundle;

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
      _currentCode = template.bundle;

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
      _showError('Bundle cannot be empty');
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
        bundleOverride: _currentCode,
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
        return AppDesignSystem.successColor;
      case 'intermediate':
        return AppDesignSystem.warningColor;
      case 'advanced':
        return AppDesignSystem.errorColor;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with collapse/expand button
        GestureDetector(
          onTap: () => setState(() => _templatesExpanded = !_templatesExpanded),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Choose a Template',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Icon(
                  _templatesExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // Template cards grid - use Wrap so all are visible
        if (_templatesExpanded)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _availableTemplates.map((template) {
              final isSelected = _selectedTemplate?.id == template.id;
              return _buildTemplateCard(template, isSelected);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildTemplateCard(ScriptTemplate template, bool isSelected) {
    final levelColor = _getLevelColor(template.level);
    final levelLabel = _getLevelLabel(template.level);

    return GestureDetector(
      key: Key('template_card_${template.id}'),
      onTap: () => _onTemplateSelected(template),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 200,
        height: 170,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.7),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji icon
                  Text(
                    template.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  // Title
                  Text(
                    template.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Description
                  Text(
                    template.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  // Difficulty badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: levelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: levelColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      levelLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: levelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Selected indicator
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  key: const Key('template_card_selected'),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getLevelLabel(String level) {
    switch (level) {
      case 'beginner':
        return 'Beginner';
      case 'intermediate':
        return 'Intermediate';
      case 'advanced':
        return 'Advanced';
      default:
        return level[0].toUpperCase() + level.substring(1);
    }
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
                  'TypeScript Source',
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
