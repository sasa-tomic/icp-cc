import 'package:flutter/material.dart';
import '../services/download_history_service.dart';
import '../controllers/script_controller.dart';
import '../services/script_repository.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/empty_state.dart';

class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({super.key});

  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  final DownloadHistoryService _downloadHistoryService = DownloadHistoryService();
  late final ScriptController _scriptController;
  
  List<DownloadRecord> _downloadHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scriptController = ScriptController(ScriptRepository.instance)..addListener(_onChanged);
    _loadDownloadHistory();
  }

  @override
  void dispose() {
    _scriptController
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadDownloadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final history = await _downloadHistoryService.getDownloadHistory();
      setState(() {
        _downloadHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromHistory(DownloadRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove from library'),
          content: Text('Remove "${record.title}" from your download library? This will not delete the local script.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _downloadHistoryService.removeFromHistory(record.marketplaceScriptId);
        await _loadDownloadHistory();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from library')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove: $e')),
          );
        }
      }
    }
  }

  Future<void> _clearHistory() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear Library'),
          content: const Text('Clear your entire download library? This will not delete any local scripts.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _downloadHistoryService.clearHistory();
        await _loadDownloadHistory();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library cleared')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Library'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          if (_downloadHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearHistory,
              tooltip: 'Clear library',
            ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const LoadingIndicator(message: 'Loading download history...');
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load library',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadDownloadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_downloadHistory.isEmpty) {
      return const EmptyState(
        icon: Icons.download_for_offline,
        title: 'No downloads yet',
        subtitle: 'Scripts you download from the marketplace will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDownloadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _downloadHistory.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final record = _downloadHistory[index];
          return _DownloadHistoryTile(
            record: record,
            scriptController: _scriptController,
            onRemove: () => _removeFromHistory(record),
          );
        },
      ),
    );
  }
}

class _DownloadHistoryTile extends StatelessWidget {
  final DownloadRecord record;
  final ScriptController scriptController;
  final VoidCallback onRemove;

  const _DownloadHistoryTile({
    required this.record,
    required this.scriptController,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Text('📦'),
      ),
      title: Text(
        record.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('by ${record.authorName}'),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                _formatDate(record.downloadedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              if (record.version != null) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.tag,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  record.version!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'remove':
              onRemove();
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline),
                SizedBox(width: 8),
                Text('Remove from library'),
              ],
            ),
          ),
        ],
      ),
      onTap: () async {
        // Navigate to the local script
        try {
          // Find the script by ID from the controller's scripts list
          await scriptController.ensureLoaded();
          final script = scriptController.scripts.where((s) => s.id == record.localScriptId).firstOrNull;

          if (script == null) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Script not found. It may have been deleted.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }

          // Navigate to scripts screen and pass the script ID to highlight
          if (context.mounted) {
            Navigator.pop(context); // Go back from history screen
            // The scripts screen should handle highlighting the script
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      },
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