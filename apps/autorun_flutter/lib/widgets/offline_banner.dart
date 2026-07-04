import 'package:flutter/material.dart';

import 'package:icp_autorun/theme/app_design_system.dart';

/// A dismissible banner that displays when the user is offline.
///
/// Shows a warning message (themed via [AppDesignSystem.warningColor]) with an
/// info icon. Can be dismissed with an X button. The dismiss state is managed
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
        // Offline == warning status: derive the whole palette (bg tint /
        // border / foreground) from the single warningColor token so a
        // status-palette swap stays a one-file change in AppDesignSystem.
        color: AppDesignSystem.warningColor.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: AppDesignSystem.warningColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: AppDesignSystem.warningColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _message,
              style: textTheme.bodyMedium?.copyWith(
                color: AppDesignSystem.warningColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.close,
              color: AppDesignSystem.warningColor,
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
