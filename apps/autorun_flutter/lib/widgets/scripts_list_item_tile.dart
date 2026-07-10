import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import '../theme/app_design_system.dart';

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
  /// when the author uploaded artwork (UXR-4).
  Widget _buildLeading(bool isCompactScreen) {
    final radius = isCompactScreen ? 20.0 : 24.0;
    final emoji = _leadingEmoji();
    final iconUrl = item.iconUrl;

    if (iconUrl == null || iconUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Text(emoji, style: _emojiTextStyle(isCompactScreen)),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: iconUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => _avatarFallback(emoji, isCompactScreen),
          errorWidget: (context, url, error) =>
              _avatarFallback(emoji, isCompactScreen),
        ),
      ),
    );
  }

  /// Emoji shown while the icon image loads, or when it fails to load. Shared
  /// by [CachedNetworkImage]'s placeholder + errorWidget so both paths render
  /// the same fallback.
  Widget _avatarFallback(String emoji, bool isCompactScreen) =>
      Center(child: Text(emoji, style: _emojiTextStyle(isCompactScreen)));

  /// Resolved single-character emoji for the avatar: the item's emoji, else 📦
  /// for marketplace scripts, else 📜; never empty.
  String _leadingEmoji() {
    const box = '📦';
    const scroll = '📜';
    final raw = item.emoji ?? (item.isFromMarketplace ? box : scroll);
    return raw.isEmpty ? scroll : raw.characters.first;
  }

  TextStyle _emojiTextStyle(bool isCompactScreen) =>
      TextStyle(fontSize: isCompactScreen ? 16 : 20);

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
