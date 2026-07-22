import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../controllers/account_controller.dart';
import '../controllers/profile_controller.dart';
import '../models/profile_keypair.dart';
import '../utils/friendly_error.dart';
import '../theme/app_design_system.dart';

/// Bottom sheet for adding a new public key to an account
///
/// ARCHITECTURE: Profile-Centric Model
/// - Only allows generating NEW keypairs for the account
/// - Does NOT allow importing/selecting existing keypairs (violates profile isolation)
/// - Each keypair belongs to exactly ONE profile
/// - Uses addKeypairToAccount() which generates keypair within profile context
///
/// UX: label + advanced options (algorithm + seed) are collected INLINE in the
/// sheet. The primary "Generate & Add" action is single-click for the common
/// case (Ed25519 + no seed + optional label). Power users open the
/// "Advanced" ExpansionTile to pick Secp256k1 or supply a custom seed.
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
  final _labelController = TextEditingController();
  KeyAlgorithm _selectedAlgorithm = KeyAlgorithm.ed25519;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppDesignSystem.sheetBorderRadius,
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
              'Generate a new keypair and add its public key to this account',
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

            if (!_isAdding) ...[
              _buildInlineForm(),
            ] else ...[
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

  Widget _buildInlineForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label (optional) — inline, visible from the start
        TextField(
          controller: _labelController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Label (optional)',
            hintText: 'e.g., Laptop Key, Mobile Key',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Advanced options (algorithm only — custom seed isn't yet wired
        // into addKeypairToAccount) — collapsed by default
        ExpansionTile(
          initiallyExpanded: _showAdvanced,
          onExpansionChanged: (expanded) =>
              setState(() => _showAdvanced = expanded),
          tilePadding: EdgeInsets.zero,
          title: const Text('Advanced'),
          subtitle: Text(
            'Algorithm (default: Ed25519)',
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral600,
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Key Algorithm',
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildAlgorithmChoice(KeyAlgorithm.ed25519, 'Ed25519',
                'Fast and secure (recommended)'),
            const SizedBox(height: 8),
            _buildAlgorithmChoice(KeyAlgorithm.secp256k1, 'Secp256k1',
                'Bitcoin/Ethereum compatible'),
          ],
        ),
        const SizedBox(height: 8),

        // Primary action
        FilledButton(
          onPressed: _generateAndAddNewKeypair,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: AppDesignSystem.primaryLight,
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
    );
  }

  Widget _buildAlgorithmChoice(
      KeyAlgorithm algorithm, String title, String description) {
    final isSelected = _selectedAlgorithm == algorithm;

    return InkWell(
      onTap: () => setState(() => _selectedAlgorithm = algorithm),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
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
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? AppDesignSystem.accentDark
                  : AppDesignSystem.neutral400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: AppDesignSystem.neutral600,
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

  /// Generate a new keypair and add it to the account using profile-centric
  /// approach. All parameters are collected inline (label + optional advanced).
  Future<void> _generateAndAddNewKeypair() async {
    final label = _labelController.text.trim();

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final newKey = await widget.accountController.addKeypairToAccount(
        profile: widget.profile,
        algorithm: _selectedAlgorithm,
        keypairLabel: label.isEmpty ? null : label,
      );

      final updatedProfile =
          widget.profileController.findById(widget.profile.id);

      if (mounted && updatedProfile != null) {
        widget.onKeyAdded(newKey, updatedProfile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(e);
          _isAdding = false;
        });
      }
    }
  }
}
