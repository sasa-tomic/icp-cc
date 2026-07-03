import 'package:flutter/material.dart';
import '../services/diff_service.dart';
import '../theme/app_design_system.dart';

class DiffViewerDialog extends StatelessWidget {
  final String oldCode;
  final String newCode;
  final String oldVersion;
  final String newVersion;

  const DiffViewerDialog({
    super.key,
    required this.oldCode,
    required this.newCode,
    required this.oldVersion,
    required this.newVersion,
  });

  @override
  Widget build(BuildContext context) {
    final diff = DiffService.compute(oldCode, newCode);

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        constraints: const BoxConstraints(
          minWidth: 500,
          maxWidth: 900,
          minHeight: 400,
          maxHeight: 700,
        ),
        child: Column(
          children: [
            _buildHeader(context, diff),
            const Divider(height: 1),
            Expanded(
              child: diff.isEmpty
                  ? _buildEmptyState(context)
                  : _buildDiffContent(context, diff),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DiffResult diff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Changes: $oldVersion → $newVersion',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (diff.additions > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppDesignSystem.successColor
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '+${diff.additions}',
                          style: TextStyle(
                            color: AppDesignSystem.successDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (diff.deletions > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppDesignSystem.errorColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${diff.deletions}',
                          style: TextStyle(
                            color: AppDesignSystem.errorDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No changes detected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Both versions are identical',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffContent(BuildContext context, DiffResult diff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLegend(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: diff.lines.length,
            itemBuilder: (context, index) {
              return _buildDiffLine(context, diff.lines[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildLegendItem(context, AppDesignSystem.successColor, 'Added'),
          const SizedBox(width: 16),
          _buildLegendItem(context, AppDesignSystem.errorColor, 'Removed'),
          const SizedBox(width: 16),
          _buildLegendItem(context, Colors.grey, 'Unchanged'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDiffLine(BuildContext context, DiffLine line) {
    Color backgroundColor;
    Color textColor;
    String prefix;
    String lineNumber;

    switch (line.type) {
      case DiffLineType.added:
        backgroundColor = AppDesignSystem.successColor.withValues(alpha: 0.1);
        textColor = AppDesignSystem.successDark;
        prefix = '+';
        lineNumber = line.newLineNumber?.toString().padLeft(4) ?? '    ';
        break;
      case DiffLineType.removed:
        backgroundColor = AppDesignSystem.errorColor.withValues(alpha: 0.1);
        textColor = AppDesignSystem.errorDark;
        prefix = '-';
        lineNumber = line.oldLineNumber?.toString().padLeft(4) ?? '    ';
        break;
      case DiffLineType.header:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            line.content,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
          ),
        );
      case DiffLineType.unchanged:
        backgroundColor = Colors.transparent;
        textColor = Theme.of(context).colorScheme.onSurface;
        prefix = ' ';
        lineNumber = line.oldLineNumber?.toString().padLeft(4) ?? '    ';
    }

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              lineNumber,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.content.isEmpty ? ' ' : line.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
