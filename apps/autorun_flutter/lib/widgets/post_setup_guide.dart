import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';

enum PostSetupAction {
  browseMarketplace,
  createScript,
  exploreCanisters,
}

class PostSetupGuide extends StatelessWidget {
  const PostSetupGuide({
    required this.onActionSelected,
    required this.onDismiss,
    this.showDontShowAgain = true,
    super.key,
  });

  final void Function(PostSetupAction) onActionSelected;
  final VoidCallback onDismiss;
  final bool showDontShowAgain;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppDesignSystem.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Getting Started',
                          style: AppDesignSystem.heading4.copyWith(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'What would you like to do next?',
                          style: AppDesignSystem.bodySmall.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _ActionTile(
                icon: Icons.storefront_outlined,
                title: 'Browse the Marketplace',
                subtitle: 'Explore scripts shared by the community',
                onTap: () =>
                    onActionSelected(PostSetupAction.browseMarketplace),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.code_rounded,
                title: 'Create Your First Script',
                subtitle: 'Start building your own automation',
                onTap: () => onActionSelected(PostSetupAction.createScript),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.dns_outlined,
                title: 'Explore Canisters',
                subtitle: 'Discover and interact with ICP services',
                onTap: () => onActionSelected(PostSetupAction.exploreCanisters),
              ),
              const SizedBox(height: 24),
              if (showDontShowAgain) ...[
                Divider(color: context.colors.outline.withValues(alpha: 0.2)),
                const SizedBox(height: 12),
              ],
              _buildButtonRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonRow(BuildContext context) {
    if (showDontShowAgain) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            label: const Text("Don't show again"),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.onSurfaceVariant,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Maybe Later'),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Maybe Later'),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppDesignSystem.primaryLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: AppDesignSystem.primaryLight,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppDesignSystem.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppDesignSystem.bodySmall.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
