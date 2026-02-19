import 'package:flutter/material.dart';
import '../models/script_execution_progress.dart';

class ScriptExecutionProgressIndicator extends StatelessWidget {
  const ScriptExecutionProgressIndicator({
    super.key,
    required this.progress,
    this.onCancel,
  });

  final ScriptExecutionProgress progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getBorderColor(colorScheme),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusIcon(colorScheme),
            const SizedBox(height: 12),
            Text(
              progress.message.isNotEmpty
                  ? progress.message
                  : progress.phase.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _getTextColor(colorScheme),
              ),
              textAlign: TextAlign.center,
            ),
            if (progress.isCancellable && onCancel != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel, size: 18),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme colorScheme) {
    switch (progress.phase) {
      case ScriptExecutionPhase.complete:
        return Icon(
          Icons.check_circle,
          size: 48,
          color: Colors.green,
        );
      case ScriptExecutionPhase.error:
        return Icon(
          Icons.error_outline,
          size: 48,
          color: colorScheme.error,
        );
      default:
        return SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        );
    }
  }

  Color _getBorderColor(ColorScheme colorScheme) {
    switch (progress.phase) {
      case ScriptExecutionPhase.error:
        return colorScheme.error.withValues(alpha: 0.5);
      case ScriptExecutionPhase.complete:
        return Colors.green.withValues(alpha: 0.5);
      default:
        return colorScheme.outline.withValues(alpha: 0.3);
    }
  }

  Color _getTextColor(ColorScheme colorScheme) {
    switch (progress.phase) {
      case ScriptExecutionPhase.error:
        return colorScheme.error;
      default:
        return colorScheme.onSurface;
    }
  }
}
