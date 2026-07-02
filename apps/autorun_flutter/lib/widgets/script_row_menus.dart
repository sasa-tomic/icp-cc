import 'package:flutter/material.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'hover_reveal_actions.dart';

/// Star toggle button used by both local and marketplace script row menus.
///
/// Pure extraction of `ScriptsScreenState._buildFavoriteStarButton`.
class FavoriteStarButton extends StatelessWidget {
  const FavoriteStarButton({
    super.key,
    required this.isFavorite,
    required this.onToggle,
  });

  final bool isFavorite;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_outline,
        color: isFavorite ? Colors.amber : null,
      ),
      onPressed: onToggle,
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
    );
  }
}

/// Trailing action cluster for a local script row: hover-reveal quick actions
/// (Run, Edit, Publish-if-unpublished, Delete) plus a favorite star and an
/// overflow popup menu.
///
/// Pure extraction of `ScriptsScreenState._buildLocalScriptMenu` +
/// `_handleLocalScriptMenuAction`. The popup-menu dispatch is owned by the
/// widget; all side-effecting actions are passed in as callbacks.
class LocalScriptRowMenu extends StatelessWidget {
  const LocalScriptRowMenu({
    super.key,
    required this.record,
    required this.isFavorite,
    required this.onRun,
    required this.onEdit,
    required this.onPublish,
    required this.onConfirmDelete,
    required this.onDuplicate,
    required this.onCopySource,
    required this.onViewInMarketplace,
    required this.onToggleFavorite,
  });

  final ScriptRecord record;
  final bool isFavorite;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onConfirmDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onCopySource;
  final VoidCallback onViewInMarketplace;
  final VoidCallback onToggleFavorite;

  bool get _canPublish => !record.isFromMarketplace;

  @override
  Widget build(BuildContext context) {
    final canPublish = _canPublish;

    final hoverRevealActions = <Widget>[
      ScriptActionButton(
        icon: Icons.play_arrow,
        onPressed: onRun,
        tooltip: 'Run script',
      ),
      ScriptActionButton(
        icon: Icons.edit,
        onPressed: onEdit,
        tooltip: 'Edit script',
      ),
      if (canPublish)
        ScriptActionButton(
          icon: Icons.share,
          onPressed: onPublish,
          tooltip: 'Share to Marketplace',
        ),
      ScriptActionButton(
        icon: Icons.delete_outline,
        onPressed: onConfirmDelete,
        tooltip: 'Delete script',
        isDestructive: true,
      ),
    ];

    final alwaysVisibleActions = <Widget>[
      FavoriteStarButton(isFavorite: isFavorite, onToggle: onToggleFavorite),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverRevealActions(
          actions: hoverRevealActions,
          alwaysVisibleActions: alwaysVisibleActions,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: _onMenuSelected,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 20),
                  SizedBox(width: 12),
                  Text('Duplicate'),
                ],
              ),
            ),
            if (canPublish)
              const PopupMenuItem(
                value: 'publish',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Share to Marketplace'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'copy_source',
              child: Row(
                children: [
                  Icon(Icons.copy, size: 20),
                  SizedBox(width: 12),
                  Text('Copy Source'),
                ],
              ),
            ),
            if (!canPublish)
              const PopupMenuItem(
                value: 'view_marketplace',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 20),
                    SizedBox(width: 12),
                    Text('View in Marketplace'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onMenuSelected(String action) {
    switch (action) {
      case 'run':
        onRun();
        break;
      case 'edit':
        onEdit();
        break;
      case 'publish':
        onPublish();
        break;
      case 'delete':
        onConfirmDelete();
        break;
      case 'duplicate':
        onDuplicate();
        break;
      case 'copy_source':
        onCopySource();
        break;
      case 'view_marketplace':
        onViewInMarketplace();
        break;
    }
  }
}

/// Trailing action cluster for a marketplace (not-yet-downloaded) script row:
/// a hover-reveal Download/View-Details button, a favorite star, and an
/// overflow popup menu.
///
/// Pure extraction of `ScriptsScreenState._buildMarketplaceScriptMenu` +
/// `_handleMarketplaceScriptMenuAction`.
class MarketplaceScriptRowMenu extends StatelessWidget {
  const MarketplaceScriptRowMenu({
    super.key,
    required this.script,
    required this.isDownloaded,
    required this.isDownloading,
    required this.isFavorite,
    required this.onViewDetails,
    required this.onDownload,
    required this.onShare,
    required this.onToggleFavorite,
  });

  final MarketplaceScript script;
  final bool isDownloaded;
  final bool isDownloading;
  final bool isFavorite;
  final VoidCallback onViewDetails;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final hoverRevealActions = <Widget>[
      ScriptActionButton(
        icon: isDownloaded ? Icons.info_outline : Icons.download,
        onPressed: isDownloaded ? onViewDetails : onDownload,
        tooltip: isDownloaded ? 'View details' : 'Download',
        isLoading: isDownloading,
      ),
    ];

    final alwaysVisibleActions = <Widget>[
      FavoriteStarButton(isFavorite: isFavorite, onToggle: onToggleFavorite),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverRevealActions(
          actions: hoverRevealActions,
          alwaysVisibleActions: alwaysVisibleActions,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: _onMenuSelected,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view_details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 12),
                  Text('View Details'),
                ],
              ),
            ),
            if (!isDownloaded)
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20),
                    SizedBox(width: 12),
                    Text('Download'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text('Share'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onMenuSelected(String action) {
    switch (action) {
      case 'view_details':
        onViewDetails();
        break;
      case 'download':
        onDownload();
        break;
      case 'share':
        onShare();
        break;
    }
  }
}
