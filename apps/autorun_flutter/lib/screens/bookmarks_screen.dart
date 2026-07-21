import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/native_bridge.dart';
import '../services/bookmarks_service.dart';
import '../theme/app_design_system.dart';
import '../widgets/bookmark_composer.dart';
import '../widgets/bookmarks_list.dart';
import '../widgets/canister_client_sheet.dart';
import '../utils/friendly_error.dart';
import '../widgets/connectivity_scope.dart';
import '../widgets/offline_banner.dart';
import '../widgets/recent_calls_list.dart';
import '../widgets/well_known_canisters.dart';

/// Single source of truth for the Canisters tab label (UX-2).
///
/// Used by BOTH the bottom-nav tab ([main.dart] `_buildModernNavigationBar`)
/// and this screen's AppBar title, so a new user always sees the same name on
/// the tab they tapped and on the screen header. Previously the tab said
/// "Canisters" while the AppBar said "Explore ICP Services" — an honesty gap.
const String kCanistersTabLabel = 'Canisters';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key, required this.bridge});

  final RustBridgeLoader bridge;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _popularCanistersKey = GlobalKey();

  void _scrollToPopularCanisters() {
    final context = _popularCanistersKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: AppDurations.slower,
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _refreshContent() async {
    BookmarksService.invalidateCache();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await BookmarksService.list();
    } catch (e) {
      // A corrupt bookmarks file now throws BookmarksLoadException rather than
      // silently returning [] (F-3/QS-3). Surface it on pull-to-refresh instead
      // of letting it escape as an unhandled async error; the BookmarksList
      // widget also re-runs its own load below and renders its inline
      // error/retry state.
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e, context: 'Could not load bookmarks')),
          backgroundColor: errorColor,
        ),
      );
    }
    // Always notify so the list widget re-runs its own load (and shows its
    // inline error/retry state on failure rather than a stale empty view).
    BookmarksEvents.notifyChanged();
  }

  void _openInlineClient(
      {String? initialCanisterId, String? initialMethodName}) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDesignSystem.sheetBorderRadius,
      ),
      builder: (context) => CanisterClientSheet(
        bridge: widget.bridge,
        initialCanisterId: initialCanisterId,
        initialMethodName: initialMethodName,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(kCanistersTabLabel),
            SizedBox(height: 2),
            Text(
              'Call Internet Computer canisters directly',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            OfflineBanner(
              isOnline: ConnectivityScope.of(context).isOnline,
              onDismiss: () =>
                  ConnectivityScope.of(context, listen: false).dismissBanner(),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: RefreshIndicator(
                  onRefresh: _refreshContent,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          key: _popularCanistersKey,
                          child: _buildSectionHeader(
                            context,
                            title: 'Popular Canisters',
                            subtitle: 'Quick access to essential ICP services',
                            icon: Icons.star_rounded,
                          ),
                        ),
                        const SizedBox(height: 16),
                        WellKnownList(
                            onSelect: (cid, method) {
                              _openInlineClient(
                                initialCanisterId: cid,
                                initialMethodName:
                                    method?.isNotEmpty == true ? method : null,
                              );
                            },
                            onBookmark: (entry) =>
                                _bookmarkWellKnown(context, entry)),
                        const SizedBox(height: 32),
                        _buildSectionHeader(
                          context,
                          title: 'Your Bookmarks',
                          subtitle:
                              'Your saved canister methods for quick access',
                          icon: Icons.bookmark_rounded,
                        ),
                        const SizedBox(height: 16),
                        BookmarkComposer(
                          onSave: BookmarksService.add,
                          onSaved: (cid, method, label) {
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Saved ${label ?? method} to bookmarks'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        BookmarksList(
                          bridge: widget.bridge,
                          onTapEntry: (cid, method) {
                            _openInlineClient(
                                initialCanisterId: cid,
                                initialMethodName: method);
                          },
                          onExplorePopular: _scrollToPopularCanisters,
                        ),
                        const SizedBox(height: 32),
                        _buildSectionHeader(
                          context,
                          title: 'Recent Calls',
                          subtitle: 'Your recent canister method calls',
                          icon: Icons.history_rounded,
                        ),
                        const SizedBox(height: 16),
                        RecentCallsList(
                          onTapEntry: (cid, method, args) {
                            _openInlineClient(
                                initialCanisterId: cid,
                                initialMethodName: method);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;

    return Container(
      padding: EdgeInsets.all(isCompactScreen ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isCompactScreen ? 12 : 16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isCompactScreen ? 10 : 12),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: isCompactScreen ? 20 : 24,
            ),
          ),
          SizedBox(width: isCompactScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: isCompactScreen ? 18 : 20,
                        letterSpacing: -0.5,
                      ),
                ),
                SizedBox(height: isCompactScreen ? 2 : 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: isCompactScreen ? 12 : 14,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bookmarkWellKnown(
      BuildContext context, WellKnownCanister entry) {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return BookmarksService.add(
      canisterId: entry.canisterId,
      method: entry.method ?? 'http_request',
      label: entry.label,
    ).then((_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Bookmarked ${entry.label}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }).catchError((Object e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e, context: 'Failed to bookmark ${entry.label}')),
          backgroundColor: colorScheme.error,
        ),
      );
    });
  }
}
