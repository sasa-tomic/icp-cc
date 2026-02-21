import 'package:flutter/material.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:icp_autorun/services/favorites_service.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/widgets/loading_indicator.dart';

class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({
    super.key,
    this.downloadHistoryService,
    this.favoritesService,
    this.scriptRepository,
  });

  final DownloadHistoryService? downloadHistoryService;
  final FavoritesService? favoritesService;
  final ScriptRepository? scriptRepository;

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  late final DownloadHistoryService _downloadHistoryService;
  late final FavoritesService _favoritesService;
  late final ScriptController _scriptController;

  List<DownloadRecord> _downloadHistory = [];
  Set<String> _favoriteScriptIds = {};
  List<ScriptRecord> _localScripts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _downloadHistoryService =
        widget.downloadHistoryService ?? DownloadHistoryService();
    _favoritesService = widget.favoritesService ?? FavoritesService();
    _scriptController = ScriptController(
      widget.scriptRepository ?? ScriptRepository.instance,
    );
    _loadData();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final downloads = await _downloadHistoryService.getDownloadHistory();
      final favorites = await _favoritesService.getAllFavorites();
      await _scriptController.ensureLoaded();

      if (mounted) {
        setState(() {
          _downloadHistory = downloads;
          _favoriteScriptIds = favorites;
          _localScripts = _scriptController.scripts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const LoadingIndicator(message: 'Loading your library...')
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    final recentActivity = _getRecentActivity();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LibrarySection(
          title: 'Downloads',
          count: _downloadHistory.length,
          icon: Icons.download_done,
          emptyText: 'No downloads yet',
          emptySubtitle:
              'Scripts you download from the marketplace will appear here',
          emptyIcon: Icons.download_for_offline_outlined,
          children: _downloadHistory
              .map((record) => _DownloadTile(record: record))
              .toList(),
        ),
        const SizedBox(height: 16),
        _LibrarySection(
          title: 'Favorites',
          count: _favoriteScriptIds.length,
          icon: Icons.star,
          emptyText: 'No favorites yet',
          emptySubtitle: 'Star scripts to quickly find them here',
          emptyIcon: Icons.star_outline,
          children: _favoriteScriptIds
              .map((id) => _FavoriteTile(
                    scriptId: id,
                    localScripts: _localScripts,
                    downloadHistory: _downloadHistory,
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        _LibrarySection(
          title: 'My Scripts',
          count: _localScripts.length,
          icon: Icons.code,
          emptyText: 'No scripts created',
          emptySubtitle: 'Create scripts to automate your workflow',
          emptyIcon: Icons.code_off_outlined,
          children: _localScripts
              .map((script) => _LocalScriptTile(script: script))
              .toList(),
        ),
        const SizedBox(height: 16),
        _LibrarySection(
          title: 'Recent Activity',
          count: recentActivity.length,
          icon: Icons.history,
          emptyText: 'No recent activity',
          emptySubtitle: 'Your script interactions will appear here',
          emptyIcon: Icons.history_outlined,
          children: recentActivity
              .map((activity) => _ActivityTile(activity: activity))
              .toList(),
        ),
      ],
    );
  }

  List<_ActivityItem> _getRecentActivity() {
    final activities = <_ActivityItem>[];

    for (final record in _downloadHistory.take(5)) {
      activities.add(_ActivityItem(
        title: record.title,
        subtitle: 'Downloaded from marketplace',
        icon: Icons.download,
        timestamp: record.downloadedAt,
      ));
    }

    for (final script in _localScripts) {
      if (script.lastRunAt != null) {
        activities.add(_ActivityItem(
          title: script.title,
          subtitle: 'Script executed',
          icon: Icons.play_arrow,
          timestamp: script.lastRunAt!,
        ));
      }
    }

    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities.take(10).toList();
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.title,
    required this.count,
    required this.icon,
    required this.emptyText,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.children,
  });

  final String title;
  final int count;
  final IconData icon;
  final String emptyText;
  final String emptySubtitle;
  final IconData emptyIcon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerText = count > 0 ? '$title ($count)' : title;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          headerText,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: children.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        emptyIcon,
                        size: 48,
                        color:
                            theme.colorScheme.onSurfaceVariant.withAlpha(128),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        emptyText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        emptySubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurfaceVariant.withAlpha(180),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ]
            : children,
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: const Icon(Icons.download_done, size: 20),
      ),
      title: Text(
        record.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('by ${record.authorName}'),
          Text(
            _formatDate(record.downloadedAt),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: record.version != null
          ? Chip(
              label: Text(
                record.version!,
                style: const TextStyle(fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
            )
          : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.scriptId,
    required this.localScripts,
    required this.downloadHistory,
  });

  final String scriptId;
  final List<ScriptRecord> localScripts;
  final List<DownloadRecord> downloadHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final localMatch = localScripts.where((s) => s.id == scriptId).firstOrNull;
    final downloadMatch = downloadHistory
        .where((r) => r.marketplaceScriptId == scriptId)
        .firstOrNull;

    final title = localMatch?.title ?? downloadMatch?.title ?? 'Unknown Script';
    final author = downloadMatch?.authorName ?? 'Local script';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          Icons.star,
          size: 20,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text('by $author'),
    );
  }
}

class _LocalScriptTile extends StatelessWidget {
  const _LocalScriptTile({required this.script});

  final ScriptRecord script;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.tertiaryContainer,
        child: Text(
          script.emoji ?? '📜',
          style: const TextStyle(fontSize: 20),
        ),
      ),
      title: Text(
        script.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Run count: ${script.runCount}',
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: script.isFromMarketplace
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Marketplace',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            )
          : null,
    );
  }
}

class _ActivityItem {
  _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.timestamp,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final DateTime timestamp;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final _ActivityItem activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          activity.icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        activity.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(activity.subtitle),
      trailing: Text(
        _formatDate(activity.timestamp),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
