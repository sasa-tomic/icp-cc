import 'package:flutter/material.dart';
import 'modern_empty_state.dart';

/// Which empty-state variant the Scripts screen should show.
enum ScriptsEmptyStateKind {
  /// No scripts at all; offers Create + Browse Marketplace.
  library,

  /// "Downloaded only" filter is active but the user has no downloads.
  downloadedFilter,

  /// "Favorites only" filter is active but the user has no favorites.
  favoritesFilter,
}

/// Empty-state widget for the Scripts screen.
///
/// Pure extraction of the inline empty-state branches that previously lived in
/// `ScriptsScreenState._buildUnifiedListView`. Behavior is unchanged: each
/// [ScriptsEmptyStateKind] maps to the same `ModernEmptyState` configuration.
///
/// Designed so a later task can extend the `library` variant (e.g. with a
/// profile-setup affordance) without touching call sites that pass the other
/// kinds.
class ScriptsEmptyState extends StatelessWidget {
  const ScriptsEmptyState({
    super.key,
    required this.kind,
    this.onCreateScript,
    this.onBrowseMarketplace,
    this.onClearDownloadedFilter,
    this.onClearFavoritesFilter,
  });

  final ScriptsEmptyStateKind kind;
  final VoidCallback? onCreateScript;
  final VoidCallback? onBrowseMarketplace;
  final VoidCallback? onClearDownloadedFilter;
  final VoidCallback? onClearFavoritesFilter;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ScriptsEmptyStateKind.downloadedFilter:
        return ModernEmptyState(
          icon: Icons.download_outlined,
          title: "You haven't downloaded any scripts yet",
          subtitle: 'Browse the marketplace to find scripts to download',
          action: onClearDownloadedFilter,
          actionLabel: 'Browse Marketplace',
        );
      case ScriptsEmptyStateKind.favoritesFilter:
        return ModernEmptyState(
          icon: Icons.star_outline,
          title: "You haven't favorited any scripts yet",
          subtitle: 'Tap the star icon on scripts to add them to favorites',
          action: onClearFavoritesFilter,
          actionLabel: 'Browse Scripts',
        );
      case ScriptsEmptyStateKind.library:
        return ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Create your first script or browse the marketplace',
          action: onCreateScript,
          actionLabel: 'Create Script',
          secondaryAction: onBrowseMarketplace,
          secondaryActionLabel: 'Browse Marketplace',
        );
    }
  }
}
