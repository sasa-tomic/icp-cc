import 'package:flutter/material.dart';

import '../controllers/identity_controller.dart';
import '../models/identity_record.dart';
import '../utils/principal.dart';

class IdentitySwitcherResult {
  const IdentitySwitcherResult({this.identityId, this.openIdentityManager = false});

  final String? identityId;
  final bool openIdentityManager;
}

Future<IdentitySwitcherResult?> showIdentitySwitcherSheet({
  required BuildContext context,
  required IdentityController controller,
}) {
  return showModalBottomSheet<IdentitySwitcherResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return IdentitySwitcherSheet(controller: controller);
    },
  );
}

class IdentitySwitcherSheet extends StatefulWidget {
  const IdentitySwitcherSheet({super.key, required this.controller});

  final IdentityController controller;

  @override
  State<IdentitySwitcherSheet> createState() => _IdentitySwitcherSheetState();
}

class _IdentitySwitcherSheetState extends State<IdentitySwitcherSheet> {
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.controller.activeIdentityId;
  }

  @override
  Widget build(BuildContext context) {
    final List<IdentityRecord> identities = widget.controller.identities;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 46,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Choose an identity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The active identity signs all uploads, marketplace actions, and canister calls.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: identities.isEmpty
                  ? _EmptyIdentitiesState(onManage: _handleManageTap)
                  : ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        _IdentityChoiceTile(
                          title: 'Incognito mode',
                          subtitle: 'Read-only mode, publishing disabled',
                          selected: _selectedId == null,
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _completeSelection(null),
                        ),
                        const Divider(height: 24),
                        ...identities.map((IdentityRecord record) {
                          final bool selected = _selectedId == record.id;
                          final String principal = PrincipalUtils.textFromRecord(record);
                          return _IdentityChoiceTile(
                            title: record.label.isEmpty ? 'Untitled identity' : record.label,
                            subtitle: '$principal (${record.algorithm.name.toUpperCase()})',
                            selected: selected,
                            icon: Icons.verified_user_outlined,
                            onTap: () => _completeSelection(record.id),
                          );
                        }),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handleManageTap,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Manage identities'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _completeSelection(_selectedId),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _completeSelection(String? identityId) {
    setState(() => _selectedId = identityId);
    Navigator.of(context).pop(
      IdentitySwitcherResult(identityId: identityId),
    );
  }

  void _handleManageTap() {
    Navigator.of(context).pop(const IdentitySwitcherResult(openIdentityManager: true));
  }
}

class _IdentityChoiceTile extends StatelessWidget {
  const _IdentityChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: selected ? 3 : 0,
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected
              ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
              : const SizedBox(width: 24, height: 24),
        ),
      ),
    );
  }
}

class _EmptyIdentitiesState extends StatelessWidget {
  const _EmptyIdentitiesState({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.info_outline, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          'No identities yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Create an identity to sign uploads and interact with ICP canisters.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onManage,
          child: const Text('Create identity'),
        ),
      ],
    );
  }
}
