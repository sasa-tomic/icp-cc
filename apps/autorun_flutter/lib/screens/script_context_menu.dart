import 'package:flutter/material.dart';

import '../models/script_list_item.dart';
import '../theme/app_design_system.dart';

/// Context menu bottom sheet for script quick actions
class ScriptContextMenuSheet extends StatelessWidget {
  const ScriptContextMenuSheet({
    super.key,
    required this.item,
    this.onRun,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onPublish,
    this.onViewDetails,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
  });

  final ScriptListItem item;
  final VoidCallback? onRun;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;
  final VoidCallback? onViewDetails;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                child: Text(
                  (item.emoji ?? (item.isFromMarketplace ? '📦' : '📜'))
                          .isNotEmpty
                      ? (item.emoji ??
                          (item.isFromMarketplace ? '📦' : '📜'))[0]
                      : '📜',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      item.isFromMarketplace ? 'Marketplace' : 'Local',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          if (item.source == ScriptSource.local) ..._buildLocalActions(context),
          if (item.source == ScriptSource.marketplace)
            ..._buildMarketplaceActions(context),
        ],
      ),
    );
  }

  List<Widget> _buildLocalActions(BuildContext context) {
    return [
      if (onRun != null)
        _ContextMenuAction(
          icon: Icons.play_arrow,
          label: 'Run',
          onTap: () {
            Navigator.of(context).pop();
            onRun!();
          },
          isPrimary: true,
        ),
      if (onEdit != null)
        _ContextMenuAction(
          icon: Icons.edit,
          label: 'Edit',
          onTap: () {
            Navigator.of(context).pop();
            onEdit!();
          },
        ),
      const SizedBox(height: 4),
      if (onDuplicate != null)
        _ContextMenuAction(
          icon: Icons.content_copy,
          label: 'Duplicate',
          onTap: () {
            Navigator.of(context).pop();
            onDuplicate!();
          },
        ),
      if (onPublish != null)
        _ContextMenuAction(
          icon: Icons.share,
          label: 'Share to Marketplace',
          onTap: () {
            Navigator.of(context).pop();
            onPublish!();
          },
        ),
      const SizedBox(height: 4),
      if (onDelete != null)
        _ContextMenuAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          onTap: () {
            Navigator.of(context).pop();
            onDelete!();
          },
          isDestructive: true,
        ),
    ];
  }

  List<Widget> _buildMarketplaceActions(BuildContext context) {
    return [
      if (onViewDetails != null)
        _ContextMenuAction(
          icon: Icons.info_outline,
          label: 'View Details',
          onTap: () {
            Navigator.of(context).pop();
            onViewDetails!();
          },
          isPrimary: true,
        ),
      if (onDownload != null && !isDownloaded)
        _ContextMenuAction(
          icon: Icons.download,
          label: isDownloading ? 'Downloading...' : 'Download',
          onTap: isDownloading
              ? null
              : () {
                  Navigator.of(context).pop();
                  onDownload!();
                },
          isPrimary: !isDownloaded,
        ),
      if (isDownloaded)
        _ContextMenuAction(
          icon: Icons.check_circle,
          label: 'Already Downloaded',
          onTap: null,
        ),
    ];
  }
}

/// Individual context menu action item
class _ContextMenuAction extends StatelessWidget {
  const _ContextMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color textColor;
    Color iconColor;
    Color? backgroundColor;

    if (isDestructive) {
      textColor = AppDesignSystem.errorColor;
      iconColor = AppDesignSystem.errorColor;
    } else if (isPrimary) {
      textColor = colorScheme.primary;
      iconColor = colorScheme.primary;
      backgroundColor = colorScheme.primaryContainer.withValues(alpha: 0.3);
    } else {
      textColor = colorScheme.onSurface;
      iconColor = colorScheme.onSurfaceVariant;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
                color: onTap == null ? colorScheme.outline : textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
