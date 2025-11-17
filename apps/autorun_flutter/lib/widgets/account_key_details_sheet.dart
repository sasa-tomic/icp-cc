import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../theme/app_design_system.dart';

/// Bottom sheet showing full details of an account public key
class AccountKeyDetailsSheet extends StatelessWidget {
  const AccountKeyDetailsSheet({
    required this.accountKey,
    required this.canRemove,
    this.onRemove,
    super.key,
  });

  final AccountPublicKey accountKey;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppDesignSystem.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Public Key Details',
              style: AppDesignSystem.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Status
            _buildInfoSection(
              'Status',
              accountKey.isActive ? 'Active' : 'Disabled',
              Icons.circle,
              statusColor: accountKey.isActive
                  ? AppDesignSystem.successLight
                  : AppDesignSystem.errorLight,
            ),
            const Divider(height: 32),

            // Public Key
            _buildInfoSection(
              'Public Key',
              accountKey.publicKey,
              Icons.key,
              canCopy: true,
              onCopy: () => _copyToClipboard(
                context,
                accountKey.publicKey,
                'Public key',
              ),
            ),
            const Divider(height: 32),

            // IC Principal
            _buildInfoSection(
              'IC Principal',
              accountKey.icPrincipal,
              Icons.fingerprint,
              canCopy: true,
              onCopy: () => _copyToClipboard(
                context,
                accountKey.icPrincipal,
                'Principal',
              ),
            ),
            const Divider(height: 32),

            // Added timestamp
            _buildInfoSection(
              'Added',
              _formatDateTime(accountKey.addedAt),
              Icons.schedule,
            ),

            // Disabled info (if applicable)
            if (!accountKey.isActive) ...[
              const Divider(height: 32),
              _buildInfoSection(
                'Disabled',
                _formatDateTime(accountKey.disabledAt!),
                Icons.block,
              ),
            ],

            // Remove button (danger zone)
            if (canRemove && accountKey.isActive) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppDesignSystem.errorLight.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppDesignSystem.errorDark,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Danger Zone',
                          style: AppDesignSystem.bodySmall.copyWith(
                            color: AppDesignSystem.errorDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onRemove,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppDesignSystem.errorLight,
                        side: BorderSide(color: AppDesignSystem.errorLight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove This Key'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(
    String label,
    String value,
    IconData icon, {
    Color? statusColor,
    bool canCopy = false,
    VoidCallback? onCopy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: statusColor ?? AppDesignSystem.primaryLight,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.neutral600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: canCopy ? 'monospace' : null,
                ),
              ),
            ),
            if (canCopy && onCopy != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
                tooltip: 'Copy',
              ),
          ],
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
