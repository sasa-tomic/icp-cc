import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/identity_record.dart';
import '../controllers/account_controller.dart';
import '../controllers/identity_controller.dart';
import '../widgets/identity_scope.dart';
import '../theme/app_design_system.dart';
import '../utils/principal.dart';
import '../services/account_signature_service.dart';

/// Bottom sheet for adding a new public key to an account
///
/// Provides two options:
/// 1. Generate a new keypair and add it to the account
/// 2. Use an existing local identity
class AddAccountKeySheet extends StatefulWidget {
  const AddAccountKeySheet({
    required this.account,
    required this.accountController,
    required this.signingIdentity,
    required this.onKeyAdded,
    super.key,
  });

  final Account account;
  final AccountController accountController;
  final IdentityRecord signingIdentity;
  final Function(AccountPublicKey) onKeyAdded;

  @override
  State<AddAccountKeySheet> createState() => _AddAccountKeySheetState();
}

class _AddAccountKeySheetState extends State<AddAccountKeySheet> {
  IdentityRecord? _selectedIdentity;
  bool _isAdding = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final identityController = IdentityScope.of(context);

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
              'Add Public Key',
              style: AppDesignSystem.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an identity to add to this account',
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.neutral600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppDesignSystem.errorLight.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppDesignSystem.errorDark,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: AppDesignSystem.bodySmall.copyWith(
                          color: AppDesignSystem.errorDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Generate new keypair option
            if (!_isAdding) ...[
              _buildGenerateNewKeypairCard(identityController),
              const SizedBox(height: 24),

              // Divider with "OR" text
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: AppDesignSystem.bodySmall.copyWith(
                        color: AppDesignSystem.neutral500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Available identities list
            if (!_isAdding) ...[
              Text(
                'Choose from existing identities',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: AppDesignSystem.neutral700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ..._buildAvailableIdentities(identityController),
              const SizedBox(height: 24),
              // Add button
              FilledButton(
                onPressed: _selectedIdentity != null ? _addSelectedKey : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppDesignSystem.primaryLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add Selected Key',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              // Loading state
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Adding key...'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateNewKeypairCard(IdentityController identityController) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppDesignSystem.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppDesignSystem.primaryLight.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generate New Keypair',
                      style: AppDesignSystem.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create a new identity and add it to this account',
                      style: AppDesignSystem.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _generateAndAddNewKeypair(identityController),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.white,
              foregroundColor: AppDesignSystem.primaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Generate & Add',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAvailableIdentities(IdentityController identityController) {
    // Get identities that don't already have keys in this account
    final accountPublicKeys = widget.account.publicKeys
        .map((k) => k.publicKey)
        .toSet();

    final availableIdentities = identityController.identities.where((identity) {
      final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);
      return !accountPublicKeys.contains(publicKeyHex);
    }).toList();

    if (availableIdentities.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48,
                  color: AppDesignSystem.neutral400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No available identities',
                  style: AppDesignSystem.bodyMedium.copyWith(
                    color: AppDesignSystem.neutral600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'All your local identities are already added to this account.',
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: AppDesignSystem.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      for (final identity in availableIdentities) ...[
        _buildIdentityCard(identity),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _buildIdentityCard(IdentityRecord identity) {
    final principal = PrincipalUtils.textFromRecord(identity);
    final isSelected = _selectedIdentity?.id == identity.id;

    return InkWell(
      onTap: () => setState(() => _selectedIdentity = identity),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppDesignSystem.accentLight.withValues(alpha: 0.1)
              : AppDesignSystem.neutral50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppDesignSystem.accentLight
                : AppDesignSystem.neutral200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio button
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? AppDesignSystem.accentDark
                  : AppDesignSystem.neutral400,
            ),
            const SizedBox(width: 12),

            // Identity info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity.label,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _truncatePrincipal(principal),
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: AppDesignSystem.neutral600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _truncatePrincipal(String principal) {
    if (principal.length <= 16) return principal;
    return '${principal.substring(0, 10)}...${principal.substring(principal.length - 6)}';
  }

  // Method to generate new keypair and add it to account
  Future<void> _generateAndAddNewKeypair(IdentityController identityController) async {
    // Show dialog to input label
    final label = await _showLabelInputDialog();
    if (label == null && mounted) {
      // User cancelled
      return;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      // Generate new identity
      final newIdentity = await identityController.createIdentity(
        algorithm: KeyAlgorithm.ed25519,
        label: label?.trim().isEmpty ?? true ? null : label!.trim(),
      );

      // Add the new identity to the account
      final newKey = await widget.accountController.addPublicKey(
        username: widget.account.username,
        signingIdentity: widget.signingIdentity,
        newIdentity: newIdentity,
      );

      if (mounted) {
        widget.onKeyAdded(newKey);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isAdding = false;
        });
      }
    }
  }

  // Method to add selected identity as key
  Future<void> _addSelectedKey() async {
    if (_selectedIdentity == null) return;

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final newKey = await widget.accountController.addPublicKey(
        username: widget.account.username,
        signingIdentity: widget.signingIdentity,
        newIdentity: _selectedIdentity!,
      );

      if (mounted) {
        widget.onKeyAdded(newKey);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isAdding = false;
        });
      }
    }
  }

  // Show dialog to input label for new identity
  Future<String?> _showLabelInputDialog() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Keypair Label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a label for the new keypair (optional)',
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.neutral600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g., Laptop Key, Mobile Key',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, controller.text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignSystem.primaryLight,
            ),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }
}
