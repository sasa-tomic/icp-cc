import 'package:flutter/material.dart';
import 'modern_empty_state.dart';

// Re-export for backward compatibility
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return ModernEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      action: action,
      actionLabel: actionLabel,
    );
  }
}
