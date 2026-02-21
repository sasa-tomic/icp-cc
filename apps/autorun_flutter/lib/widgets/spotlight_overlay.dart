import 'package:flutter/material.dart';
import '../services/spotlight_service.dart';

class SpotlightOverlay extends StatelessWidget {
  final String title;
  final String description;
  final SpotlightPosition currentPosition;
  final int? stepNumber;
  final int? totalSteps;
  final bool isLastStep;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final VoidCallback? onDismiss;
  final Rect? targetRect;

  const SpotlightOverlay({
    required this.title,
    required this.description,
    required this.currentPosition,
    this.stepNumber,
    this.totalSteps,
    this.isLastStep = false,
    this.onNext,
    this.onBack,
    this.onDismiss,
    this.targetRect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          _buildDimmedBackground(context),
          if (targetRect != null) _buildSpotlightHole(context, targetRect!),
          _buildContentCard(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildDimmedBackground(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildSpotlightHole(BuildContext context, Rect rect) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _SpotlightHolePainter(
          targetRect: rect,
          borderRadius: 12,
        ),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context, ColorScheme colorScheme) {
    final screenSize = MediaQuery.of(context).size;
    Offset position;

    if (currentPosition == SpotlightPosition.center) {
      position = Offset(
        (screenSize.width - 320) / 2,
        (screenSize.height - 200) / 2,
      );
    } else if (targetRect != null) {
      position =
          _calculatePositionForTarget(targetRect!, screenSize, currentPosition);
    } else {
      position = _getDefaultPosition(screenSize, currentPosition);
    }

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: _SpotlightCard(
          title: title,
          description: description,
          stepNumber: stepNumber,
          totalSteps: totalSteps,
          isLastStep: isLastStep,
          onNext: onNext,
          onBack: onBack,
          onDismiss: onDismiss,
          arrowPosition: currentPosition == SpotlightPosition.center
              ? null
              : _getOppositePosition(currentPosition),
        ),
      ),
    );
  }

  Offset _calculatePositionForTarget(
      Rect target, Size screenSize, SpotlightPosition pos) {
    const cardWidth = 320.0;
    const cardHeight = 200.0;
    const padding = 16.0;
    const arrowHeight = 12.0;

    switch (pos) {
      case SpotlightPosition.bottom:
        return Offset(
          (target.left + target.width / 2 - cardWidth / 2)
              .clamp(0.0, screenSize.width - cardWidth),
          target.bottom + padding + arrowHeight,
        );
      case SpotlightPosition.top:
        return Offset(
          (target.left + target.width / 2 - cardWidth / 2)
              .clamp(0.0, screenSize.width - cardWidth),
          target.top - cardHeight - padding - arrowHeight,
        );
      case SpotlightPosition.left:
        return Offset(
          target.left - cardWidth - padding - arrowHeight,
          (target.top + target.height / 2 - cardHeight / 2)
              .clamp(0.0, screenSize.height - cardHeight),
        );
      case SpotlightPosition.right:
        return Offset(
          target.right + padding + arrowHeight,
          (target.top + target.height / 2 - cardHeight / 2)
              .clamp(0.0, screenSize.height - cardHeight),
        );
      case SpotlightPosition.center:
        return Offset(
          (screenSize.width - cardWidth) / 2,
          (screenSize.height - cardHeight) / 2,
        );
    }
  }

  Offset _getDefaultPosition(Size screenSize, SpotlightPosition pos) {
    const cardWidth = 320.0;
    const cardHeight = 200.0;

    switch (pos) {
      case SpotlightPosition.bottom:
        return Offset(
            (screenSize.width - cardWidth) / 2, screenSize.height * 0.3);
      case SpotlightPosition.top:
        return Offset(
            (screenSize.width - cardWidth) / 2, screenSize.height * 0.6);
      case SpotlightPosition.left:
        return Offset(
            screenSize.width * 0.55, (screenSize.height - cardHeight) / 2);
      case SpotlightPosition.right:
        return Offset(
            screenSize.width * 0.1, (screenSize.height - cardHeight) / 2);
      case SpotlightPosition.center:
        return Offset(
          (screenSize.width - cardWidth) / 2,
          (screenSize.height - cardHeight) / 2,
        );
    }
  }

  SpotlightPosition _getOppositePosition(SpotlightPosition pos) {
    switch (pos) {
      case SpotlightPosition.bottom:
        return SpotlightPosition.top;
      case SpotlightPosition.top:
        return SpotlightPosition.bottom;
      case SpotlightPosition.left:
        return SpotlightPosition.right;
      case SpotlightPosition.right:
        return SpotlightPosition.left;
      case SpotlightPosition.center:
        return SpotlightPosition.center;
    }
  }
}

class _SpotlightCard extends StatelessWidget {
  final String title;
  final String description;
  final int? stepNumber;
  final int? totalSteps;
  final bool isLastStep;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final VoidCallback? onDismiss;
  final SpotlightPosition? arrowPosition;

