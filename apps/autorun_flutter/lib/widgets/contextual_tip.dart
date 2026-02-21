import 'package:flutter/material.dart';
import '../services/contextual_tip_service.dart';

/// A widget that shows an in-context tip when the user first encounters a feature.
///
/// The tip is shown only once per feature and can be dismissed by the user.
/// After dismissal, it won't show again unless the user resets onboarding.
class ContextualTip extends StatefulWidget {
  const ContextualTip({
    required this.feature,
    required this.child,
    this.onDismiss,
    super.key,
  });

  /// The feature this tip is for.
  final ContextualTipFeature feature;

  /// The child widget to wrap.
  final Widget child;

  /// Called when the tip is dismissed.
  final VoidCallback? onDismiss;

  @override
  State<ContextualTip> createState() => _ContextualTipState();
}

class _ContextualTipState extends State<ContextualTip> {
  final ContextualTipService _service = ContextualTipService();
  bool _shouldShow = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final shouldShow = await _service.shouldShowTip(widget.feature);
    if (mounted) {
      setState(() {
        _shouldShow = shouldShow;
        _isLoading = false;
      });
    }
  }

  Future<void> _dismiss() async {
    await _service.markTipSeen(widget.feature);
    widget.onDismiss?.call();
    if (mounted) {
      setState(() {
        _shouldShow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.child;
    }

    if (!_shouldShow) {
      return widget.child;
    }

    final content = _service.getTipContent(widget.feature);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tip banner
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: const EdgeInsets.all(16),
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _dismiss,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Dismiss',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        // Child content
        Flexible(child: widget.child),
      ],
    );
  }
}

/// A simpler inline tip that shows as an info banner.
class InlineContextualTip extends StatefulWidget {
  const InlineContextualTip({
    required this.feature,
    this.onDismiss,
    super.key,
  });

  final ContextualTipFeature feature;
  final VoidCallback? onDismiss;

  @override
  State<InlineContextualTip> createState() => _InlineContextualTipState();
}

class _InlineContextualTipState extends State<InlineContextualTip> {
  final ContextualTipService _service = ContextualTipService();
  bool _shouldShow = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final shouldShow = await _service.shouldShowTip(widget.feature);
    if (mounted) {
      setState(() {
        _shouldShow = shouldShow;
        _isLoading = false;
      });
    }
  }

  Future<void> _dismiss() async {
    await _service.markTipSeen(widget.feature);
    widget.onDismiss?.call();
    if (mounted) {
      setState(() {
        _shouldShow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_shouldShow) {
      return const SizedBox.shrink();
    }

    final content = _service.getTipContent(widget.feature);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              content.description,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _dismiss,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
