import 'package:flutter/material.dart';
import '../services/onboarding_progress_service.dart';

class GettingStartedCard extends StatefulWidget {
  const GettingStartedCard({
    required this.onItemTap,
    required this.onDismiss,
    required this.onSnooze,
    super.key,
  });

  final void Function(OnboardingItem item) onItemTap;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;

  @override
  State<GettingStartedCard> createState() => _GettingStartedCardState();
}

class _GettingStartedCardState extends State<GettingStartedCard> {
  final OnboardingProgressService _service = OnboardingProgressService();
  List<OnboardingItem> _incompleteItems = [];
  OnboardingProgress _progress =
      const OnboardingProgress(completed: 0, total: 5);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final items = await _service.getIncompleteItems();
    final progress = await _service.getCompletionProgress();
    if (mounted) {
      setState(() {
        _incompleteItems = items;
        _progress = progress;
        _isLoading = false;
      });
    }
  }

  Future<void> _markComplete(OnboardingItem item) async {
    await _service.markComplete(item);
    await _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_progress.isComplete || _incompleteItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.rocket_launch_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Getting Started',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_progress.completed} of ${_progress.total} completed',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (value) {
                    if (value == 'dismiss') {
                      widget.onDismiss();
                    } else if (value == 'snooze') {
                      widget.onSnooze();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'snooze',
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 20),
                          SizedBox(width: 12),
                          Text('Remind me later'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'dismiss',
                      child: Row(
                        children: [
                          Icon(Icons.close, size: 20),
                          SizedBox(width: 12),
                          Text("Don't show again"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress.percentage,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
                minHeight: 6,
              ),
            ),
          ),
          ..._incompleteItems.take(4).map((item) => _ChecklistItem(
                item: item,
                isCompleted: false,
                onTap: () {
                  widget.onItemTap(item);
                  _markComplete(item);
                },
              )),
          if (_incompleteItems.length > 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '+${_incompleteItems.length - 4} more items',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.item,
    required this.isCompleted,
    required this.onTap,
  });

  final OnboardingItem item;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCompleted
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: isCompleted
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Icon(
                item.icon,
                size: 18,
                color: isCompleted
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isCompleted
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.onSurface,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
