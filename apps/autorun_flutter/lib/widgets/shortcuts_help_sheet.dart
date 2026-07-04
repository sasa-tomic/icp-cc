import 'package:flutter/material.dart';

import '../theme/app_design_system.dart';
import 'keyboard_shortcuts.dart';

/// Opens the keyboard-shortcuts help overlay as a modal bottom sheet.
Future<void> showShortcutsHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppDesignSystem.radius24)),
    ),
    builder: (context) => const ShortcutsHelpSheet(),
  );
}

/// A grouped, scannable list of every desktop keyboard shortcut. The shortcut
/// keys and descriptions are read from [kShortcutSpecs] so this view can never
/// drift from the actual bindings.
class ShortcutsHelpSheet extends StatelessWidget {
  const ShortcutsHelpSheet({super.key});

  static const List<_ShortcutGroup> _groups = <_ShortcutGroup>[
    _ShortcutGroup('Navigation', ['tab1', 'tab2', 'tab3', 'back']),
    _ShortcutGroup('Scripts', ['new', 'search', 'refresh']),
    _ShortcutGroup('Dapps', ['dapp_refresh']),
    _ShortcutGroup('Account', ['account_save']),
    _ShortcutGroup('Help', ['help']),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDesignSystem.spacing20,
          AppDesignSystem.spacing4,
          AppDesignSystem.spacing20,
          AppDesignSystem.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Keyboard Shortcuts', style: theme.textTheme.titleLarge),
            if (DesktopShortcuts.isDesktop) ...[
              const SizedBox(height: AppDesignSystem.spacing2),
              Text(
                'Press ? anytime to reopen this list.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppDesignSystem.spacing16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final group in _groups) ...[
                    _GroupHeader(label: group.title),
                    const SizedBox(height: AppDesignSystem.spacing4),
                    for (final action in group.actions)
                      _ShortcutRow(action: action),
                    const SizedBox(height: AppDesignSystem.spacing12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action});
  final String action;

  @override
  Widget build(BuildContext context) {
    final spec = kShortcutSpecs[action]!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.spacing4),
      child: Row(
        children: [
          Expanded(
            child: Text(spec.description, style: theme.textTheme.bodyMedium),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _KeySet(token: spec.token),
              // Secondary binding (e.g. `/` search also responds to Ctrl/Cmd+F).
              if (spec.altToken != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.spacing4),
                  child: Text('or',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                _KeySet(token: spec.altToken!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders a `mod+X` / `Alt+1` style token as a row of `+`-separated key chips.
class _KeySet extends StatelessWidget {
  const _KeySet({required this.token});
  final String token;

  @override
  Widget build(BuildContext context) {
    final parts = DesktopShortcuts.formatShortcutToken(token).split('+');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.spacing2),
              child: Text('+',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          _KeyChip(label: parts[i]),
        ],
      ],
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing8,
        vertical: AppDesignSystem.spacing2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesignSystem.radius8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Always-visible affordance that opens the shortcuts help overlay. Placed next
/// to the profile avatar so the `?` shortcut is discoverable without a keyboard.
class ShortcutsHelpButton extends StatelessWidget {
  const ShortcutsHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ShortcutTooltip(
      label: 'Keyboard shortcuts',
      shortcut: '?',
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showShortcutsHelpSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(AppDesignSystem.spacing8),
            child: Icon(
              Icons.keyboard_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutGroup {
  const _ShortcutGroup(this.title, this.actions);
  final String title;
  final List<String> actions;
}
