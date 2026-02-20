import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_design_system.dart';

/// Result from the quick profile creation dialog
class QuickProfileCreationResult {
  const QuickProfileCreationResult({
    this.profileName,
    this.skipped = false,
  });

  /// The entered profile name (null if skipped)
  final String? profileName;

  /// Whether the user skipped profile creation
  final bool skipped;

  /// Check if a profile name was provided
  bool get hasName => profileName != null && profileName!.isNotEmpty;
}

/// Minimal first-run dialog asking only "What's your name?"
///
/// This replaces the multi-step onboarding with a single action:
/// just enter a name to create a local-only profile.
/// Account registration is deferred until the user wants to publish.
class QuickProfileCreationDialog extends StatefulWidget {
  const QuickProfileCreationDialog({super.key});

  @override
  State<QuickProfileCreationDialog> createState() =>
      _QuickProfileCreationDialogState();
}

class _QuickProfileCreationDialogState
    extends State<QuickProfileCreationDialog> {
  final _nameController = TextEditingController();
  final bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty && !_isCreating;

  void _handleContinue() {
    if (!_canContinue) return;

    HapticFeedback.mediumImpact();
    final name = _nameController.text.trim();
    Navigator.of(context).pop(QuickProfileCreationResult(
      profileName: name,
      skipped: false,
    ));
  }

  void _handleSkip() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(const QuickProfileCreationResult(skipped: true));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppDesignSystem.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          AppDesignSystem.primaryLight.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              "What's your name?",
              style: AppDesignSystem.heading2.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Create a profile to save your preferences. '
              'You can register a marketplace account later.',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: AppDesignSystem.neutral600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Name input
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleContinue(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Your name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 20),

            // Continue button
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _isCreating
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : FilledButton(
                      onPressed: _canContinue ? _handleContinue : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppDesignSystem.primaryLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Skip option
            Center(
              child: TextButton(
                onPressed: _isCreating ? null : _handleSkip,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: _isCreating
                        ? AppDesignSystem.neutral400
                        : AppDesignSystem.neutral600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
