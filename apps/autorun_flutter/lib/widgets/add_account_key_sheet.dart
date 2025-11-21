import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/identity_record.dart';
import '../controllers/account_controller.dart';
import '../widgets/identity_scope.dart';
import '../widgets/key_parameters_dialog.dart';
import '../theme/app_design_system.dart';

/// Bottom sheet for adding a new public key to an account
///
/// ARCHITECTURE: Profile-Centric Model
/// - Only allows generating NEW keypairs for the account
/// - Does NOT allow importing/selecting existing identities (violates profile isolation)
/// - Each keypair belongs to exactly ONE profile
///
/// FIXME: This widget should be refactored to accept a Profile parameter instead of
/// Account + signingIdentity. Then it can use AccountController.addKeypairToAccount()
/// which properly generates the keypair within the profile context.
/// Currently using deprecated addPublicKey() for backward compatibility.
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
  bool _isAdding = false;
  String? _errorMessage;

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
              'Add New Keypair',
              style: AppDesignSystem.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Generate a new keypair for this account',
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
              _buildGenerateNewKeypairCard(),
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

  Widget _buildGenerateNewKeypairCard() {
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
                      'Generate a new keypair and add its public key to this account',
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
            onPressed: _generateAndAddNewKeypair,
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

  /// Generate a new keypair and add it to the account
  ///
  /// FIXME: This should use AccountController.addKeypairToAccount() with a Profile
  /// parameter once the calling screen (AccountProfileScreen) is updated to provide
  /// the Profile context. Currently using deprecated addPublicKey() for compatibility.
  Future<void> _generateAndAddNewKeypair() async {
    final identityController = IdentityScope.of(context);

    // Show dialog to collect key parameters
    final KeyParameters? params = await showDialog<KeyParameters>(
      context: context,
      builder: (context) => const KeyParametersDialog(
        title: 'Add New Keypair',
      ),
    );

    if (params == null || !mounted) {
      return;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      // Generate new identity with provided parameters (don't set as active)
      final newIdentity = await identityController.createIdentity(
        algorithm: params.algorithm,
        label: params.label,
        mnemonic: params.seed,
        setAsActive: false,
      );

      // Add the new identity to the account
      // ignore: deprecated_member_use_from_same_package
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
}
