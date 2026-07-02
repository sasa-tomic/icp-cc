import 'package:flutter/material.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/models/script_record.dart';
import '../theme/app_design_system.dart';
import 'package:icp_autorun/screens/script_context_menu.dart';
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

/// Bundles the side-effecting callbacks a script context menu can trigger.
/// Passed into [showScriptContextMenuSheet] / [showScriptContextMenuPopup] so
/// the menu code stays free of ScriptsScreen state.
class ScriptContextMenuActions {
  const ScriptContextMenuActions({
    this.onRun,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onPublish,
    this.onCopySource,
    this.onViewDetails,
    this.onDownload,
    this.onShare,
    this.isDownloading = false,
  });

  final VoidCallback? onRun;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;
  final VoidCallback? onCopySource;
  final VoidCallback? onViewDetails;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;
  final bool isDownloading;
}

/// Builds the popup-menu entries for a script row's secondary (right-click)
/// context menu.
///
/// Pure extraction of `ScriptsScreenState._buildContextMenuItems`.
/// `canPublish` (local scripts only) and `isDownloaded` (marketplace scripts
/// only) are supplied by the caller.
List<PopupMenuEntry<String>> buildScriptContextMenuItems(
  ScriptListItem item, {
  required bool canPublish,
  required bool isDownloaded,
}) {
  final items = <PopupMenuEntry<String>>[];

  if (item.source == ScriptSource.local && item.localScript != null) {
    items.addAll([
      const PopupMenuItem(
        value: 'run',
        child: Row(
          children: [
            Icon(Icons.play_arrow, size: 20),
            SizedBox(width: 12),
            Text('Run'),
          ],
        ),
      ),
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
    ]);
  } else if (item.source == ScriptSource.marketplace &&
      item.marketplaceScript != null) {
    items.addAll([
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
        PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              const Icon(Icons.download, size: 20),
              const SizedBox(width: 12),
              Text(
                  'Download${item.marketplaceScript!.price > 0 ? ' (${item.marketplaceScript!.price} credits)' : ''}'),
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
    ]);
  }

  return items;
}

/// Dispatches a context-menu action string to the matching callback in
/// [actions]. Pure extraction of `ScriptsScreenState._handleContextMenuAction`.
void handleScriptContextMenuAction(
  String action,
  ScriptListItem item,
  ScriptContextMenuActions actions,
) {
  switch (action) {
    case 'run':
      if (item.localScript != null) actions.onRun?.call();
      break;
    case 'edit':
      if (item.localScript != null) actions.onEdit?.call();
      break;
    case 'duplicate':
      if (item.localScript != null) actions.onDuplicate?.call();
      break;
    case 'delete':
      if (item.localScript != null) actions.onDelete?.call();
      break;
    case 'publish':
      if (item.localScript != null) actions.onPublish?.call();
      break;
    case 'copy_source':
      if (item.localScript != null) actions.onCopySource?.call();
      break;
    case 'view_details':
      if (item.marketplaceScript != null) actions.onViewDetails?.call();
      break;
    case 'download':
      if (item.marketplaceScript != null) actions.onDownload?.call();
      break;
    case 'share':
      if (item.marketplaceScript != null) actions.onShare?.call();
      break;
  }
}

/// Opens the long-press bottom-sheet context menu for a script row.
/// Pure extraction of `ScriptsScreenState._showScriptContextMenu`.
void showScriptContextMenuSheet(
  BuildContext context,
  ScriptListItem item,
  ScriptContextMenuActions actions,
) {
  final isLocal = item.source == ScriptSource.local && item.localScript != null;
  final isMarketplace =
      item.source == ScriptSource.marketplace && item.marketplaceScript != null;

  showModalBottomSheet<void>(
    context: context,
    shape: RoundedRectangleBorder(
      borderRadius: AppDesignSystem.sheetBorderRadius,
    ),
    builder: (context) => ScriptContextMenuSheet(
      item: item,
      onRun: isLocal ? actions.onRun : null,
      onEdit: isLocal ? actions.onEdit : null,
      onDuplicate: isLocal ? actions.onDuplicate : null,
      onDelete: isLocal ? actions.onDelete : null,
      onPublish: isLocal ? actions.onPublish : null,
      onViewDetails: isMarketplace ? actions.onViewDetails : null,
      onDownload: isMarketplace && !item.isInstalled ? actions.onDownload : null,
      isDownloading: isMarketplace ? actions.isDownloading : false,
      isDownloaded: item.isInstalled,
    ),
  );
}

/// Opens the right-click popup context menu for a script row at [position].
/// Pure extraction of `ScriptsScreenState._showScriptContextMenuAt`.
void showScriptContextMenuPopup(
  BuildContext context,
  ScriptListItem item,
  Offset position,
  ScriptContextMenuActions actions, {
  required bool canPublish,
  required bool isDownloaded,
}) {
  final overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: buildScriptContextMenuItems(item,
        canPublish: canPublish, isDownloaded: isDownloaded),
  ).then((value) {
    if (value != null) {
      handleScriptContextMenuAction(value, item, actions);
    }
  });
}
