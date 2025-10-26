import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_design_system.dart';

/// Modern, animated custom navigation bar with glassmorphism effect
class ModernNavigationBar extends StatefulWidget {
  const ModernNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ModernNavigationItem> items;

  @override
  State<ModernNavigationBar> createState() => _ModernNavigationBarState();
}

class _ModernNavigationBarState extends State<ModernNavigationBar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppDesignSystem.durationNormal,
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppDesignSystem.curveEaseOut,
    ));
    _animationController.forward();
  }

  @override
  void didUpdateWidget(ModernNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animationController.reset();
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppDesignSystem.spacing20),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing8,
        vertical: AppDesignSystem.spacing12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius24),
        boxShadow: [
          ...AppDesignSystem.shadowMedium,
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widget.items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isActive = widget.currentIndex == index;
          
          return _buildNavItem(
            item: item,
            isActive: isActive,
            index: index,
            animation: isActive ? _slideAnimation : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNavItem({
    required ModernNavigationItem item,
    required bool isActive,
    required int index,
    Animation<double>? animation,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap(index);
      },
      child: AnimatedContainer(
        duration: AppDesignSystem.durationNormal,
        curve: AppDesignSystem.curveEaseInOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.spacing16,
          vertical: AppDesignSystem.spacing8,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radius16),
          border: isActive
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AppDesignSystem.durationNormal,
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                key: ValueKey(isActive),
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(height: AppDesignSystem.spacing4),
            AnimatedDefaultTextStyle(
              duration: AppDesignSystem.durationNormal,
              curve: AppDesignSystem.curveEaseInOut,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model for navigation items
class ModernNavigationItem {
  const ModernNavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Modern floating action button with enhanced animations
class ModernFloatingActionButton extends StatefulWidget {
  const ModernFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.extended = false,
    this.heroTag,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final bool extended;
  final Object? heroTag;

  @override
  State<ModernFloatingActionButton> createState() =>
      _ModernFloatingActionButtonState();
}

class _ModernFloatingActionButtonState
    extends State<ModernFloatingActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppDesignSystem.durationNormal,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppDesignSystem.curveEaseOut,
    ));
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppDesignSystem.curveEaseInOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: RotationTransition(
        turns: _rotationAnimation,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppDesignSystem.primaryGradient,
            borderRadius: BorderRadius.circular(AppDesignSystem.radius16),
            boxShadow: AppDesignSystem.shadowColored,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(AppDesignSystem.radius16),
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 56,
                  minHeight: 56,
                  maxWidth: 200,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.extended ? AppDesignSystem.spacing20 : AppDesignSystem.spacing16,
                  vertical: AppDesignSystem.spacing12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.icon,
                    if (widget.extended) ...[
                      const SizedBox(width: AppDesignSystem.spacing8),
                      Flexible(
                        child: Text(
                          widget.label,
                          style: AppDesignSystem.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modern card with glassmorphism effect and animations
class ModernCard extends StatefulWidget {
  ModernCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderRadius,
    this.padding,
    this.margin,
    this.isSelected = false,
    this.animationDuration = AppDesignSystem.durationNormal,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final List<BoxShadow> shadow = AppDesignSystem.shadowMedium;
  final bool isSelected;
  final Duration animationDuration;
  final double elevation = 0;
  final bool animated = true;

  @override
  State<ModernCard> createState() => _ModernCardState();
}

class _ModernCardState extends State<ModernCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _animationController = AnimationController(
        duration: AppDesignSystem.durationNormal,
        vsync: this,
      );
      _scaleAnimation = Tween<double>(
        begin: 0.95,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: AppDesignSystem.curveEaseOut,
      ));
      _elevationAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: AppDesignSystem.curveEaseOut,
      ));
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    if (widget.animated) {
      _animationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: widget.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(AppDesignSystem.radius20),
        boxShadow: widget.shadow,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.all(16),
        child: widget.child,
      ),
    );

    if (!widget.animated) {
      return card;
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: AnimatedContainer(
            duration: AppDesignSystem.durationFast,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(AppDesignSystem.radius20),
              boxShadow: widget.shadow.map((shadow) {
                return BoxShadow(
                  color: shadow.color,
                  blurRadius: shadow.blurRadius * _elevationAnimation.value,
                  offset: shadow.offset,
                );
              }).toList(),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                borderRadius: widget.borderRadius ?? BorderRadius.circular(AppDesignSystem.radius20),
                child: card,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Modern chip with enhanced design
class ModernChip extends StatelessWidget {
  const ModernChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.onDeleted,
    this.selected = false,
    this.color,
    this.backgroundColor,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool selected;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDesignSystem.durationFast,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing12,
        vertical: AppDesignSystem.spacing8,
      ),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  color ?? Theme.of(context).colorScheme.primary,
                  (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.8),
                ],
              )
            : null,
        color: selected
            ? null
            : backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesignSystem.radius20),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: AppDesignSystem.spacing8),
          ],
          Text(
            label,
            style: AppDesignSystem.caption.copyWith(
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: AppDesignSystem.spacing8),
            GestureDetector(
              onTap: onDeleted,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: selected
                    ? Colors.white.withValues(alpha: 0.8)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Modern button with enhanced animations and effects
class ModernButton extends StatefulWidget {
  const ModernButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = ModernButtonVariant.primary,
    this.size = ModernButtonSize.medium,
    this.fullWidth = false,
    this.loading = false,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ModernButtonVariant variant;
  final ModernButtonSize size;
  final bool fullWidth;
  final bool loading;
  final Widget? icon;

  @override
  State<ModernButton> createState() => _ModernButtonState();
}

class _ModernButtonState extends State<ModernButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppDesignSystem.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppDesignSystem.curveEaseInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _animationController.reverse();
  }

  void _onTapCancel() {
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(context);
    final padding = _getPadding();
    final textStyle = _getTextStyle(context);

    return GestureDetector(
      onTapDown: widget.onPressed != null ? _onTapDown : null,
      onTapUp: widget.onPressed != null ? _onTapUp : null,
      onTapCancel: widget.onPressed != null ? _onTapCancel : null,
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppDesignSystem.durationFast,
              width: widget.fullWidth ? double.infinity : null,
              padding: padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.loading
                      ? [colors.background.withValues(alpha: 0.5), colors.background.withValues(alpha: 0.3)]
                      : [
                          colors.background,
                          colors.background.withValues(alpha: 0.8),
                        ],
                ),
                borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
                border: widget.variant == ModernButtonVariant.outline
                    ? Border.all(color: colors.background, width: 2)
                    : null,
                boxShadow: widget.variant == ModernButtonVariant.primary
                    ? [
                        BoxShadow(
                          color: colors.background.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: widget.loading
                    ? SizedBox(
                        width: textStyle.fontSize! * 1.2,
                        height: textStyle.fontSize! * 1.2,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.foreground),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            widget.icon!,
                            const SizedBox(width: AppDesignSystem.spacing8),
                          ],
                          DefaultTextStyle(
                            style: textStyle.copyWith(color: colors.foreground),
                            child: widget.child,
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  _ButtonColors _getColors(BuildContext context) {
    switch (widget.variant) {
      case ModernButtonVariant.primary:
        return _ButtonColors(
          background: Theme.of(context).colorScheme.primary,
          foreground: Colors.white,
        );
      case ModernButtonVariant.secondary:
        return _ButtonColors(
          background: Theme.of(context).colorScheme.secondary,
          foreground: Colors.white,
        );
      case ModernButtonVariant.outline:
        return _ButtonColors(
          background: Theme.of(context).colorScheme.primary,
          foreground: Theme.of(context).colorScheme.primary,
        );
      case ModernButtonVariant.ghost:
        return _ButtonColors(
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
          foreground: Theme.of(context).colorScheme.onSurface,
        );
    }
  }

  EdgeInsets _getPadding() {
    switch (widget.size) {
      case ModernButtonSize.small:
        return const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.spacing12,
          vertical: AppDesignSystem.spacing8,
        );
      case ModernButtonSize.medium:
        return const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.spacing20,
          vertical: AppDesignSystem.spacing12,
        );
      case ModernButtonSize.large:
        return const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.spacing24,
          vertical: AppDesignSystem.spacing16,
        );
    }
  }

  TextStyle _getTextStyle(BuildContext context) {
    switch (widget.size) {
      case ModernButtonSize.small:
        return AppDesignSystem.bodySmall.copyWith(fontWeight: FontWeight.w600);
      case ModernButtonSize.medium:
        return AppDesignSystem.bodySmall.copyWith(fontWeight: FontWeight.w600);
      case ModernButtonSize.large:
        return AppDesignSystem.bodyMedium.copyWith(fontWeight: FontWeight.w600);
    }
  }
}

enum ModernButtonVariant { primary, secondary, outline, ghost }
enum ModernButtonSize { small, medium, large }

class _ButtonColors {
  _ButtonColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}