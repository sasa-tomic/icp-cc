import 'package:flutter/material.dart';

import '../services/canister_history_service.dart';
import '../theme/app_design_system.dart';

/// Recent calls list for displaying call history
class RecentCallsList extends StatefulWidget {
  const RecentCallsList({super.key, required this.onTapEntry});
  final void Function(String canisterId, String method, String arguments)
      onTapEntry;

  @override
  State<RecentCallsList> createState() => _RecentCallsListState();
}

class _RecentCallsListState extends State<RecentCallsList> {
  List<CanisterCallRecord> _callHistory = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await CanisterHistoryService().getHistory();
    if (mounted) {
      setState(() => _callHistory = history);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_callHistory.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.history,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No recent calls. Your call history will appear here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Spacer(),
            TextButton.icon(
              key: const Key('clearHistoryButton'),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
              onPressed: () async {
                if (!await _confirmClear(context)) return;
                await CanisterHistoryService().clearHistory();
                await _loadHistory();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          key: const Key('callHistoryList'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _callHistory.length > 10 ? 10 : _callHistory.length,
          itemBuilder: (context, index) {
            final record = _callHistory[index];
            final isSuccess = record.resultSummary == 'success';
            final isUpdate = record.callType == CallType.update;
            final isComposite = record.callType == CallType.compositeQuery;

            final icon = isUpdate
                ? Icons.sync_alt
                : (isComposite ? Icons.merge_type : Icons.search);
            // call-type category colour (query/update/composite), not a status — see above.
            final iconColor = isUpdate
                ? Colors.orange
                : (isComposite ? Colors.purple : theme.colorScheme.primary);

            final timeAgo = _formatTimeAgo(record.timestamp);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                key: Key(
                    'historyItem_${record.canisterId}_${record.methodName}'),
                leading: Icon(icon, color: iconColor, size: 20),
                title: Text(
                  record.methodName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.canisterId.length > 16
                          ? '${record.canisterId.substring(0, 8)}...${record.canisterId.substring(record.canisterId.length - 4)}'
                          : record.canisterId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          isSuccess ? Icons.check_circle : Icons.error,
                          size: 12,
                          color: isSuccess
                              ? AppDesignSystem.successColor
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSuccess ? 'Success' : record.resultSummary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isSuccess
                                ? AppDesignSystem.successColor
                                : theme.colorScheme.error,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: const Icon(Icons.replay, size: 18),
                onTap: () => widget.onTapEntry(
                  record.canisterId,
                  record.methodName,
                  record.arguments,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  /// Guards the destructive "Clear all call history" action behind a confirm
  /// dialog. Returns true iff the user explicitly confirmed.
  ///
  /// The Clear button wipes ALL persisted call history — a one-click data-loss
  /// hazard without this guard (UX-H5).
  Future<bool> _confirmClear(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('clearHistoryConfirmDialog'),
        title: const Text('Clear call history?'),
        content: const Text(
          'This permanently removes every recent call from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('clearHistoryCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('clearHistoryConfirmButton'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
