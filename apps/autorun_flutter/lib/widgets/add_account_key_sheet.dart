import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../controllers/account_controller.dart';
import '../controllers/profile_controller.dart';
import '../widgets/key_parameters_dialog.dart';
import '../theme/app_design_system.dart';

/// Bottom sheet for adding a new public key to an account
///
/// ARCHITECTURE: Profile-Centric Model
/// - Only allows generating NEW keypairs for the account
/// - Does NOT allow importing/selecting existing identities (violates profile isolation)
/// - Each keypair belongs to exactly ONE profile
/// - Uses addKeypairToAccount() which generates keypair within profile context
class AddAccountKeySheet extends StatefulWidget {
  const AddAccountKeySheet({
    required this.account,
    required this.accountController,
    required this.profile,
    required this.profileController,
    required this.onKeyAdded,
    super.key,
  });

  final Account account;
  final AccountController accountController;
  final Profile profile;
  final ProfileController profileController;
  final Function(AccountPublicKey, Profile) onKeyAdded;

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

  /// Generate a new keypair and add it to the account using profile-centric approach
  Future<void> _generateAndAddNewKeypair() async {
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
      // Use profile-centric addKeypairToAccount which:
      // 1. Generates NEW keypair within the profile (via ProfileController)
      // 2. Registers the public key with the backend account
      final newKey = await widget.accountController.addKeypairToAccount(
        profile: widget.profile,
        algorithm: params.algorithm,
        keypairLabel: params.label,
      );

      // Get updated profile from ProfileController
      final updatedProfile = widget.profileController.findById(widget.profile.id);

      if (mounted && updatedProfile != null) {
        widget.onKeyAdded(newKey, updatedProfile);
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
