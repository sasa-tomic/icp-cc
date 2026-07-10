import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/native_bridge.dart';
import '../services/bookmarks_service.dart';
import '../theme/app_design_system.dart';
import 'modern_empty_state.dart';

class BookmarksList extends StatefulWidget {
  const BookmarksList({
    super.key,
    required this.bridge,
    required this.onTapEntry,
    this.onExplorePopular,
  });
  final RustBridgeLoader bridge;
  final void Function(String canisterId, String method) onTapEntry;
  final VoidCallback? onExplorePopular;

  @override
  State<BookmarksList> createState() => _BookmarksListState();
}

class _BookmarksListState extends State<BookmarksList> {
  List<BookmarkEntry> _entries = const <BookmarkEntry>[];
  String? _loadError;
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _reload();
    _listener = _reload;
    BookmarksEvents.listenable.addListener(_listener);
  }

  @override
  void dispose() {
    BookmarksEvents.listenable.removeListener(_listener);
    super.dispose();
  }

  void _reload() async {
    try {
      final entries = await BookmarksService.list();
      if (mounted) {
        setState(() {
          _entries = entries;
          _loadError = null;
        });
      }
    } catch (e) {
      // Surface the load failure LOUDLY instead of silently rendering an empty
      // list. An empty list would read as "no bookmarks" to the user, who could
      // then add one — triggering a save that overwrites the corrupt file and
      // permanently destroys the (partially recoverable) data. Showing an
      // explicit error + retry blocks that path. See F-3 / QS-3.
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    if (error != null) {
      return _buildLoadError(context, error);
    }
    if (_entries.isEmpty) {
      return ModernEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'No Bookmarks Yet',
        subtitle: 'Save your favorite canister methods for quick access',
        action: widget.onExplorePopular,
        actionLabel: 'Explore Popular Canisters',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final entry = _entries[index];
        final cid = entry.canisterId;
        final method = entry.method;
        final label = entry.label ?? '';

        return Card(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () => widget.onTapEntry(cid, method),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withValues(alpha: 0.2),
                          Colors.indigo.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.isNotEmpty ? label : method,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cid,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            method,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppDesignSystem.errorColor,
                          size: 20,
                        ),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await BookmarksService.remove(
                                canisterId: cid, method: method);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: const Text('Bookmark removed'),
                                  backgroundColor: Colors.blue.shade500,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Failed to remove bookmark: $e')),
                              );
                            }
                          }
                        },
                        tooltip: 'Remove bookmark',
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Surfaces a corrupt-load failure loudly (F-3 / QS-3). Distinct from the
  /// empty state: the message tells the user the file is damaged and was NOT
  /// overwritten, and offers a retry. This blocks the data-loss path where a
  /// user mistaking the empty list for "no bookmarks" adds one and clobbers
  /// the corrupt-but-recoverable file.
  Widget _buildLoadError(BuildContext context, String error) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not load bookmarks',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Your bookmarks file is damaged and wasn't loaded — this "
                'protects it from being overwritten. Restore a backup if you '
                'have one, then retry.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
