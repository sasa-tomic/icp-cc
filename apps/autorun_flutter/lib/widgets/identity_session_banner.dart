import 'package:flutter/material.dart';

import '../controllers/identity_controller.dart';
import '../models/identity_record.dart';
import '../utils/principal.dart';

class IdentitySessionBanner extends StatelessWidget {
  const IdentitySessionBanner({
    super.key,
    required this.controller,
    required this.onManageIdentities,
  });

  final IdentityController controller;
  final VoidCallback onManageIdentities;

  @override
  Widget build(BuildContext context) {
    final IdentityRecord? active = controller.activeIdentity;
    if (active == null) {
      return _AnonymousIdentityCard(
        onManageIdentities: onManageIdentities,
      );
    }
    final bool isComplete = controller.isProfileComplete(active);
    return _ActiveIdentityCard(
      identity: active,
      principal: PrincipalUtils.textFromRecord(active),
      isProfileComplete: isComplete,
      onManageIdentities: onManageIdentities,
    );
  }
}

class _AnonymousIdentityCard extends StatelessWidget {
  const _AnonymousIdentityCard({
    required this.onManageIdentities,
  });

  final VoidCallback onManageIdentities;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.visibility_off_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Incognito mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No identity selected. Go to the Identities tab to select an identity for signing uploads, '
              'marketplace actions, and canister calls.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onManageIdentities,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Go to Identities tab'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveIdentityCard extends StatelessWidget {
  const _ActiveIdentityCard({
    required this.identity,
    required this.principal,
    required this.isProfileComplete,
    required this.onManageIdentities,
  });

  final IdentityRecord identity;
  final String principal;
  final bool isProfileComplete;
  final VoidCallback onManageIdentities;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String profileStatus = isProfileComplete ? 'Complete' : 'Incomplete';
    final Color chipColor = isProfileComplete ? colors.secondaryContainer : colors.errorContainer;
    final Color chipTextColor =
        isProfileComplete ? colors.onSecondaryContainer : colors.onErrorContainer;

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
                        identity.label.isEmpty ? 'Untitled identity' : identity.label,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$principal (${identity.algorithm.name.toUpperCase()})',
                        style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
                    isProfileComplete ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    color: chipTextColor,
                  ),
                  label: Text('Profile $profileStatus', style: TextStyle(color: chipTextColor)),
                  backgroundColor: chipColor,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onManageIdentities,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Manage in Identities tab'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
