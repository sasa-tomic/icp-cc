import 'package:flutter/material.dart';

import '../controllers/profile_controller.dart';
import '../models/profile_keypair.dart';
import '../utils/principal.dart';

class KeypairSessionBanner extends StatelessWidget {
  const KeypairSessionBanner({
    super.key,
    required this.controller,
    required this.onManageKeypairs,
  });

  final ProfileController controller;
  final VoidCallback onManageKeypairs;

  @override
  Widget build(BuildContext context) {
    final ProfileKeypair? active = controller.activeKeypair;
    if (active == null) {
      return _AnonymousKeypairCard(
        onManageKeypairs: onManageKeypairs,
      );
    }
    // With the new system, all keypairs have an account (draft or registered)
    return _ActiveKeypairCard(
      keypair: active,
      principal: PrincipalUtils.textFromRecord(active),
      isProfileComplete: true, // Always true now - all keypairs have accounts
      onManageKeypairs: onManageKeypairs,
    );
  }
}

class _AnonymousKeypairCard extends StatelessWidget {
  const _AnonymousKeypairCard({
    required this.onManageKeypairs,
  });

  final VoidCallback onManageKeypairs;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.visibility_off_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Incognito mode',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No keypair selected. Go to the Profiles tab to select an keypair for signing uploads, '
              'marketplace actions, and canister calls.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onManageKeypairs,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Go to Profiles tab'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveKeypairCard extends StatelessWidget {
  const _ActiveKeypairCard({
    required this.keypair,
    required this.principal,
    required this.isProfileComplete,
    required this.onManageKeypairs,
  });

  final ProfileKeypair keypair;
  final String principal;
  final bool isProfileComplete;
  final VoidCallback onManageKeypairs;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String profileStatus = isProfileComplete ? 'Complete' : 'Incomplete';
    final Color chipColor =
        isProfileComplete ? colors.secondaryContainer : colors.errorContainer;
    final Color chipTextColor = isProfileComplete
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: colors.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.verified_user, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        keypair.label.isEmpty
                            ? 'Untitled keypair'
                            : keypair.label,
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$principal (${keypair.algorithm.name.toUpperCase()})',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Chip(
                  avatar: Icon(
                    isProfileComplete
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: chipTextColor,
                  ),
                  label: Text('Profile $profileStatus',
                      style: TextStyle(color: chipTextColor)),
                  backgroundColor: chipColor,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onManageKeypairs,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Manage in Profiles tab'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
