import 'package:flutter/material.dart';

import '../models/identity_record.dart';
import '../utils/principal.dart';

const String identityRequirementMessage =
    'Identity is required for script signing';
const String identitySelectionErrorText =
    'Please select an identity to sign the script';

/// Dropdown field for selecting an author identity used to sign marketplace requests.
class IdentitySelectorField extends StatelessWidget {
  const IdentitySelectorField({
    super.key,
    required this.identities,
    required this.selectedIdentity,
    required this.onChanged,
    this.requirementMessage,
    this.emptyStateMessage =
        'No identities available. Create an author identity first.',
  });

  final List<IdentityRecord> identities;
  final IdentityRecord? selectedIdentity;
  final ValueChanged<IdentityRecord?> onChanged;
  final String? requirementMessage;
  final String emptyStateMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasIdentity = selectedIdentity != null;
    final bool hasIdentities = identities.isNotEmpty;
    final Color borderColor =
        hasIdentity ? theme.colorScheme.outline : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<IdentityRecord>(
              key: const Key('identity-selector-dropdown'),
              value: selectedIdentity,
              isExpanded: true,
              hint: Text(
                'Select an identity...',
                style: TextStyle(
                  color: hasIdentity ? null : theme.colorScheme.error,
                ),
              ),
              items: hasIdentities
                  ? identities.map((IdentityRecord identity) {
                      final String principal =
                          PrincipalUtils.textFromRecord(identity);
                      final String shortPrincipal = principal.length >= 5
                          ? principal.substring(0, 5)
                          : principal;

                      return DropdownMenuItem<IdentityRecord>(
                        value: identity,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    identity.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '$shortPrincipal... (${keyAlgorithmToString(identity.algorithm)})',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList()
                  : <DropdownMenuItem<IdentityRecord>>[],
              onChanged: hasIdentities ? onChanged : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!hasIdentities)
          Text(
            emptyStateMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (!hasIdentity && requirementMessage != null)
          Text(
            requirementMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}
