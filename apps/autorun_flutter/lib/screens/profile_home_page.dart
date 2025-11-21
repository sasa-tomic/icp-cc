import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/profile_controller.dart';
import '../controllers/account_controller.dart';
import '../models/profile.dart';
import '../models/account.dart';
import '../theme/app_design_system.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_fab.dart';
import '../widgets/key_parameters_dialog.dart';
import '../widgets/profile_scope.dart';
import 'account_registration_wizard.dart';
import 'account_profile_screen.dart';

/// Profile home page showing all user profiles
///
/// Architecture: Profile-Centric Model
/// - Lists Profiles (not individual keypairs)
/// - Each profile shows: name, @username, keypair count
/// - Tap profile to make it active
/// - Create new profiles with initial keypair
class ProfileHomePage extends StatefulWidget {
  const ProfileHomePage({super.key});

  @override
  State<ProfileHomePage> createState() => _ProfileHomePageState();
}

class _ProfileHomePageState extends State<ProfileHomePage> {
  ProfileController? _profileController;
  AccountController? _accountController;
  bool _initialized = false;

  /// Track account loading state for each profile
  final Map<String, bool> _accountLoading = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _profileController = ProfileScope.of(context, listen: false);
      _profileController!.addListener(_onControllerChanged);
      _accountController = AccountController(profileController: _profileController);
      _accountController!.addListener(_onControllerChanged);
      unawaited(_profileController!.ensureLoaded());
      unawaited(_loadAccountsForProfiles());
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _profileController?.removeListener(_onControllerChanged);
    _accountController
      ?..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAccountsForProfiles() async {
    if (_profileController == null) return;
    await _profileController!.ensureLoaded();
    final profiles = _profileController!.profiles;

    for (final profile in profiles) {
      if (profile.username != null) {
        setState(() {
          _accountLoading[profile.id] = true;
        });

        try {
          await _accountController?.getAccountForProfile(profile);
        } catch (e) {
          debugPrint('Error loading account for profile ${profile.id}: $e');
        } finally {
          if (mounted) {
            setState(() {
              _accountLoading[profile.id] = false;
            });
          }
        }
      }
    }
  }

  Future<void> _showCreateProfileDialog() async {
    final KeyParameters? params = await showDialog<KeyParameters>(
      context: context,
      builder: (context) => const KeyParametersDialog(
        title: 'Create New Profile',
      ),
    );

    if (params == null || !mounted) {
      return;
    }

    final String profileName = params.label ?? 'Profile ${_profileController!.profiles.length + 1}';

    final Profile profile = await _profileController!.createProfile(
      profileName: profileName,
      algorithm: params.algorithm,
      mnemonic: params.seed,
      setAsActive: true,
    );

    if (!mounted) {
      return;
    }

    // Navigate to account registration
    await _navigateToAccountRegistration(profile);
  }

  Future<void> _navigateToAccountRegistration(Profile profile) async {
    final Account? createdAccount = await Navigator.push<Account>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountRegistrationWizard(
          identity: profile.primaryKeypair,
          accountController: _accountController!,
        ),
      ),
    );

    if (createdAccount != null && mounted) {
      // Update profile with username
      await _profileController!.updateProfileUsername(
        profileId: profile.id,
        username: createdAccount.username,
      );

      await _navigateToAccountProfile(createdAccount, profile);
    }
  }

  Future<void> _navigateToAccountProfile(Account account, Profile profile) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountProfileScreen(
          account: account,
          accountController: _accountController!,
          profile: profile,
          profileController: _profileController!,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profileController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Profile> profiles = _profileController!.profiles;
    final bool showLoading = _profileController!.isBusy && profiles.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _profileController!.isBusy
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _profileController!.refresh();
                    },
              tooltip: 'Refresh profiles',
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Builder(
            builder: (BuildContext context) {
              if (showLoading) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.account_circle_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Loading Profiles...',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ),
                );
              }
              if (profiles.isEmpty) {
                return EmptyState(
                  icon: Icons.account_circle_rounded,
                  title: 'No Profiles Yet',
                  subtitle: 'Create your first profile to start using the app',
                  action: _showCreateProfileDialog,
                  actionLabel: 'Create Profile',
                );
              }
              return RefreshIndicator(
                onRefresh: _profileController!.refresh,
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 16 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: profiles.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final Profile profile = profiles[index];
                    final bool isActive = profile.id == _profileController!.activeProfileId;
                    final bool isLoading = _accountLoading[profile.id] ?? false;

                    return _buildProfileCard(context, profile, isActive, isLoading);
                  },
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: AnimatedFab(
        heroTag: 'profiles_fab',
        onPressed: _profileController!.isBusy
            ? null
            : () {
                HapticFeedback.mediumImpact();
                _showCreateProfileDialog();
              },
        icon: const Icon(Icons.add_rounded),
        label: 'New Profile',
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, Profile profile, bool isActive, bool isLoading) {
    final String keypairCount = profile.keypairs.length == 1 ? '1 key' : '${profile.keypairs.length} keys';

    return Hero(
      tag: 'profile_${profile.id}',
      child: Card(
        elevation: isActive ? 8 : 4,
        shadowColor: isActive
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
            : Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isActive
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            if (!isActive) {
              final messenger = ScaffoldMessenger.of(context);
              await _profileController!.setActiveProfile(profile.id);
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('${profile.name} is now active'),
                  backgroundColor: AppDesignSystem.successLight,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isActive
                          ? [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                            ]
                          : [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.secondary,
                            ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: isActive ? 12 : 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          _getInitials(profile.name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Profile info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: -0.5,
                            ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 8),
                      if (profile.username != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.alternate_email,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              profile.username!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                                  : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              keypairCount,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: isActive
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 9,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Loading or menu
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => _showProfileMenu(context, profile, isActive),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '#';
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.substring(0, 1).toUpperCase();
  }

  Future<void> _showProfileMenu(BuildContext context, Profile profile, bool isActive) async {
    // TODO: Implement profile menu (rename, delete, manage keys, etc.)
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile menu coming soon')),
    );
  }
}
