import 'package:flutter/material.dart';

import '../controllers/profile_controller.dart';
import '../models/profile.dart';
import '../utils/principal.dart';

class KeypairSwitcherResult {
  const KeypairSwitcherResult(
      {this.profileId, this.openKeypairManager = false});

  final String? profileId;
  final bool openKeypairManager;
}

Future<KeypairSwitcherResult?> showKeypairSwitcherSheet({
  required BuildContext context,
  required ProfileController controller,
}) {
  return showModalBottomSheet<KeypairSwitcherResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return KeypairSwitcherSheet(controller: controller);
    },
  );
}

class KeypairSwitcherSheet extends StatefulWidget {
  const KeypairSwitcherSheet({super.key, required this.controller});

  final ProfileController controller;

  @override
  State<KeypairSwitcherSheet> createState() => _KeypairSwitcherSheetState();
}

class _KeypairSwitcherSheetState extends State<KeypairSwitcherSheet> {
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.controller.activeProfileId;
  }

  @override
  Widget build(BuildContext context) {
    final List<Profile> profiles = widget.controller.profiles;
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
              'Choose a keypair',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The active keypair signs all uploads, marketplace actions, and canister calls.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  _KeypairChoiceTile(
                    title: 'Incognito mode',
                    subtitle: 'Read-only mode, publishing disabled',
                    selected: _selectedId == null,
                    icon: Icons.visibility_off_outlined,
                    onTap: () => _completeSelection(null),
                  ),
                  if (profiles.isNotEmpty) ...[
                    const Divider(height: 24),
                    ...profiles.map((Profile profile) {
                      final bool selected = _selectedId == profile.id;
                      final String principal =
                          PrincipalUtils.textFromRecord(profile.primaryKeypair);
                      final String keyCount = profile.keypairs.length == 1
                          ? '1 key'
                          : '${profile.keypairs.length} keys';
                      return _KeypairChoiceTile(
                        title: profile.name.isEmpty
                            ? 'Untitled profile'
                            : profile.name,
                        subtitle: '$principal ($keyCount)',
                        selected: selected,
                        icon: Icons.verified_user_outlined,
                        onTap: () => _completeSelection(profile.id),
                      );
                    }),
                  ] else ...[
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.info_outline,
                            size: 32,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No profiles yet',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Create a profile to sign uploads',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    label: const Text('Manage keypairs'),
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

  void _completeSelection(String? profileId) {
    setState(() => _selectedId = profileId);
    Navigator.of(context).pop(
      KeypairSwitcherResult(profileId: profileId),
    );
  }

  void _handleManageTap() {
    Navigator.of(context)
        .pop(const KeypairSwitcherResult(openKeypairManager: true));
  }
}

class _KeypairChoiceTile extends StatelessWidget {
  const _KeypairChoiceTile({
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
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.4)
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
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : const SizedBox(width: 24, height: 24),
        ),
      ),
    );
  }
}
