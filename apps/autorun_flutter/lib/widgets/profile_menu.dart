import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/profile_controller.dart';
import '../controllers/account_controller.dart';
import '../theme/app_design_system.dart';
import '../models/profile.dart';
import '../models/account.dart';
import '../services/passkey_service.dart';
import '../services/settings_service.dart';
import '../screens/account_profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/unified_setup_wizard.dart';
import '../screens/vault_password_setup_screen.dart';
import '../screens/vault_unlock_screen.dart';
import '../services/secure_storage_readiness.dart';
import '../utils/user_initials.dart';

/// Profile menu action types
enum ProfileMenuAction {
  editProfile,
  createAccount,
  settings,
  manageProfiles,
  vault,
}

/// Profile menu widget that can be shown as a bottom sheet or menu
class ProfileMenuWidget extends StatefulWidget {
  const ProfileMenuWidget({
    super.key,
    required this.profileController,
    required this.accountController,
    this.passkeyService,
    this.onNavigate,
    this.onThemeChanged,
  });

  final ProfileController profileController;
  final AccountController accountController;
  final PasskeyService? passkeyService;
  final VoidCallback? onNavigate;
  final VoidCallback? onThemeChanged;

  @override
  State<ProfileMenuWidget> createState() => _ProfileMenuWidgetState();
}

class _ProfileMenuWidgetState extends State<ProfileMenuWidget> {
  bool _initialized = false;
  Account? _activeAccount;

