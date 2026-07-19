import 'package:flutter/material.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import '../theme/app_design_system.dart';
import 'script_leading_icon.dart';
import 'trust_badges.dart';

/// A single row in the unified Scripts list.
///
/// Pure extraction of `ScriptsScreenState._buildAllScriptsListItem` plus its
/// private helpers (`_buildSourceIcon`, `_buildItemSubtitle`,
/// `_formatRelativeTime`). Layout, styling and compact-screen behavior are
/// unchanged. The trailing action cluster, tap and long-press / right-click
/// handlers are supplied by the caller so this widget stays presentational.
class ScriptsListItemTile extends StatelessWidget {
  const ScriptsListItemTile({
    super.key,
    required this.item,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  final ScriptListItem item;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapUpDetails)? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;

    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTapUp: onSecondaryTapUp,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompactScreen ? 12 : 16,
          vertical: 4,
        ),
        leading: _buildLeading(isCompactScreen),
        title: Row(
          children: [
            _buildSourceIcon(isCompactScreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: isCompactScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (!item.isInstalled && item.source == ScriptSource.marketplace)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.download_outlined,
                  size: isCompactScreen ? 14 : 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isCompactScreen ? 2 : 4),
            Text(
              _buildItemSubtitle(),
              style: TextStyle(
                fontSize: isCompactScreen ? 11 : 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: isCompactScreen ? 2 : 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                const SandboxedChip(),
                if (item.author != null && item.author!.isNotEmpty)
                  SignedByChip(
                    author: item.author!,
                    verified:
                        item.marketplaceScript?.author?.isVerifiedDeveloper ??
                            false,
                  ),
              ],
            ),
          ],
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  /// Leading avatar for the row.
  ///
  /// Marketplace scripts (and local scripts with an image) render their
  /// `iconUrl` artwork; emoji-only scripts render the emoji. On image load
  /// failure the emoji fallback is shown, so a broken image never degrades the
  /// row. Without this, every marketplace tile shows the same generic 📦 even
  /// when the author uploaded artwork (UXR-4). The rendering lives in the
  /// shared [ScriptLeadingIcon] so the run panel stays consistent (W7-19).
  Widget _buildLeading(bool isCompactScreen) {
    final radius = isCompactScreen ? 20.0 : 24.0;
    return ScriptLeadingIcon(
      iconUrl: item.iconUrl,
      emoji: item.emoji,
      isMarketplace: item.isFromMarketplace,
      radius: radius,
    );
  }

  /// Small color-coded source icon.
  /// Blue for local scripts, green for marketplace scripts.
  Widget _buildSourceIcon(bool isCompactScreen) {
    final isMarketplace = item.isFromMarketplace;
    final iconColor = isMarketplace ? AppDesignSystem.successColor : Colors.blue;
    final iconSize = isCompactScreen ? 12.0 : 14.0;

    return Icon(
      isMarketplace ? Icons.cloud_outlined : Icons.folder_outlined,
      size: iconSize,
      color: iconColor,
    );
  }

  /// Simplified subtitle for script list items.
  /// - For marketplace scripts: shows author only
  /// - For local scripts: shows relative date only
  String _buildItemSubtitle() {
    // For downloaded marketplace scripts (local with marketplace metadata)
    if (item.source == ScriptSource.local && item.author != null) {
      return item.author!;
    }

    // For marketplace scripts, show author
    if (item.source == ScriptSource.marketplace) {
      return item.author ?? 'Unknown';
    }

    // For local scripts without author, show relative date
    return _formatRelativeTime(item.updatedAt);
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
