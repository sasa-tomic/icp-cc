import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../models/profile_keypair.dart';
import '../controllers/account_controller.dart';
import '../controllers/profile_controller.dart';
import '../theme/app_design_system.dart';
import '../widgets/account_key_details_sheet.dart';
import '../widgets/add_account_key_sheet.dart';
import '../utils/passkey_platform.dart';
import '../utils/tech_terms.dart';
import 'passkey_management_screen.dart';
import 'account_registration_wizard.dart';
import 'export_keys_dialog.dart';
import 'import_keys_dialog.dart';

/// Account profile screen showing account details and key management.
///
/// Displays:
/// - Account username
/// - Creation date
/// - List of public keys (active and disabled)
/// - Key management actions (add/remove)
///
/// UX-7: when [account] is null (the profile exists locally but has NOT been
/// registered on the marketplace backend), the screen renders a LOCAL key
/// surface — the profile's own keypairs (label / public key / principal,
/// "Use for signing", Import / Export) — which is local data that should be
/// reachable without backend registration. Backend-account specifics
/// (@username, profile editing, registered-key status) remain gated on a
/// registered [account], with an inline "Register an account" CTA.
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    this.account,
    required this.accountController,
    required this.profile,
    required this.profileController,
    super.key,
  });

  /// The backend marketplace account, if registered. Null for a local-only
  /// profile (see [AccountProfileScreen] doc comment / UX-7).
  final Account? account;
  final AccountController accountController;
  final Profile profile;
  final ProfileController profileController;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  // Assigned only when [widget.account] is non-null (registered mode). In
  // local-only mode it is never read, so leaving it unassigned is safe.
  late Account _account;
  late Profile _profile;
  bool _isRefreshing = false;

  /// True when the profile has no backend account — render the LOCAL key
  /// surface instead of the backend-account UI (UX-7).
  bool _isLocalOnly = false;

  // Edit controllers
  final _displayNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactTelegramController = TextEditingController();
  final _contactTwitterController = TextEditingController();
  final _contactDiscordController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isLocalOnly = widget.account == null;
    _profile = widget.profile;
    if (!_isLocalOnly) {
      _account = widget.account!;
      _initializeControllers();
      _refreshAccount();
    }
  }

  void _initializeControllers() {
    _displayNameController.text = _account.displayName;
    _contactEmailController.text = _account.contactEmail ?? '';
    _contactTelegramController.text = _account.contactTelegram ?? '';
    _contactTwitterController.text = _account.contactTwitter ?? '';
    _contactDiscordController.text = _account.contactDiscord ?? '';
    _websiteUrlController.text = _account.websiteUrl ?? '';
    _bioController.text = _account.bio ?? '';
  }

  /// Find matching local keypair for an AccountPublicKey
  /// Returns null if no matching keypair found
  ProfileKeypair? _findMatchingKeypair(AccountPublicKey accountKey) {
    // Both AccountPublicKey and ProfileKeypair use base64 format - simple string comparison
    for (final keypair in _profile.keypairs) {
      if (keypair.publicKey == accountKey.publicKey) {
        return keypair;
      }
    }
    return null;
  }

  /// Check if the given account key is the current signing key
  bool _isSigningKey(AccountPublicKey accountKey) {
    final matchingKeypair = _findMatchingKeypair(accountKey);
    if (matchingKeypair == null) return false;
    return _profile.primaryKeypair.id == matchingKeypair.id;
  }

  /// Check if the profile's signing keypair exists in the account's public keys
  /// Returns true if there's a match, false if there's a mismatch (data corruption)
  bool _profileKeypairExistsInAccount() {
    final signingKeypair = _profile.primaryKeypair;
    return _findAccountKeyForKeypair(signingKeypair) != null;
  }

  /// Find the AccountPublicKey that matches a ProfileKeypair
  AccountPublicKey? _findAccountKeyForKeypair(ProfileKeypair keypair) {
    // Both use base64 format - simple string comparison
    for (final accountKey in _account.publicKeys) {
      if (accountKey.publicKey == keypair.publicKey) {
        return accountKey;
      }
    }
    return null;
  }

  /// Find a profile keypair that IS registered with the account (for recovery)
  ProfileKeypair? _findRegisteredKeypair() {
    for (final keypair in _profile.keypairs) {
      if (_findAccountKeyForKeypair(keypair) != null) {
        return keypair;
      }
    }
    return null;
  }

  /// Set a key as the signing key for this profile
  Future<void> _setAsSigningKey(AccountPublicKey accountKey) async {
    final matchingKeypair = _findMatchingKeypair(accountKey);
    if (matchingKeypair == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot find matching local keypair')),
      );
      return;
    }

    try {
      await widget.profileController.setActiveKeypair(
        profileId: _profile.id,
        keypairId: matchingKeypair.id,
      );

      // Refresh the local profile reference
      final updatedProfile = widget.profileController.findById(_profile.id);
      if (updatedProfile != null && mounted) {
        setState(() {
          _profile = updatedProfile;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          AppDesignSystem.successSnackBar('Signing key updated'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set signing key: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _contactEmailController.dispose();
    _contactTelegramController.dispose();
    _contactTwitterController.dispose();
    _contactDiscordController.dispose();
    _websiteUrlController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _refreshAccount() async {
    setState(() => _isRefreshing = true);
    try {
      final refreshed =
          await widget.accountController.refreshAccount(_account.username);
      if (refreshed != null && mounted) {
        setState(() => _account = refreshed);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'My Identity',
          style: AppDesignSystem.heading3.copyWith(
            color: context.colors.onSurface,
          ),
        ),
        actions: [
          // Refresh fetches the live backend account — only meaningful when
          // registered. Local-only mode has no backend state to refresh.
          if (!_isLocalOnly)
            IconButton(
              icon: Icon(
                _isRefreshing ? Icons.hourglass_empty : Icons.refresh,
                color: AppDesignSystem.primaryLight,
              ),
              onPressed: _isRefreshing ? null : _refreshAccount,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _isLocalOnly ? _buildLocalOnlyBody() : _buildRegisteredBody(),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget? _buildFloatingActionButton() {
    // Local-only: add a NEW local keypair directly to the profile.
    if (_isLocalOnly) {
      if (!_profile.canAddKeypair) return null;
      return FloatingActionButton.extended(
        onPressed: _addLocalKeypair,
        backgroundColor: AppDesignSystem.primaryLight,
        icon: const Icon(Icons.add),
        label: const Text('Add Key'),
      );
    }
    // Registered: capped by the backend account's key limit.
    if (_account.isAtMaxKeys) return null;
    return FloatingActionButton.extended(
      onPressed: _showAddKeySheet,
      backgroundColor: AppDesignSystem.primaryLight,
      icon: const Icon(Icons.add),
      label: const Text('Add Key'),
    );
  }

  /// Registered-mode body: backend account header, editable profile, security
  /// (passkeys + backend public keys).
  Widget _buildRegisteredBody() {
    return RefreshIndicator(
      onRefresh: _refreshAccount,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show warning if profile's signing key is not in account
            if (!_profileKeypairExistsInAccount()) ...[
              _buildKeypairMismatchWarning(),
              const SizedBox(height: 16),
            ],
            _buildAccountHeader(),
            const SizedBox(height: 24),
            _buildProfileSection(),
            const SizedBox(height: 24),
            _buildSecuritySection(),
          ],
        ),
      ),
    );
  }

  /// Local-only body (UX-7): the profile's local identity + a register CTA +
  /// the profile's own keypairs. No backend calls.
  Widget _buildLocalOnlyBody() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLocalIdentityHeader(),
          const SizedBox(height: 16),
          _buildRegisterCtaCard(),
          const SizedBox(height: 24),
          _buildLocalKeysSection(),
        ],
      ),
    );
  }

  /// Identity header for a local-only profile: shows the local profile name and
  /// an honest "not registered" badge instead of an @username.
  Widget _buildLocalIdentityHeader() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppDesignSystem.primaryGradient,
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _profile.name,
              style: AppDesignSystem.heading2.copyWith(
                color: AppDesignSystem.primaryDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppDesignSystem.warningLight.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 14, color: AppDesignSystem.warningDark),
                  const SizedBox(width: 4),
                  Text(
                    'Local profile — not registered',
                    style: AppDesignSystem.caption.copyWith(
                      color: AppDesignSystem.warningDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Created ${_formatDate(_profile.createdAt)}',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Inline CTA explaining the value of registration, with a button that opens
  /// the registration wizard (same flow the profile menu uses).
  Widget _buildRegisterCtaCard() {
    return Card(
      elevation: 0,
      color: AppDesignSystem.primaryLight.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: AppDesignSystem.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.how_to_reg_rounded,
                    color: AppDesignSystem.primaryLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Register an account',
                    style: AppDesignSystem.bodyMedium.copyWith(
                      color: AppDesignSystem.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Get an @username, publish scripts to the marketplace, and sync '
              'your public keys across devices. Your local keys keep working '
              'either way.',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _registerAccount,
              icon: const Icon(Icons.how_to_reg_outlined, size: 18),
              label: const Text('Register an account'),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignSystem.primaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The profile's local keypairs — always visible, regardless of backend
  /// registration (UX-7). Each key shows its label, public key, IC principal,
  /// and "Use for signing". Import / Export are surfaced here too.
  Widget _buildLocalKeysSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'YOUR KEYS',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _profile.canAddKeypair
                        ? AppDesignSystem.accentLight.withValues(alpha: 0.2)
                        : AppDesignSystem.warningLight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_profile.keypairs.length}/10',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: _profile.canAddKeypair
                          ? AppDesignSystem.accentDark
                          : AppDesignSystem.warningDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _showImportKeysDialog,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Import Keys'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppDesignSystem.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showExportKeysDialog,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export Keys'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppDesignSystem.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final keypair in _profile.keypairs) ...[
              _buildLocalKeyCard(keypair),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalKeyCard(ProfileKeypair keypair) {
    final isSigningKey = _profile.primaryKeypair.id == keypair.id;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSigningKey
            ? context.colors.primaryContainer.withValues(alpha: 0.3)
            : context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSigningKey ? context.colors.primary : context.colors.outline,
          width: isSigningKey ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppDesignSystem.successLight,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Local key',
                style: AppDesignSystem.bodySmall.copyWith(
                  color: AppDesignSystem.successDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isSigningKey) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 12, color: context.colors.onPrimary),
                      const SizedBox(width: 4),
                      Text(
                        'SIGNING KEY',
                        style: AppDesignSystem.caption.copyWith(
                          color: context.colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (!isSigningKey)
                TextButton.icon(
                  onPressed: () => _useLocalKeyForSigning(keypair),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Use for signing'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            keypair.label,
            style: AppDesignSystem.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: TechTerm.keypair.fullExplanation,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Public Key',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color:
                      context.colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _shortenKey(keypair.publicKey),
                  style: AppDesignSystem.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () =>
                    _copyToClipboard(keypair.publicKey, 'Public key'),
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (keypair.principal != null) ...[
            const SizedBox(height: 12),
            Tooltip(
              message: TechTerm.principal.fullExplanation,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'IC Principal',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: context.colors.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    keypair.principal!,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () =>
                      _copyToClipboard(keypair.principal!, 'Principal'),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Created ${_formatDate(keypair.createdAt)}',
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact a base64 key/principal for display (mirrors
  /// [AccountPublicKey.displayKey]'s shape).
  String _shortenKey(String value) {
    if (value.length <= 12) return value;
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  /// Open the registration wizard (same flow the profile menu uses). On
  /// success, flip the screen into registered mode with the new account and
  /// persist the username on the profile.
  Future<void> _registerAccount() async {
    final createdAccount = await Navigator.of(context).push<Account>(
      MaterialPageRoute<Account>(
        builder: (context) => AccountRegistrationWizard(
          keypair: _profile.primaryKeypair,
          accountController: widget.accountController,
          initialDisplayName: _profile.name,
        ),
      ),
    );

    if (createdAccount != null && mounted) {
      await widget.profileController.updateProfileUsername(
        profileId: _profile.id,
        username: createdAccount.username,
      );
      setState(() {
        _isLocalOnly = false;
        _account = createdAccount;
      });
      _initializeControllers();
      _refreshAccount();
    }
  }

  /// Generate a NEW local keypair directly into the profile (no backend
  /// needed). Available in local-only mode (UX-7).
  Future<void> _addLocalKeypair() async {
    try {
      final updatedProfile = await widget.profileController.addKeypairToProfile(
        profileId: _profile.id,
        algorithm: _profile.primaryKeypair.algorithm,
      );
      if (mounted) {
        setState(() => _profile = updatedProfile);
        _showSuccessSnackbar('Key added successfully');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to add key: $e');
      }
    }
  }

  /// Set a local keypair as the profile's signing key (local operation).
  Future<void> _useLocalKeyForSigning(ProfileKeypair keypair) async {
    try {
      await widget.profileController.setActiveKeypair(
        profileId: _profile.id,
        keypairId: keypair.id,
      );
      final updatedProfile = widget.profileController.findById(_profile.id);
      if (updatedProfile != null && mounted) {
        setState(() => _profile = updatedProfile);
        ScaffoldMessenger.of(context).showSnackBar(
          AppDesignSystem.successSnackBar('Signing key updated'),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to set signing key: $e');
      }
    }
  }

  Widget _buildKeypairMismatchWarning() {
    final registeredKeypair = _findRegisteredKeypair();
    final canRecover = registeredKeypair != null;

    return Card(
      elevation: 0,
      color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppDesignSystem.errorLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppDesignSystem.errorDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Signing Key Not Registered',
                    style: AppDesignSystem.bodyMedium.copyWith(
                      color: AppDesignSystem.errorDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canRecover
                  ? 'Your current signing key is not registered with this account, but another key in your profile is. '
                      'Switch to that key to restore access, then optionally add your preferred key.'
                  : 'Your profile\'s signing key is not registered with this account. '
                      'You need to recover the original signing key or unlink this account.',
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.errorDark,
              ),
            ),
            const SizedBox(height: 12),
            if (canRecover)
              FilledButton.icon(
                onPressed: () => _switchToRegisteredKey(registeredKeypair),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Switch to Registered Key'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignSystem.errorDark,
                ),
              )
          ],
        ),
      ),
    );
  }

  Future<void> _switchToRegisteredKey(ProfileKeypair keypair) async {
    try {
      await widget.profileController.setActiveKeypair(
        profileId: _profile.id,
        keypairId: keypair.id,
      );

      // Refresh the local profile reference
      final updatedProfile = widget.profileController.findById(_profile.id);
      if (updatedProfile != null && mounted) {
        setState(() {
          _profile = updatedProfile;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          AppDesignSystem.successSnackBar('Switched to registered signing key'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch key: $e')),
        );
      }
    }
  }

  Widget _buildAccountHeader() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Account icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppDesignSystem.primaryGradient,
              ),
              child: const Icon(
                Icons.account_circle,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Display Name
            Text(
              _account.displayName,
              style: AppDesignSystem.heading2.copyWith(
                color: AppDesignSystem.primaryDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // Username
            Text(
              '@${_account.username}',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // Creation date
            Text(
              'Created ${_formatDate(_account.createdAt)}',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROFILE',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),

            // Primary fields always visible
            _buildEditField(
              controller: _displayNameController,
              label: 'Display Name *',
              icon: Icons.person,
            ),
            const SizedBox(height: 12),
            _buildEditField(
              controller: _bioController,
              label: 'Bio',
              icon: Icons.notes,
              maxLines: 3,
            ),

            // Collapsible contact info section
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text(
                'Contact Info',
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Email, social links, and website',
                style: AppDesignSystem.bodySmall.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              leading: Icon(
                Icons.contact_mail_outlined,
                color: AppDesignSystem.primaryLight,
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: [
                _buildEditField(
                  controller: _contactEmailController,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _contactTelegramController,
                  label: 'Telegram',
                  icon: Icons.send_outlined,
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _contactTwitterController,
                  label: 'Twitter/X',
                  icon: Icons.tag,
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _contactDiscordController,
                  label: 'Discord',
                  icon: Icons.forum_outlined,
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _websiteUrlController,
                  label: 'Website',
                  icon: Icons.language,
                  keyboardType: TextInputType.url,
                ),
              ],
            ),

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveProfile,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppDesignSystem.primaryLight,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_displayNameController.text.isEmpty) {
      _showErrorSnackbar('Display name is required');
      return;
    }

    setState(() => _isRefreshing = true);
    try {
      final updatedAccount = await widget.accountController.updateProfile(
        username: _account.username,
        signingKeypair: _profile.primaryKeypair,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        contactEmail: _contactEmailController.text.trim().isEmpty
            ? null
            : _contactEmailController.text.trim(),
        contactTelegram: _contactTelegramController.text.trim().isEmpty
            ? null
            : _contactTelegramController.text.trim(),
        contactTwitter: _contactTwitterController.text.trim().isEmpty
            ? null
            : _contactTwitterController.text.trim(),
        contactDiscord: _contactDiscordController.text.trim().isEmpty
            ? null
            : _contactDiscordController.text.trim(),
        websiteUrl: _websiteUrlController.text.trim().isEmpty
            ? null
            : _websiteUrlController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
      );

      if (mounted) {
        setState(() => _account = updatedAccount);
        _showSuccessSnackbar('Profile updated successfully');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to update profile: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Widget _buildSecuritySection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SECURITY',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildPasskeysRow(),
            const Divider(height: 24),
            _buildPublicKeysRow(),
            const Divider(height: 24),
            _buildBackupRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildPasskeysRow() {
    if (PasskeyPlatform.isLinuxDesktop) {
      return _buildLinuxPasskeyRow();
    }

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppDesignSystem.primaryLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.fingerprint,
          color: AppDesignSystem.primaryLight,
        ),
      ),
      title: Tooltip(
        message: TechTerm.passkey.fullExplanation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Passkeys'),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 14,
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
      subtitle: const Text('Biometric authentication for secure login'),
      trailing: OutlinedButton(
        onPressed: () => _navigateToPasskeyManagement(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppDesignSystem.primaryLight,
          side: BorderSide(color: AppDesignSystem.primaryLight),
        ),
        child: const Text('Manage'),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildLinuxPasskeyRow() {
    return ExpansionTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppDesignSystem.warningLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.fingerprint,
          color: AppDesignSystem.warningDark,
        ),
      ),
      title: Tooltip(
        message: TechTerm.passkey.fullExplanation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Passkeys'),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 14,
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
      subtitle: Text(
        'Requires browser on Linux',
        style: AppDesignSystem.bodySmall.copyWith(
          color: AppDesignSystem.warningDark,
        ),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 56, bottom: 8),
      children: [
        Text(
          "Passkeys aren't available on Linux desktop. "
          'Use the app on macOS, Windows, or Android to set up passkeys '
          '(browser support is deferred — see R-1).',
          style: AppDesignSystem.bodySmall.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPublicKeysRow() {
    final activeKeys = _account.activeKeys;
    final disabledKeys = _account.disabledKeys;

    return ExpansionTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppDesignSystem.accentLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.vpn_key,
          color: AppDesignSystem.accentDark,
        ),
      ),
      title: const Text('Public Keys'),
      subtitle: Text(
        'Cryptographic keys for signing transactions',
        style: AppDesignSystem.bodySmall.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _account.isAtMaxKeys
              ? AppDesignSystem.warningLight.withValues(alpha: 0.2)
              : AppDesignSystem.accentLight.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_account.publicKeys.length}/10',
          style: AppDesignSystem.bodySmall.copyWith(
            color: _account.isAtMaxKeys
                ? AppDesignSystem.warningDark
                : AppDesignSystem.accentDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _showImportKeysDialog,
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Import Keys'),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignSystem.primaryLight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            TextButton.icon(
              onPressed: _showExportKeysDialog,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export Keys'),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignSystem.primaryLight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (activeKeys.isNotEmpty)
          for (var key in activeKeys) ...[
            _buildKeyCard(key, isActive: true),
            const SizedBox(height: 12),
          ],
        if (disabledKeys.isNotEmpty) ...[
          const Divider(height: 16),
          Text(
            'DISABLED KEYS',
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          for (var key in disabledKeys) ...[
            _buildKeyCard(key, isActive: false),
            const SizedBox(height: 12),
          ],
        ],
        if (_account.publicKeys.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No keys found',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBackupRow() {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppDesignSystem.neutral100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.download,
          color: AppDesignSystem.neutral700,
        ),
      ),
      title: const Text('Backup'),
      subtitle: const Text('Export your keys for secure backup'),
      trailing: OutlinedButton.icon(
        onPressed: _showExportKeysDialog,
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Export'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppDesignSystem.neutral700,
          side: const BorderSide(color: AppDesignSystem.neutral400),
        ),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  void _navigateToPasskeyManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PasskeyManagementScreen(
          accountId: _account.id,
          username: _account.username,
        ),
      ),
    );
  }

  Widget _buildKeyCard(AccountPublicKey key, {required bool isActive}) {
    final isLastActive = isActive && _account.activeKeys.length == 1;
    final isSigningKey = _isSigningKey(key);
    final hasMatchingKeypair = _findMatchingKeypair(key) != null;

    return InkWell(
      onTap: () => _showKeyDetails(key),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSigningKey
              ? context.colors.primaryContainer.withValues(alpha: 0.3)
              : isActive
                  ? context.colors.surfaceContainerHighest
                  : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSigningKey
                ? context.colors.primary
                : isActive
                    ? AppDesignSystem.successLight.withValues(alpha: 0.3)
                    : context.colors.outline,
            width: isSigningKey ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppDesignSystem.successLight
                        : AppDesignSystem.errorLight,
                  ),
                ),
                const SizedBox(width: 8),

                // Status text
                Text(
                  isActive ? 'Active' : 'Disabled',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: isActive
                        ? AppDesignSystem.successDark
                        : AppDesignSystem.errorDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Signing key badge
                if (isSigningKey) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit,
                          size: 12,
                          color: context.colors.onPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'SIGNING KEY',
                          style: AppDesignSystem.caption.copyWith(
                            color: context.colors.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (isLastActive && !isSigningKey) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          AppDesignSystem.warningLight.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'LAST ACTIVE',
                      style: AppDesignSystem.caption.copyWith(
                        color: AppDesignSystem.warningDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                // Set as signing key button (only show for active keys that are not already signing key)
                if (isActive && !isSigningKey && hasMatchingKeypair)
                  TextButton.icon(
                    onPressed: () => _setAsSigningKey(key),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Use for signing'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                // Action buttons
                if (isActive && !isLastActive)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmRemoveKey(key),
                    tooltip: 'Remove key',
                    color: AppDesignSystem.errorLight,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              key.displayLabel,
              style: AppDesignSystem.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            Tooltip(
              message: TechTerm.keypair.fullExplanation,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Public Key',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color:
                        context.colors.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    key.displayKey,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () =>
                      _copyToClipboard(key.publicKey, 'Public key'),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            Tooltip(
              message: TechTerm.principal.fullExplanation,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'IC Principal',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color:
                        context.colors.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    key.displayPrincipal,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () =>
                      _copyToClipboard(key.icPrincipal, 'Principal'),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Timestamps
            Text(
              isActive
                  ? 'Added ${_formatDate(key.addedAt)}'
                  : 'Disabled ${_formatDate(key.disabledAt!)}',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyDetails(AccountPublicKey key) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AccountKeyDetailsSheet(
        accountKey: key,
        canRemove: key.isActive && _account.activeKeys.length > 1,
        onRemove: () {
          Navigator.pop(context);
          _confirmRemoveKey(key);
        },
      ),
    );
  }

  void _showAddKeySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddAccountKeySheet(
        account: _account,
        accountController: widget.accountController,
        profile: _profile,
        profileController: widget.profileController,
        onKeyAdded: (key, updatedProfile) {
          Navigator.pop(context);
          setState(() {
            _profile = updatedProfile;
          });
          _refreshAccount();
          _showSuccessSnackbar('Key added successfully');
        },
      ),
    );
  }

  Future<void> _confirmRemoveKey(AccountPublicKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Key?'),
        content: Text(
          'This will disable the key "${key.displayKey}". The key will no longer have access to this account.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignSystem.errorLight,
            ),
            child: const Text('Remove Key'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _removeKey(key);
    }
  }

  Future<void> _removeKey(AccountPublicKey key) async {
    try {
      await widget.accountController.removePublicKey(
        username: _account.username,
        keyId: key.id,
        signingKeypair: _profile.primaryKeypair,
      );

      if (mounted) {
        _refreshAccount();
        _showSuccessSnackbar('Key removed successfully');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnackbar('$label copied to clipboard');
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppDesignSystem.successLight,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppDesignSystem.errorLight,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  void _showExportKeysDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => ExportKeysDialog(
        profileId: _profile.id,
        profileController: widget.profileController,
      ),
    );
  }

  void _showImportKeysDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => ImportKeysDialog(
        profileController: widget.profileController,
      ),
    );
  }
}
