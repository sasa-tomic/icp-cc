import 'package:flutter/material.dart';
import 'package:icp_autorun/utils/error_categories.dart';

class ErrorDisplay extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final String? retryText;
  final Object? errorObject;

  const ErrorDisplay({
    super.key,
    required this.error,
    this.onRetry,
    this.retryText = 'Retry',
    this.errorObject,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveError = errorObject ?? error;
    final category = categorizeError(effectiveError);
    final info = getErrorInfo(category);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              info.icon,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              info.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              info.suggestedAction,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(retryText!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _showHelpDialog(context),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Get Help'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Technical Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error Message:',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              SelectableText(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
              if (errorObject != null && errorObject.toString() != error) ...[
                const SizedBox(height: 16),
                Text(
                  'Technical Info:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  errorObject.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
