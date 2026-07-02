import 'package:flutter/material.dart';

import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../theme/app_design_system.dart';
import '../widgets/script_editor.dart';

/// Improved script editor dialog with syntax highlighting and improved UX
class ScriptEditorDialog extends StatefulWidget {
  const ScriptEditorDialog(
      {super.key, required this.controller, required this.record});
  final ScriptController controller;
  final ScriptRecord record;

  @override
  State<ScriptEditorDialog> createState() => ScriptEditorDialogState();
}

class ScriptEditorDialogState extends State<ScriptEditorDialog> {
  bool _saving = false;
  late final ValueNotifier<String> _codeNotifier;
  final GlobalKey<ScriptEditorState> _editorKey =
      GlobalKey<ScriptEditorState>();

  @override
  void initState() {
    super.initState();
    _codeNotifier = ValueNotifier<String>(widget.record.bundle);
  }

  @override
  void dispose() {
    _codeNotifier.dispose();
    super.dispose();
  }

  void _onCodeChanged(String code) {
    _codeNotifier.value = code;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateSource(
        id: widget.record.id,
        bundle: _codeNotifier.value,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar('Script saved successfully!'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Handle cancel/close with unsaved changes check
  Future<void> _handleCancel() async {
    final isDirty = _editorKey.currentState?.isDirty ?? false;
    if (!isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final shouldDiscard = await showUnsavedChangesDialog(context);
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompactScreen = screenSize.width < 400;

    return PopScope(
      canPop: !(_editorKey.currentState?.isDirty ?? false),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleCancel();
      },
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: screenSize.width,
          height: screenSize.height,
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              // Compact Header
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isCompactScreen ? 12 : 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit,
                      color: Theme.of(context).colorScheme.primary,
                      size: isCompactScreen ? 18 : 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.record.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isCompactScreen ? 14 : 16,
                                ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (!isCompactScreen) ...[
                      TextButton(
                        onPressed: _handleCancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save, size: 16),
                      label: const Text('Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                    if (isCompactScreen) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _handleCancel,
                        icon: const Icon(Icons.close),
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),

              // Maximized Editor
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isCompactScreen ? 4 : 8),
                  child: ScriptEditor(
                    key: _editorKey,
                    initialCode: widget.record.bundle,
                    onCodeChanged: _onCodeChanged,
                    showIntegrations: !isCompactScreen,
                    minLines: isCompactScreen ? 20 : 30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