  const _SpotlightCard({
    required this.title,
    required this.description,
    this.stepNumber,
    this.totalSteps,
    this.isLastStep = false,
    this.onNext,
    this.onBack,
    this.onDismiss,
    this.arrowPosition,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(colorScheme),
          _buildStepIndicator(colorScheme),
          _buildDescription(colorScheme),
          _buildActions(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme colorScheme) {
    if (stepNumber == null || totalSteps == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$stepNumber of $totalSteps',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stepNumber! / totalSteps!,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: onDismiss,
            child: Text(
              'Skip',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Row(
            children: [
              if (onBack != null)
                TextButton(
                  onPressed: onBack,
                  child: Text(
                    'Back',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              if (onBack != null) const SizedBox(width: 8),
              FilledButton(
                onPressed: isLastStep ? onDismiss : onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                child: Text(isLastStep ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightHolePainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;

  _SpotlightHolePainter({
    required this.targetRect,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        targetRect.inflate(8),
        Radius.circular(borderRadius),
      ))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        targetRect.inflate(8),
        Radius.circular(borderRadius),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightHolePainter oldDelegate) {
    return targetRect != oldDelegate.targetRect;
  }
}

class SpotlightTour extends StatefulWidget {
  final Widget child;
  final SpotlightService service;
  final Map<String, GlobalKey> targetKeys;
  final VoidCallback? onComplete;
  final VoidCallback? onDismiss;

  const SpotlightTour({
    required this.child,
    required this.service,
    required this.targetKeys,
    this.onComplete,
    this.onDismiss,
    super.key,
  });

  @override
  State<SpotlightTour> createState() => _SpotlightTourState();
}

class _SpotlightTourState extends State<SpotlightTour> {
  bool _showingTour = false;
  int _currentStep = 0;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _checkAndStartTour();
  }

  Future<void> _checkAndStartTour() async {
    final shouldShow = await widget.service.shouldShowTour();
    if (shouldShow && mounted) {
      final step = await widget.service.currentStep();
      setState(() {
        _showingTour = true;
        _currentStep = step;
      });
      _updateTargetRect();
    }
  }

  void _updateTargetRect() {
    final stepInfo = widget.service.getStepInfo(_currentStep);
    final key = widget.targetKeys[stepInfo.targetKey];
    if (key?.currentContext != null) {
      final renderBox = key!.currentContext!.findRenderObject() as RenderBox;
      final position = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _targetRect = position & renderBox.size;
      });
    }
  }

  Future<void> _handleNext() async {
    if (_currentStep >= SpotlightService.totalSteps - 1) {
      await _handleComplete();
      return;
    }

    await widget.service.nextStep();
    setState(() {
      _currentStep++;
    });
    _updateTargetRect();
  }

  Future<void> _handleBack() async {
    if (_currentStep <= 0) return;

    await widget.service.previousStep();
    setState(() {
      _currentStep--;
    });
    _updateTargetRect();
  }

  Future<void> _handleComplete() async {
    await widget.service.completeTour();
    setState(() {
      _showingTour = false;
    });
    widget.onComplete?.call();
  }

  Future<void> _handleDismiss() async {
    await widget.service.dismissTour();
    setState(() {
      _showingTour = false;
    });
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showingTour) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    final stepInfo = widget.service.getStepInfo(_currentStep);
    final isLastStep = _currentStep >= SpotlightService.totalSteps - 1;

    return SpotlightOverlay(
      title: stepInfo.title,
      description: stepInfo.description,
      currentPosition: stepInfo.position,
      targetRect: _targetRect,
      stepNumber: _currentStep + 1,
      totalSteps: SpotlightService.totalSteps,
      isLastStep: isLastStep,
      onNext: _handleNext,
      onBack: _currentStep > 0 ? _handleBack : null,
      onDismiss: _handleDismiss,
    );
  }
}