  /// True while probing /vault to decide setup-vs-unlock routing. Prevents
  /// double-taps from stacking two vault screens and gives a visible "Checking…"
  /// cue. The probe happens with the menu still open (we must not pop first —
  /// popping disposes this widget mid-await); see [_navigateToVault].
  bool _isProbingVault = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadActiveAccount();
    }
  }

  Future<void> _loadActiveAccount() async {
    final profile = widget.profileController.activeProfile;
    if (profile?.username != null) {
      try {
        final account =
            await widget.accountController.getAccountForProfile(profile!);
        if (mounted && account != null) {
          setState(() {
            _activeAccount = account;
          });
        }
      } catch (e) {
        debugPrint('Error loading account: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profileController.activeProfile;
    final hasAccount = profile?.username != null;
    final displayName = _activeAccount?.displayName ?? profile?.name ?? 'Guest';
    final username = profile?.username;
    final profileCount = widget.profileController.profiles.length;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle (pinned)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header + items scroll so an inline profile list stays fully
          // reachable when the user owns many profiles.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileHeader(
                      context, profile, displayName, username, hasAccount),
                  const Divider(),
                  _buildMenuItems(context, profile, hasAccount, profileCount),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, Profile? profile,
      String displayName, String? username, bool hasAccount) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _getInitials(displayName),
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Profile info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (username != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.alternate_email,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        username,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    hasAccount ? 'Account setup in progress' : 'No account',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItems(BuildContext context, Profile? profile,
      bool hasAccount, int profileCount) {
    return Column(
      children: [
        // 1. My Account - unified account management (combines account + passkeys).
        // Always rendered: on a first run (no active profile) the tap routes to
        // profile creation/selection instead of being a silent no-op.
        _buildMyAccountTile(profile, hasAccount),
        // 1b. Vault — the zero-knowledge credential store (A-4). Account-scoped:
        // the opaque blob is keyed by the backend account id, so the tile is only
        // reachable when the active profile has a registered account (hasAccount).
        // Setup-vs-unlock routing is decided by probing /vault ON TAP (never on
        // menu open), so opening the menu costs zero network calls.
        if (hasAccount)
          _MenuTile(
            icon: Icons.lock_outline,
            label: 'Vault',
            subtitle:
                _isProbingVault ? 'Checking…' : 'Encrypt your credentials',
            onTap: _isProbingVault
                ? null
                : () => _handleAction(ProfileMenuAction.vault),
          ),
        // 2. Profile switching. With more than one profile the list is inlined
        // directly into the menu (2-tap switch). With a single profile the list
        // would be noise, so we fall back to a single entry that opens the
        // full manage sheet (create / delete / rename).
        if (profileCount > 1)
          _buildInlineProfileSwitcher()
        else
          _MenuTile(
            icon: Icons.swap_horiz,
            label: 'Switch Profile',
            subtitle: 'Only you',
            onTap: () => _handleAction(ProfileMenuAction.manageProfiles),
          ),
        // 3. Settings
        _MenuTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          subtitle: 'Theme, help, and app info',
          onTap: () => _handleAction(ProfileMenuAction.settings),
        ),
      ],
    );
  }

  /// Inline profile list shown when more than one profile exists. Tapping a
  /// non-active profile switches immediately (2 taps total) and closes the
  /// menu; the active profile is marked and non-interactive. A trailing
  /// "Manage Profiles" entry opens the full sheet for create/delete/rename.
  Widget _buildInlineProfileSwitcher() {
    final theme = Theme.of(context);
    final profiles = widget.profileController.profiles;
    final activeId = widget.profileController.activeProfileId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            'Switch profile',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final profile in profiles)
          _ProfileSwitchRow(
            profile: profile,
            isActive: profile.id == activeId,
            onTap:
                profile.id == activeId ? null : () => _switchToProfile(profile),
          ),
        _MenuTile(
          icon: Icons.tune_outlined,
          label: 'Manage Profiles',
          subtitle: 'Create, rename, or delete',
          onTap: () => _handleAction(ProfileMenuAction.manageProfiles),
        ),
      ],
    );
  }

  /// Switches the active profile via the same controller path used by the
  /// manage sheet, then closes the menu and confirms the switch. Keypair /
  /// script scoping is therefore identical to the legacy 3-tap flow.
  Future<void> _switchToProfile(Profile profile) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    await widget.profileController.setActiveProfile(profile.id);
    if (!mounted) return;
    Navigator.of(context).pop(); // Close the menu
    messenger.showSnackBar(
      SnackBar(content: Text('${profile.name} is now active')),
    );
  }

  Widget _buildMyAccountTile(Profile? profile, bool hasAccount) {
    final IconData icon;
    final String subtitle;
    final ProfileMenuAction action;

    if (profile == null) {
      icon = Icons.person_add_outlined;
      subtitle = 'Create a profile to get started';
      action = ProfileMenuAction.createAccount;
    } else if (hasAccount) {
      icon = Icons.person;
      subtitle = '@${profile.username}';
      action = ProfileMenuAction.editProfile;
    } else {
      // UX-7: a local-only profile (no backend account) still owns local
      // keypairs that the user must be able to reach. Route to Account & Keys,
      // which renders the local key surface and an inline "Register" CTA —
      // do NOT jump straight into the registration wizard and hide the keys.
      icon = Icons.person_outline;
      subtitle = 'Local profile — view keys or register';
      action = ProfileMenuAction.editProfile;
    }

    return _MenuTile(
      icon: icon,
      label: 'My Account',
      subtitle: subtitle,
      onTap: () => _handleAction(action),
      highlight: profile == null || !hasAccount,
    );
  }

  String _getInitials(String name) => computeInitials(name);

  void _handleAction(ProfileMenuAction action) async {
    HapticFeedback.lightImpact();

    // Vault is special: it must probe /vault to decide setup-vs-unlock BEFORE
    // closing this menu. Closing first (the pattern every other action uses)
    // would dispose this widget mid-probe and silently abort the navigation.
    if (action == ProfileMenuAction.vault) {
      await _navigateToVault();
      return;
    }

    Navigator.of(context).pop(); // Close the menu first

    final profile = widget.profileController.activeProfile;

    switch (action) {
      case ProfileMenuAction.editProfile:
        // Routes for both registered (account != null) and local-only
        // (account == null, UX-7) profiles. The screen's local-only branch
        // handles the null-account case without any backend calls.
        if (profile != null) {
          await _navigateToAccountProfile(_activeAccount, profile);
        }
        break;
      case ProfileMenuAction.createAccount:
        // Only reachable on first-run (no active profile) now that
        // local-only profiles route to AccountProfileScreen via editProfile.
        if (widget.profileController.profiles.isEmpty) {
          await _showCreateProfileDialog();
        } else {
          await _showManageProfilesSheet();
        }
        break;
      case ProfileMenuAction.settings:
        await _navigateToSettings();
        break;
      case ProfileMenuAction.manageProfiles:
        await _showManageProfilesSheet();
        break;
      case ProfileMenuAction.vault:
        // Handled above before the menu-pop. Unreachable.
        break;
    }
  }

  Future<void> _navigateToAccountProfile(
      Account? account, Profile profile) async {
    widget.onNavigate?.call();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountProfileScreen(
          account: account,
          accountController: widget.accountController,
          profile: profile,
          profileController: widget.profileController,
        ),
      ),
    );
    if (mounted) {
      await _loadActiveAccount();
      setState(() {});
    }
  }

  /// Routes to the vault flow (A-4 zero-knowledge credential store).
  ///
  /// The vault is account-scoped: its opaque blob is keyed by the backend
  /// account id, so the active [Account] must be loaded. We probe `/vault`
  /// ONCE on tap (never on menu open) to choose first-time setup
  /// ([VaultPasswordSetupScreen]) vs unlock ([VaultUnlockScreen]); that probe
  /// is the only network call in this flow.
  ///
  /// The probe runs BEFORE closing the menu: closing first would dispose this
  /// widget mid-await and silently abort. On a probe failure we surface the
  /// error loudly (SnackBar) and abort — we never guess "setup" because a down
  /// server is NOT "no vault", and guessing setup could clobber an existing
  /// blob. Uses `widget.passkeyService` when injected (tests) else the
  /// [PasskeyService] singleton (production).
  Future<void> _navigateToVault() async {
    if (_isProbingVault) return; // ignore accidental double-taps
    final account = _activeAccount;
    if (account == null) {
      // Defensive: the tile is gated on hasAccount, so a backend account is
      // loading. If the user taps before the load resolves, say so honestly
      // instead of routing with a null id.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account is still loading — try again in a moment.'),
        ),
      );
      return;
    }
    // The signature-gated vault routes (W7-12) need the active keypair to sign
    // the request. Keypairs live in local secure storage (independent of the
    // vault blob), so this is available without first unlocking the vault.
    final keypair = widget.profileController.activeKeypair;
    if (keypair == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active keypair — cannot authenticate vault access.'),
        ),
      );
      return;
    }

    setState(() => _isProbingVault = true);
    final service = widget.passkeyService ?? PasskeyService();
    bool vaultExists;
    try {
      final vault = await service.getVault(keypair: keypair, accountId: account.id);
      vaultExists = vault != null;
    } on PasskeyException catch (e) {
      // LOUD: a failed probe must NOT silently fall through to setup/unlock.
      if (mounted) {
        setState(() => _isProbingVault = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check vault status: ${e.message}')),
        );
      }
      return;
    }

    if (!mounted) {
      // The menu was dismissed while probing (e.g. user tapped elsewhere) —
      // nothing to route onto.
      return;
    }
    setState(() => _isProbingVault = false);

    // Close the menu, then push the chosen vault screen onto the same (root)
    // navigator. Both calls are synchronous in this frame — the State stays
    // mounted through the push (disposal only happens after the menu's exit
    // animation, which we don't await). This is the same pop-then-push pattern
    // used by [_navigateToAccountProfile].
    widget.onNavigate?.call();
    Navigator.of(context).pop();
    final screen = vaultExists
        ? VaultUnlockScreen(accountId: account.id, keypair: keypair)
        : VaultPasswordSetupScreen(accountId: account.id, keypair: keypair);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  Future<void> _navigateToSettings() async {
    widget.onNavigate?.call();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          settingsService: SettingsService(),
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  /// Combined profile management sheet - shows switch + create options
  Future<void> _showManageProfilesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ManageProfilesSheet(
        profileController: widget.profileController,
        accountController: widget.accountController,
        onCreateProfile: () async {
          Navigator.of(context).pop();
          await _showCreateProfileDialog();
        },
      ),
    );
    if (mounted) {
      await _loadActiveAccount();
      setState(() {});
    }
  }

  Future<void> _showCreateProfileDialog() async {
    await Navigator.of(context).push<UnifiedSetupResult>(
      MaterialPageRoute<UnifiedSetupResult>(
        fullscreenDialog: true,
        builder: (_) => UnifiedSetupWizard(
          profileController: widget.profileController,
          accountController: widget.accountController,
          secureStorageReadiness: SecureStorageReadiness(),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }
}

/// Menu tile widget
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: highlight
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: highlight
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
          color: onTap == null
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
              : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: onTap == null
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: onTap != null
          ? Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : null,
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

/// Shared profile row used both by the inline menu switcher and the manage
/// profiles sheet. Active profile renders a gradient avatar + check; inactive
/// rows are tappable via [onTap] (null when active).
class _ProfileSwitchRow extends StatelessWidget {
  const _ProfileSwitchRow({
    required this.profile,
    required this.isActive,
    this.onTap,
    this.onRename,
    this.onDelete,
  });

  final Profile profile;
  final bool isActive;
  final VoidCallback? onTap;

  /// When non-null, a trailing "more" menu (Rename / Delete) is rendered.
  /// Used by the full Manage Profiles sheet. The inline quick-switcher omits
  /// these (it is for 2-tap switching only).
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rename = onRename;
    final trailing = rename != null
        ? PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: theme.colorScheme.onSurfaceVariant),
            tooltip: 'Profile options',
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  rename();
                case 'delete':
                  onDelete?.call();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          )
        : (isActive
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : null);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8),
                  ],
                )
              : null,
          color: isActive ? null : theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            computeInitials(profile.name),
            style: TextStyle(
              color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      title: Text(
        profile.name,
        style: isActive ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: profile.username != null ? Text('@${profile.username}') : null,
      trailing: trailing,
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

/// Combined profile management sheet with switch + create + rename + delete.
///
/// Subtitle promises "Create, rename, or delete" — this delivers all three.
/// Rename/delete use the existing [ProfileController.updateProfileName] /
/// [ProfileController.deleteProfile] (which were previously unreachable from
/// the UI).
class _ManageProfilesSheet extends StatefulWidget {
  const _ManageProfilesSheet({
    required this.profileController,
    required this.accountController,
    required this.onCreateProfile,
  });

  final ProfileController profileController;
  final AccountController accountController;
  final VoidCallback onCreateProfile;

  @override
  State<_ManageProfilesSheet> createState() => _ManageProfilesSheetState();
}

class _ManageProfilesSheetState extends State<_ManageProfilesSheet> {
  Future<void> _renameProfile(Profile profile) async {
    final controller =
        TextEditingController(text: profile.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Profile Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || !mounted) return;
    if (newName == profile.name) return;

    try {
      await widget.profileController.updateProfileName(
        profileId: profile.id,
        name: newName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename profile: $e')),
        );
      }
    }
  }

  Future<void> _deleteProfile(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text(
          'Delete "${profile.name}"? This permanently removes its keypairs '
          'from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.profileController.deleteProfile(profile.id);
      messenger.showSnackBar(
        SnackBar(content: Text('"${profile.name}" deleted')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.profileController;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profiles = controller.profiles;
        final activeId = controller.activeProfileId;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Manage Profiles',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isActive = profile.id == activeId;

                    return _ProfileSwitchRow(
                      profile: profile,
                      isActive: isActive,
                      onTap: isActive
                          ? null
                          : () async {
                              HapticFeedback.lightImpact();
                              final messenger = ScaffoldMessenger.of(context);
                              await controller.setActiveProfile(profile.id);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                SnackBar(
                                  content:
                                      Text('${profile.name} is now active'),
                                ),
                              );
                            },
                      onRename: () => _renameProfile(profile),
                      onDelete: () => _deleteProfile(profile),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Create New Profile',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Add another identity',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onCreateProfile();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

/// Profile avatar button for use in app bars
///
/// Shows subtle text indicator when [hasAccount] is false, indicating
/// that the user hasn't registered a cloud username yet.
/// Red badge removed to reduce notification anxiety.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({
    super.key,
    required this.onTap,
    this.displayName,
    this.size = 36,
    this.showLabel = true,
    this.hasAccount = true,
  });

  final VoidCallback onTap;
  final String? displayName;
  final double size;
  final bool showLabel;

  /// Whether the user has a registered account. When false, shows subtle text.
  final bool hasAccount;

  String _getInitials(String? name) => computeInitials(name ?? '');

  /// Clean, single-sentence a11y label for the chip. The visible avatar
  /// initials and "Profile" / "No account" texts are excluded from semantics
  /// (see [ExcludeSemantics] in [build]) so the spoken label is this sentence
  /// alone, instead of raw initials spliced mid-sentence (W7-19 / W7-10).
  String get _semanticsLabel {
    if (!hasAccount) {
      return 'Profile menu, no account registered. Tap to open.';
    }
    final name = displayName;
    if (name != null && name.trim().isNotEmpty) {
      return 'Profile: $name. Tap to open.';
    }
    return 'Profile menu. Tap to open.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          _getInitials(displayName),
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );

    if (!showLabel) {
      return Semantics(
        label: _semanticsLabel,
        button: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: ExcludeSemantics(child: avatar),
        ),
      );
    }

    return Semantics(
      label: _semanticsLabel,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.8),
              borderRadius: BorderRadius.all(AppDesignSystem.sheetRadius),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(width: 8),
                Text(
                  'Profile',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                // Subtle "No account" indicator instead of red badge
                if (!hasAccount) ...[
                  const SizedBox(width: 6),
                  Text(
                    'No account',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
