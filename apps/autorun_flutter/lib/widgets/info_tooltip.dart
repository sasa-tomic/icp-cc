import 'package:flutter/material.dart';
import '../utils/tech_terms.dart';

class InfoTooltip extends StatelessWidget {
  const InfoTooltip({
    required this.term,
    this.showIcon = true,
    this.iconSize = 14,
    this.textStyle,
    this.useFullExplanation = true,
    super.key,
  });

  final TechTerm term;
  final bool showIcon;
  final double iconSize;
  final TextStyle? textStyle;
  final bool useFullExplanation;

  @override
  Widget build(BuildContext context) {
    final message =
        useFullExplanation ? term.fullExplanation : term.shortExplanation;
    final theme = Theme.of(context);
    final effectiveTextStyle = textStyle ?? theme.textTheme.bodyMedium;

    return Tooltip(
      message: message,
      preferBelow: true,
      showDuration: const Duration(seconds: 5),
      waitDuration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              term.term,
              style: effectiveTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showIcon) ...[
            SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: iconSize,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}

class InfoTooltipText extends StatelessWidget {
  const InfoTooltipText({
    required this.text,
    required this.term,
    this.showIcon = true,
    this.iconSize = 14,
    this.textStyle,
    this.useFullExplanation = true,
    super.key,
  });

  final String text;
  final TechTerm term;
  final bool showIcon;
  final double iconSize;
  final TextStyle? textStyle;
  final bool useFullExplanation;

  @override
  Widget build(BuildContext context) {
    final message =
        useFullExplanation ? term.fullExplanation : term.shortExplanation;
    final theme = Theme.of(context);
    final effectiveTextStyle = textStyle ?? theme.textTheme.bodyMedium;

    return Tooltip(
      message: message,
      preferBelow: true,
      showDuration: const Duration(seconds: 5),
      waitDuration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              style: effectiveTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showIcon) ...[
            SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: iconSize,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}

class TermWithTooltip extends StatelessWidget {
  const TermWithTooltip({
    required this.term,
    this.style,
    this.iconSize = 14,
    super.key,
  });

  final TechTerm term;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ?? theme.textTheme.bodySmall;

    return Tooltip(
      message: term.fullExplanation,
      preferBelow: true,
      showDuration: const Duration(seconds: 5),
      waitDuration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline,
            size: iconSize,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          SizedBox(width: 4),
          Text(
            term.shortExplanation,
            style: effectiveStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class InlineTermTooltip extends StatelessWidget {
  const InlineTermTooltip({
    required this.term,
    this.style,
    this.showIcon = true,
    this.iconSize = 12,
    this.inline = true,
    super.key,
  });

  final TechTerm term;
  final TextStyle? style;
  final bool showIcon;
  final double iconSize;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ?? theme.textTheme.bodySmall;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          Icon(
            Icons.info_outline,
            size: iconSize,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          SizedBox(width: 2),
        ],
        Text(
          term.term,
          style: effectiveStyle?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Tooltip(
      message: term.fullExplanation,
      preferBelow: true,
      showDuration: const Duration(seconds: 5),
      waitDuration: const Duration(milliseconds: 300),
      child: inline ? content : Semantics(button: true, child: content),
    );
  }
}
