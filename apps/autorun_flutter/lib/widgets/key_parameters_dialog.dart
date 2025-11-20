import 'package:flutter/material.dart';
import '../models/identity_record.dart';
import '../theme/app_design_system.dart';

/// Parameters for creating a new keypair
class KeyParameters {
  final KeyAlgorithm algorithm;
  final String? seed;
  final String? label;

  const KeyParameters({
    required this.algorithm,
    this.seed,
    this.label,
  });
}

/// Dialog for collecting keypair creation parameters
///
/// Collects:
/// - Key algorithm (ed25519 or secp256k1)
/// - Optional seed phrase
/// - Optional label
class KeyParametersDialog extends StatefulWidget {
  const KeyParametersDialog({
    this.title = 'New Keypair',
    this.defaultAlgorithm = KeyAlgorithm.ed25519,
    super.key,
  });

  final String title;
  final KeyAlgorithm defaultAlgorithm;

  @override
  State<KeyParametersDialog> createState() => _KeyParametersDialogState();
}

class _KeyParametersDialogState extends State<KeyParametersDialog> {
  late KeyAlgorithm _selectedAlgorithm;
  final _seedController = TextEditingController();
  final _labelController = TextEditingController();
  bool _showSeedInput = false;

  @override
  void initState() {
    super.initState();
    _selectedAlgorithm = widget.defaultAlgorithm;
  }

  @override
  void dispose() {
    _seedController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Algorithm selection
            Text(
              'Key Algorithm',
              style: AppDesignSystem.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildAlgorithmChoice(KeyAlgorithm.ed25519, 'Ed25519', 'Fast and secure (recommended)'),
            const SizedBox(height: 8),
            _buildAlgorithmChoice(KeyAlgorithm.secp256k1, 'Secp256k1', 'Bitcoin/Ethereum compatible'),
            const SizedBox(height: 16),

            // Seed input toggle
            Row(
              children: [
                Checkbox(
                  value: _showSeedInput,
                  onChanged: (value) {
                    setState(() {
                      _showSeedInput = value ?? false;
                      if (!_showSeedInput) {
                        _seedController.clear();
                      }
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    'Use custom seed phrase',
                    style: AppDesignSystem.bodyMedium,
                  ),
                ),
              ],
            ),

            // Seed input field
            if (_showSeedInput) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _seedController,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter seed phrase (mnemonic)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  helperText: 'Leave empty to generate randomly',
                  helperMaxLines: 2,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Label input
            Text(
              'Label (optional)',
              style: AppDesignSystem.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _onGenerate,
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignSystem.primaryLight,
          ),
          child: const Text('Generate'),
        ),
      ],
    );
  }

  Widget _buildAlgorithmChoice(KeyAlgorithm algorithm, String title, String description) {
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

  void _onGenerate() {
    final seed = _seedController.text.trim();
    final label = _labelController.text.trim();

    final parameters = KeyParameters(
      algorithm: _selectedAlgorithm,
      seed: seed.isEmpty ? null : seed,
      label: label.isEmpty ? null : label,
    );

    Navigator.pop(context, parameters);
  }
}
