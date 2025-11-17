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

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _refreshAccount();
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

            // Username
            Text(
              '@${_account.username}',
              style: AppDesignSystem.heading2.copyWith(
                color: AppDesignSystem.primaryDark,
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
