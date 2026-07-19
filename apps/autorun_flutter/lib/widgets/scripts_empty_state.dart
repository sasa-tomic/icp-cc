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

  /// A search query is active but matched nothing. Distinct from [library]
  /// so the user is told "no results" (with a Clear-search affordance) rather
  /// than the misleading "Your library is empty" when scripts ARE installed
  /// (W6-8 / UX finding W6-6). The query string is passed via [searchQuery].
  searchNoResults,
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
    this.hasProfile = true,
    this.searchQuery,
    this.onCreateScript,
    this.onBrowseMarketplace,
    this.onSetupProfile,
    this.onClearDownloadedFilter,
    this.onClearFavoritesFilter,
    this.onClearSearch,
  });

  final ScriptsEmptyStateKind kind;

  /// Whether an active profile exists. Only consulted by the [library] variant:
  /// when `false`, the empty state offers a "Set Up Profile" primary action that
  /// re-opens the setup wizard instead of the keypair-dependent Create / Browse
  /// CTAs (which lead to broken flows when no keypair exists). Defaults to
  /// `true` so call sites that don't supply it keep the legacy behavior.
  final bool hasProfile;

  /// The active search query. Only consulted by the [searchNoResults] variant,
  /// which echoes it back so the user sees *which* term found nothing.
  final String? searchQuery;

  final VoidCallback? onCreateScript;
  final VoidCallback? onBrowseMarketplace;
  final VoidCallback? onSetupProfile;
  final VoidCallback? onClearDownloadedFilter;
  final VoidCallback? onClearFavoritesFilter;

  /// Clears the active search query. The primary action of the
  /// [searchNoResults] variant.
  final VoidCallback? onClearSearch;

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
          actionIcon: Icons.storefront_rounded,
        );
      case ScriptsEmptyStateKind.favoritesFilter:
        return ModernEmptyState(
          icon: Icons.star_outline,
          title: "You haven't favorited any scripts yet",
          subtitle: 'Tap the star icon on scripts to add them to favorites',
          action: onClearFavoritesFilter,
          actionLabel: 'Browse Marketplace',
          actionIcon: Icons.storefront_rounded,
        );
      case ScriptsEmptyStateKind.searchNoResults:
        // Echo the query so the user can see *which* term found nothing. The
        // primary action clears the search rather than nudging them to create
        // a script — the library isn't empty, the search just had no hits.
        final query = searchQuery ?? '';
        return ModernEmptyState(
          icon: Icons.search_off_rounded,
          title: "No scripts match '$query'",
          subtitle: 'Try a different search term, or clear the search.',
          action: onClearSearch,
          actionLabel: 'Clear search',
        );
      case ScriptsEmptyStateKind.library:
        if (!hasProfile) {
          return ModernEmptyState(
            icon: Icons.person_outline_rounded,
            title: 'Set Up Your Profile',
            subtitle:
                'Create a profile to start building, running, and sharing scripts',
            action: onSetupProfile,
            actionLabel: 'Set Up Profile',
            actionIcon: Icons.person_add_rounded,
          );
        }
        return ModernEmptyState(
          icon: Icons.code_rounded,
          title: 'Your Script Library is Empty',
          subtitle: 'Browse the marketplace to find scripts, or create your own',
          action: onBrowseMarketplace,
          actionLabel: 'Browse Marketplace',
          actionIcon: Icons.storefront_rounded,
          secondaryAction: onCreateScript,
          secondaryActionLabel: 'Create Script',
        );
    }
  }
}
