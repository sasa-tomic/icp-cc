import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_design_system.dart';
import '../theme/modern_components.dart';

/// Modern empty state widget with enhanced animations and design
class ModernEmptyState extends StatefulWidget {
  const ModernEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel,
    this.secondaryAction,
    this.secondaryActionLabel,
    this.animationDelay = Duration.zero,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  final VoidCallback? secondaryAction;
  final String? secondaryActionLabel;
  final Duration animationDelay;

  @override
  State<ModernEmptyState> createState() => _ModernEmptyStateState();
}

class _ModernEmptyStateState extends State<ModernEmptyState>
    with TickerProviderStateMixin {
  late AnimationController _iconAnimationController;
  late AnimationController _contentAnimationController;
  late AnimationController _actionAnimationController;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;
  late Animation<Offset> _contentSlideAnimation;
  late Animation<double> _contentFadeAnimation;
  late Animation<double> _actionFadeAnimation;
  late Animation<double> _actionScaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _iconAnimationController = AnimationController(
      duration: AppDesignSystem.durationSlow,
      vsync: this,
    );
    
    _contentAnimationController = AnimationController(
      duration: AppDesignSystem.durationNormal,
      vsync: this,
    );
    
    _actionAnimationController = AnimationController(
      duration: AppDesignSystem.durationNormal,
      vsync: this,
    );

    _iconScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: AppDesignSystem.curveBounce,
    ));

    _iconRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: AppDesignSystem.curveEaseOut,
    ));

    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: AppDesignSystem.curveEaseOut,
    ));

    _contentFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: AppDesignSystem.curveEaseOut,
    ));

    _actionFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _actionAnimationController,
      curve: AppDesignSystem.curveEaseOut,
    ));

    _actionScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _actionAnimationController,
      curve: AppDesignSystem.curveEaseOut,
    ));

    // Start animations with delay
    Future.delayed(widget.animationDelay, () {
      if (mounted) {
        _iconAnimationController.forward();
      }
    });
    
    Future.delayed(widget.animationDelay + const Duration(milliseconds: 200), () {
      if (mounted) {
        _contentAnimationController.forward();
      }
    });
    
    Future.delayed(widget.animationDelay + const Duration(milliseconds: 400), () {
      if (mounted) {
        _actionAnimationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _contentAnimationController.dispose();
    _actionAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.spacing32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon container
            AnimatedBuilder(
              animation: _iconAnimationController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _iconScaleAnimation.value,
                  child: Transform.rotate(
                    angle: _iconRotationAnimation.value * 0.1,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: AppDesignSystem.spacing32),
            
            // Animated content
            AnimatedBuilder(
              animation: _contentAnimationController,
              builder: (context, child) {
                return SlideTransition(
                  position: _contentSlideAnimation,
                  child: FadeTransition(
                    opacity: _contentFadeAnimation,
                    child: Column(
                      children: [
                        Text(
                          widget.title,
                          style: context.textStyles.heading3.copyWith(
                            color: context.colors.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        
                        const SizedBox(height: AppDesignSystem.spacing12),
                        
                        Text(
                          widget.subtitle,
                          style: context.textStyles.bodyLarge.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // Animated actions
            if (widget.action != null && widget.actionLabel != null) ...[
              const SizedBox(height: AppDesignSystem.spacing32),
              
              AnimatedBuilder(
                animation: _actionAnimationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _actionFadeAnimation,
                    child: ScaleTransition(
                      scale: _actionScaleAnimation,
                      child: Column(
                        children: [
                          ModernButton(
                            onPressed: widget.action,
                            variant: ModernButtonVariant.primary,
                            size: ModernButtonSize.large,
                            fullWidth: false,
                            icon: const Icon(Icons.add_rounded, color: Colors.white),
                            child: Text(widget.actionLabel!),
                          ),
                          
                          if (widget.secondaryAction != null && widget.secondaryActionLabel != null) ...[
                            const SizedBox(height: AppDesignSystem.spacing12),
                            ModernButton(
                              onPressed: widget.secondaryAction,
                              variant: ModernButtonVariant.ghost,
                              size: ModernButtonSize.medium,
                              fullWidth: false,
                              child: Text(widget.secondaryActionLabel!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            
            // Decorative elements
            const SizedBox(height: AppDesignSystem.spacing40),
            AnimatedBuilder(
              animation: _contentAnimationController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _contentFadeAnimation,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDot(context.colors.primary.withValues(alpha: 0.3)),
                      const SizedBox(width: AppDesignSystem.spacing8),
                      _buildDot(context.colors.primary.withValues(alpha: 0.5)),
                      const SizedBox(width: AppDesignSystem.spacing8),
                      _buildDot(context.colors.primary.withValues(alpha: 0.3)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(Color color) {
    return AnimatedContainer(
      duration: AppDesignSystem.durationNormal,
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Modern loading indicator with enhanced animations
class ModernLoadingIndicator extends StatefulWidget {
  const ModernLoadingIndicator({
    super.key,
    this.message = 'Loading...',
    this.size = ModernLoadingIndicatorSize.medium,
  });

  final String message;
  final ModernLoadingIndicatorSize size;

  @override
  State<ModernLoadingIndicator> createState() => _ModernLoadingIndicatorState();
}

class _ModernLoadingIndicatorState extends State<ModernLoadingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _rotationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_rotationController);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _rotationController.repeat();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _getIconSize();
    final fontSize = _getFontSize();
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_rotationController, _pulseController]),
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Transform.rotate(
                  angle: _rotationAnimation.value * 2 * 3.14159,
                  child: Container(
                    width: iconSize * 2,
                    height: iconSize * 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.colors.primary,
                          context.colors.secondary,
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: context.shadows.colored,
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: iconSize,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: AppDesignSystem.spacing24),
          
          Text(
            widget.message,
            style: context.textStyles.bodyLarge.copyWith(
              color: context.colors.onSurfaceVariant,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }

  double _getIconSize() {
    switch (widget.size) {
      case ModernLoadingIndicatorSize.small:
        return 16.0;
      case ModernLoadingIndicatorSize.medium:
        return 24.0;
      case ModernLoadingIndicatorSize.large:
        return 32.0;
    }
  }

  double _getFontSize() {
    switch (widget.size) {
      case ModernLoadingIndicatorSize.small:
        return 12.0;
      case ModernLoadingIndicatorSize.medium:
        return 14.0;
      case ModernLoadingIndicatorSize.large:
        return 16.0;
    }
  }
}

enum ModernLoadingIndicatorSize { small, medium, large }

/// Modern error display with retry functionality
class ModernErrorDisplay extends StatefulWidget {
  const ModernErrorDisplay({
    super.key,
    required this.error,
    required this.onRetry,
    this.icon = Icons.error_outline_rounded,
    this.title = 'Something went wrong',
  });

  final String error;
  final VoidCallback onRetry;
  final IconData icon;
  final String title;

  @override
  State<ModernErrorDisplay> createState() => _ModernErrorDisplayState();
}

class _ModernErrorDisplayState extends State<ModernErrorDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppDesignSystem.durationNormal,
      vsync: this,
    );

    _shakeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const ShakeCurve(),
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppDesignSystem.curveEaseOut,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.spacing32),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Transform.translate(
                offset: Offset(_shakeAnimation.value * 10, 0),
                child: ModernCard(
                  padding: const EdgeInsets.all(AppDesignSystem.spacing24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              context.colors.error.withValues(alpha: 0.1),
                              context.colors.error.withValues(alpha: 0.05),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.colors.error.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 32,
                          color: context.colors.error,
                        ),
                      ),
                      
                      const SizedBox(height: AppDesignSystem.spacing20),
                      
                      Text(
                        widget.title,
                        style: context.textStyles.heading4.copyWith(
                          color: context.colors.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: AppDesignSystem.spacing12),
                      
                      Text(
                        widget.error,
                        style: context.textStyles.bodyMedium.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: AppDesignSystem.spacing24),
                      
                      ModernButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          widget.onRetry();
                        },
                        variant: ModernButtonVariant.primary,
                        size: ModernButtonSize.medium,
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Custom shake curve for error animation
class ShakeCurve extends Curve {
  const ShakeCurve();

  @override
  double transform(double t) {
    if (t < 0.1) return 0.0;
    if (t < 0.2) return -0.1;
    if (t < 0.3) return 0.1;
    if (t < 0.4) return -0.05;
    if (t < 0.5) return 0.05;
    if (t < 0.6) return -0.02;
    if (t < 0.7) return 0.02;
    if (t < 0.8) return -0.01;
    if (t < 0.9) return 0.01;
    return 0.0;
  }
}