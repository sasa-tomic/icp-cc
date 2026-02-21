import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A widget that reveals action buttons on hover/focus for desktop platforms.
/// On mobile platforms, actions are always visible.
///
/// This improves discoverability of critical actions (Run, Edit, Delete, Publish)
/// while keeping the UI clean on desktop by revealing them only on hover.
class HoverRevealActions extends StatefulWidget {
  const HoverRevealActions({
    super.key,
    required this.actions,
    this.alwaysVisibleActions = const [],
  });

  /// Action buttons that reveal on hover (desktop) or are always visible (mobile)
  final List<Widget> actions;

  /// Action buttons that are always visible regardless of hover state
  /// (e.g., the star/favorite button)
  final List<Widget> alwaysVisibleActions;

  @override
  State<HoverRevealActions> createState() => HoverRevealActionsState();
}

class HoverRevealActionsState extends State<HoverRevealActions>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  static bool get _isDesktop {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHover(bool hovered) {
    if (hovered != _isHovered) {
      setState(() => _isHovered = hovered);
      if (hovered) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // On mobile, always show all actions
    if (!_isDesktop) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.alwaysVisibleActions,
          ...widget.actions,
        ],
      );
    }

    // On desktop, use hover reveal behavior
    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) => KeyEventResult.ignored,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Always visible actions (e.g., star/favorite)
            ...widget.alwaysVisibleActions,
            // Hover-reveal actions
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SizeTransition(
                  sizeFactor: _fadeAnimation,
                  axis: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.actions,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact icon button for script actions with consistent styling.
/// Used for Run, Edit, Delete, Publish actions in script lists.
class ScriptActionButton extends StatelessWidget {
  const ScriptActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.isDestructive = false,
    this.isLoading = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;
  final bool isDestructive;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = isDestructive
        ? colorScheme.error
        : (color ?? colorScheme.onSurfaceVariant);

    return IconButton(
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: effectiveColor,
              ),
            )
          : Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      color: effectiveColor,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 36,
        minHeight: 36,
      ),
      padding: EdgeInsets.zero,
    );
  }
}

/// Container widget that groups script action buttons together.
/// Provides consistent spacing and hover behavior.
class ScriptActionChips extends StatelessWidget {
  const ScriptActionChips({
    super.key,
    required this.actions,
    this.alwaysVisibleActions = const [],
  });

  final List<Widget> actions;
  final List<Widget> alwaysVisibleActions;

  @override
  Widget build(BuildContext context) {
    return HoverRevealActions(
      actions: actions,
      alwaysVisibleActions: alwaysVisibleActions,
    );
  }
}
