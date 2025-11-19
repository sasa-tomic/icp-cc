import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../models/identity_record.dart';
import '../controllers/account_controller.dart';
import '../theme/app_design_system.dart';
import '../widgets/account_key_details_sheet.dart';
import '../widgets/add_account_key_sheet.dart';

/// Account profile screen showing account details and key management
///
/// Displays:
/// - Account username
/// - Creation date
/// - List of public keys (active and disabled)
/// - Key management actions (add/remove)
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    required this.account,
    required this.accountController,
    required this.currentIdentity,
    super.key,
  });

  final Account account;
  final AccountController accountController;
  final IdentityRecord currentIdentity;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late Account _account;
  bool _isRefreshing = false;
  bool _isEditing = false;

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
    _account = widget.account;
    _initializeControllers();
    _refreshAccount();
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
      final refreshed = await widget.accountController.refreshAccount(_account.username);
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
          'Account Profile',
          style: AppDesignSystem.heading3.copyWith(
            color: context.colors.onSurface,
          ),
        ),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: _refreshAccount,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAccountHeader(),
              const SizedBox(height: 24),
              _buildProfileSection(),
              const SizedBox(height: 24),
              _buildKeysSection(),
            ],
          ),
        ),
      ),
      floatingActionButton: _account.isAtMaxKeys
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddKeySheet,
              backgroundColor: AppDesignSystem.primaryLight,
              icon: const Icon(Icons.add),
              label: const Text('Add Key'),
            ),
    );
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PROFILE',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isEditing ? _cancelEdit : _startEdit,
                  icon: Icon(
                    _isEditing ? Icons.close : Icons.edit,
                    size: 18,
                  ),
                  label: Text(_isEditing ? 'Cancel' : 'Edit'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!_isEditing) ...[
              // Display mode
              _buildProfileField(
                label: 'Display Name',
                value: _account.displayName,
                icon: Icons.person,
              ),
              _buildProfileField(
                label: 'Email',
                value: _account.contactEmail,
                icon: Icons.email_outlined,
              ),
              _buildProfileField(
                label: 'Telegram',
                value: _account.contactTelegram,
                icon: Icons.send_outlined,
              ),
              _buildProfileField(
                label: 'Twitter/X',
                value: _account.contactTwitter,
                icon: Icons.tag,
              ),
              _buildProfileField(
                label: 'Discord',
                value: _account.contactDiscord,
                icon: Icons.forum_outlined,
              ),
              _buildProfileField(
                label: 'Website',
                value: _account.websiteUrl,
                icon: Icons.language,
              ),
              _buildProfileField(
                label: 'Bio',
                value: _account.bio,
                icon: Icons.notes,
              ),
            ] else ...[
              // Edit mode
              _buildEditField(
                controller: _displayNameController,
                label: 'Display Name *',
                icon: Icons.person,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              _buildEditField(
                controller: _bioController,
                label: 'Bio',
                icon: Icons.notes,
                maxLines: 3,
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
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField({
    required String label,
    String? value,
    required IconData icon,
  }) {
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppDesignSystem.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
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

  void _startEdit() {
    setState(() => _isEditing = true);
  }

  void _cancelEdit() {
    _initializeControllers();
    setState(() => _isEditing = false);
  }

  Future<void> _saveProfile() async {
    if (_displayNameController.text.isEmpty) {
      _showErrorSnackbar('Display name is required');
      return;
    }

    // TODO: Implement API call to update profile
    // For now, just show a message that this is not yet implemented
    _showErrorSnackbar('Profile update API not yet implemented');

    // When implemented, this should:
    // 1. Call backend API to update account profile
    // 2. Refresh the account data
    // 3. Exit edit mode
    // 4. Show success message
  }

  Widget _buildKeysSection() {
    final activeKeys = _account.activeKeys;
    final disabledKeys = _account.disabledKeys;

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PUBLIC KEYS',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
              ],
            ),
            const SizedBox(height: 16),

            // Active keys
            if (activeKeys.isNotEmpty) ...[
              for (var key in activeKeys) ...[
                _buildKeyCard(key, isActive: true),
                const SizedBox(height: 12),
              ],
            ],

            // Disabled keys
            if (disabledKeys.isNotEmpty) ...[
              const Divider(height: 24),
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
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'No keys found',
                    style: AppDesignSystem.bodyMedium.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard(AccountPublicKey key, {required bool isActive}) {
    final isLastActive = isActive && _account.activeKeys.length == 1;

    return InkWell(
      onTap: () => _showKeyDetails(key),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? context.colors.surfaceContainerHighest
              : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppDesignSystem.successLight.withValues(alpha: 0.3)
                : context.colors.outline,
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

                if (isLastActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppDesignSystem.warningLight.withValues(alpha: 0.2),
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

            // Public key
            Text(
              'Public Key',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
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
                  onPressed: () => _copyToClipboard(key.publicKey, 'Public key'),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // IC Principal
            Text(
              'IC Principal',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
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
                  onPressed: () => _copyToClipboard(key.icPrincipal, 'Principal'),
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
        signingIdentity: widget.currentIdentity,
        onKeyAdded: (key) {
          Navigator.pop(context);
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
        signingIdentity: widget.currentIdentity,
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
}
