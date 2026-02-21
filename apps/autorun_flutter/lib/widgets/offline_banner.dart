import 'package:flutter/material.dart';

/// A dismissible banner that displays when the user is offline.
///
/// Shows a warning message with an amber background and info icon.
/// Can be dismissed with an X button. The dismiss state is managed
/// by the parent widget via [onDismiss] callback.
class OfflineBanner extends StatelessWidget {
  /// Creates an offline banner.
  const OfflineBanner({
    super.key,
    required this.isOnline,
    this.onDismiss,
  });

  /// Whether the user is currently online.
  /// When `false`, the banner is displayed.
  final bool isOnline;

  /// Called when the user taps the dismiss button.
  /// The parent should handle persisting the dismiss state.
  final VoidCallback? onDismiss;

  static const String _message =
      "You're offline. Some features may be unavailable.";

  @override
  Widget build(BuildContext context) {
    // Hide when online
    if (isOnline) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        border: Border(
          bottom: BorderSide(
            color: Colors.amber.shade300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.amber.shade900,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _message,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.close,
              color: Colors.amber.shade900,
              size: 18,
            ),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
