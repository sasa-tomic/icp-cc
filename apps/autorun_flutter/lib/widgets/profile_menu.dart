import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/profile_controller.dart';
import '../controllers/account_controller.dart';
import '../models/profile.dart';
import '../models/account.dart';
import '../services/passkey_service.dart';
import '../services/settings_service.dart';
import '../screens/account_registration_wizard.dart';
import '../screens/account_profile_screen.dart';
import '../screens/passkey_management_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/my_library_screen.dart';

/// Profile menu action types
enum ProfileMenuAction {
  viewProfile,
  editProfile,
  createAccount,
  passkeys,
  settings,
  manageProfiles,
  myLibrary,
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
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Profile header
          _buildProfileHeader(
              context, profile, displayName, username, hasAccount),
          const Divider(),
          // Menu items
          _buildMenuItems(context, profile, hasAccount, profileCount),
          const SizedBox(height: 16),
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
                style: const TextStyle(
                  color: Colors.white,
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
        // 1. My Account - unified account management (combines account + passkeys)
        if (profile != null)
          _MenuTile(
            icon: hasAccount ? Icons.person : Icons.person_outline,
            label: 'My Account',
            subtitle: hasAccount
                ? '@${profile.username}'
                : 'Register to publish scripts',
            onTap: () => _handleAction(hasAccount
                ? ProfileMenuAction.editProfile
                : ProfileMenuAction.createAccount),
            highlight: !hasAccount,
          ),
        // 2. Switch Profile - simple profile switching
        _MenuTile(
          icon: Icons.swap_horiz,
          label: 'Switch Profile',
          subtitle: profileCount > 1
              ? '$profileCount profiles available'
              : 'Only you',
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

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.substring(0, 1).toUpperCase();
  }

  void _handleAction(ProfileMenuAction action) async {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(); // Close the menu first

    final profile = widget.profileController.activeProfile;

    switch (action) {
      case ProfileMenuAction.editProfile:
        if (_activeAccount != null && profile != null) {
          await _navigateToAccountProfile(_activeAccount!, profile);
        }
        break;
      case ProfileMenuAction.createAccount:
        if (profile != null) {
          await _navigateToAccountRegistration(profile);
        }
        break;
      case ProfileMenuAction.passkeys:
        if (_activeAccount != null) {
          await _navigateToPasskeyManagement(_activeAccount!);
        }
        break;
      case ProfileMenuAction.viewProfile:
        break;
      case ProfileMenuAction.settings:
        await _navigateToSettings();
        break;
      case ProfileMenuAction.manageProfiles:
        await _showManageProfilesSheet();
        break;
      case ProfileMenuAction.myLibrary:
        await _navigateToMyLibrary();
        break;
    }
  }

  Future<void> _navigateToAccountProfile(
      Account account, Profile profile) async {
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

  Future<void> _navigateToAccountRegistration(Profile profile) async {
    widget.onNavigate?.call();
    final Account? createdAccount = await Navigator.push<Account>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountRegistrationWizard(
          keypair: profile.primaryKeypair,
          accountController: widget.accountController,
          initialDisplayName: profile.name,
        ),
      ),
    );

    if (createdAccount != null && mounted) {
      await widget.profileController.updateProfileUsername(
        profileId: profile.id,
        username: createdAccount.username,
      );
      setState(() {
        _activeAccount = createdAccount;
      });
    }
  }

  Future<void> _navigateToPasskeyManagement(Account account) async {
    widget.onNavigate?.call();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => PasskeyManagementScreen(
          accountId: account.id,
          username: account.username,
        ),
      ),
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

  Future<void> _navigateToMyLibrary() async {
    widget.onNavigate?.call();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => const MyLibraryScreen(),
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateProfileDialog(),
    );

    if (result != null && mounted) {
      try {
        await widget.profileController.createProfile(
          profileName: result['name'] ?? 'New Profile',
          algorithm: result['algorithm'] ?? 'ed25519',
          setAsActive: true,
        );
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create profile: $e')),
          );
        }
      }
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

/// Combined profile management sheet with switch + create options
class _ManageProfilesSheet extends StatelessWidget {
  const _ManageProfilesSheet({
    required this.profileController,
    required this.accountController,
    required this.onCreateProfile,
  });

  final ProfileController profileController;
  final AccountController accountController;
  final VoidCallback onCreateProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = profileController.profiles;
    final activeId = profileController.activeProfileId;

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
              'Switch Profile',
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

                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary
                                    .withValues(alpha: 0.8),
                              ],
                            )
                          : null,
                      color: isActive
                          ? null
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        profile.name.isNotEmpty
                            ? profile.name.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  title: Text(profile.name),
                  subtitle: profile.username != null
                      ? Text('@${profile.username}')
                      : null,
                  trailing: isActive
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap: isActive
                      ? null
                      : () async {
                          HapticFeedback.lightImpact();
                          await profileController.setActiveProfile(profile.id);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${profile.name} is now active'),
                              ),
                            );
                          }
                        },
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Create new profile option
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
              onCreateProfile();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Simple create profile dialog
class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog();

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _controller = TextEditingController(text: 'New Profile');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Profile'),
      content: TextField(
        controller: _controller,
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
          onPressed: () {
            Navigator.pop(context, {
              'name': _controller.text.trim(),
              'algorithm': 'ed25519',
            });
          },
          child: const Text('Create'),
        ),
      ],
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

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.substring(0, 1).toUpperCase();
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
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );

    if (!showLabel) {
      return Semantics(
        label: hasAccount
            ? 'Profile menu'
            : 'Profile menu - no account registered',
        button: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: avatar,
        ),
      );
    }

    return Semantics(
      label:
          hasAccount ? 'Profile menu' : 'Profile menu - no account registered',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
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
    );
  }
}
