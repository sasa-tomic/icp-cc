import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../models/identity_record.dart';
import '../controllers/account_controller.dart';
import '../services/account_signature_service.dart';
import '../theme/app_design_system.dart';
import '../utils/principal.dart';

/// Account registration wizard with multi-step flow
///
/// Guides users through:
/// 1. Username selection with real-time validation
/// 2. Review account details
/// 3. Processing (signature generation + API call)
/// 4. Success celebration
class AccountRegistrationWizard extends StatefulWidget {
  const AccountRegistrationWizard({
    required this.identity,
    required this.accountController,
    super.key,
  });

  final IdentityRecord identity;
  final AccountController accountController;

  @override
  State<AccountRegistrationWizard> createState() => _AccountRegistrationWizardState();
}

class _AccountRegistrationWizardState extends State<AccountRegistrationWizard>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactTelegramController = TextEditingController();
  final _contactTwitterController = TextEditingController();
  final _contactDiscordController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _bioController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Validation state
  bool _isValidating = false;
  UsernameValidation? _validation;
  Timer? _debounceTimer;

  // Processing state
  String _processingStatus = '';
  Account? _createdAccount;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _contactEmailController.dispose();
    _contactTelegramController.dispose();
    _contactTwitterController.dispose();
    _contactDiscordController.dispose();
    _websiteUrlController.dispose();
    _bioController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _currentStep == 3 ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Create Account',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case 0:
        return _buildUsernameStep();
      case 1:
        return _buildReviewStep();
      case 2:
        return _buildProcessingStep();
      case 3:
        return _buildSuccessStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // Step 1: Username Input
  Widget _buildUsernameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress indicator
            _buildProgressIndicator(1, 3),
            const SizedBox(height: 32),

            // Illustration
            Container(
              height: 120,
              alignment: Alignment.center,
              child: Icon(
                Icons.account_circle_outlined,
                size: 100,
                color: AppDesignSystem.primaryLight.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 32),

            // Title
            Text(
              'Choose Your Username',
              style: AppDesignSystem.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This will be your unique identifier on the ICP network',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: AppDesignSystem.neutral600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Warning about username permanence
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignSystem.accentLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppDesignSystem.accentLight.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: AppDesignSystem.accentDark,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Username cannot be changed later',
                      style: AppDesignSystem.bodySmall.copyWith(
                        color: AppDesignSystem.accentDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Username input
            TextFormField(
              controller: _usernameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'alice',
                prefixIcon: const Icon(Icons.alternate_email),
                suffixIcon: _buildValidationIcon(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onUsernameChanged,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Username is required';
                }
                if (_validation?.isValid == false) {
                  return _validation?.error;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Format rules
            _buildFormatRules(),
            const SizedBox(height: 32),

            // Display Name input
            TextFormField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: 'Display Name *',
                hintText: 'Alice Developer',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Display name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Contact Email (optional)
            TextFormField(
              controller: _contactEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email (optional)',
                hintText: 'alice@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contact Telegram (optional)
            TextFormField(
              controller: _contactTelegramController,
              decoration: InputDecoration(
                labelText: 'Telegram (optional)',
                hintText: '@alice',
                prefixIcon: const Icon(Icons.send_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contact Twitter (optional)
            TextFormField(
              controller: _contactTwitterController,
              decoration: InputDecoration(
                labelText: 'Twitter/X (optional)',
                hintText: '@alice_dev',
                prefixIcon: const Icon(Icons.tag),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contact Discord (optional)
            TextFormField(
              controller: _contactDiscordController,
              decoration: InputDecoration(
                labelText: 'Discord (optional)',
                hintText: 'alice#1234',
                prefixIcon: const Icon(Icons.forum_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Website URL (optional)
            TextFormField(
              controller: _websiteUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Website (optional)',
                hintText: 'https://alice.dev',
                prefixIcon: const Icon(Icons.language),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Bio (optional)
            TextFormField(
              controller: _bioController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Bio (optional)',
                hintText: 'Tell us about yourself...',
                prefixIcon: const Icon(Icons.notes),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),

            // Continue button
            FilledButton(
              onPressed: _canContinue ? _goToReview : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppDesignSystem.primaryLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isValidating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Step 2: Review Details
  Widget _buildReviewStep() {
    final publicKeyHex = AccountSignatureService.publicKeyToHex(widget.identity.publicKey);
    final principal = PrincipalUtils.textFromRecord(widget.identity);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProgressIndicator(2, 3),
          const SizedBox(height: 32),

          Text(
            'Review Details',
            style: AppDesignSystem.heading2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Account details card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppDesignSystem.neutral200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    'Username',
                    '@${_usernameController.text}',
                    Icons.person,
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    'Public Key',
                    _truncateKey(publicKeyHex),
                    Icons.key,
                    onCopy: () => _copyToClipboard(publicKeyHex, 'Public key'),
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    'IC Principal',
                    _truncatePrincipal(principal),
                    Icons.fingerprint,
                    onCopy: () => _copyToClipboard(principal, 'Principal'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Info message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppDesignSystem.accentLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppDesignSystem.accentLight.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppDesignSystem.accentDark,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This operation will be cryptographically signed with your identity.',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: AppDesignSystem.accentDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _createAccount,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppDesignSystem.primaryLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Step 3: Processing
  Widget _buildProcessingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 32),
              Text(
                _processingStatus,
                style: AppDesignSystem.heading3,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppDesignSystem.errorLight,
              ),
              const SizedBox(height: 24),
              Text(
                'Registration Failed',
                style: AppDesignSystem.heading2.copyWith(
                  color: AppDesignSystem.errorDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: AppDesignSystem.neutral600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => setState(() {
                  _currentStep = 1;
                  _errorMessage = null;
                }),
                child: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Step 4: Success
  Widget _buildSuccessStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Success icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppDesignSystem.successGradient,
              ),
              child: const Icon(
                Icons.check,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Account Created!',
              style: AppDesignSystem.heading1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Text(
              '@${_createdAccount?.username ?? _usernameController.text}',
              style: AppDesignSystem.heading3.copyWith(
                color: AppDesignSystem.accentDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              'Your account is ready on the ICP network.',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: AppDesignSystem.neutral600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            FilledButton(
              onPressed: () => Navigator.pop(context, _createdAccount),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                backgroundColor: AppDesignSystem.primaryLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View Account Profile',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widgets
  Widget _buildProgressIndicator(int current, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 1; i <= total; i++) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current
                  ? AppDesignSystem.primaryLight
                  : AppDesignSystem.neutral300,
            ),
          ),
          if (i < total)
            Container(
              width: 40,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: i < current
                  ? AppDesignSystem.primaryLight
                  : AppDesignSystem.neutral300,
            ),
        ],
      ],
    );
  }

  Widget _buildValidationIcon() {
    if (_isValidating) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_validation == null || _usernameController.text.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_validation!.isValid) {
      return const Icon(
        Icons.check_circle,
        color: AppDesignSystem.successLight,
      );
    } else {
      return const Icon(
        Icons.cancel,
        color: AppDesignSystem.errorLight,
      );
    }
  }

  Widget _buildFormatRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Username requirements:',
          style: AppDesignSystem.bodySmall.copyWith(
            color: AppDesignSystem.neutral600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildRule('3-32 characters'),
        _buildRule('Lowercase letters and numbers'),
        _buildRule('Can use _ or -'),
        _buildRule('Cannot start or end with _ or -'),
      ],
    );
  }

  Widget _buildRule(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: AppDesignSystem.neutral400,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    VoidCallback? onCopy,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppDesignSystem.primaryLight),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppDesignSystem.bodySmall.copyWith(
                  color: AppDesignSystem.neutral600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: onCopy,
            tooltip: 'Copy',
          ),
      ],
    );
  }

  // Logic
  void _onUsernameChanged(String value) {
    // Cancel previous timer
    _debounceTimer?.cancel();

    // Reset validation if empty
    if (value.isEmpty) {
      setState(() {
        _validation = null;
        _isValidating = false;
      });
      return;
    }

    // Start new timer for debounced validation
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _validateUsername(value);
    });
  }

  Future<void> _validateUsername(String username) async {
    setState(() {
      _isValidating = true;
    });

    try {
      // Check format first
      final formatValidation = widget.accountController.validateUsername(username);
      if (!formatValidation.isValid) {
        setState(() {
          _validation = formatValidation;
          _isValidating = false;
        });
        return;
      }

      // Check availability
      final isAvailable = await widget.accountController.isUsernameAvailable(username);
      setState(() {
        _validation = isAvailable
            ? UsernameValidation.valid
            : UsernameValidation.invalid('Username already taken');
        _isValidating = false;
      });
    } catch (e) {
      setState(() {
        _validation = UsernameValidation.invalid('Failed to check availability');
        _isValidating = false;
      });
    }
  }

  bool get _canContinue {
    return _usernameController.text.trim().isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty;
  }

  Future<void> _goToReview() async {
    // Validate username if not already validated
    final username = _usernameController.text.trim();
    if (_validation == null || !_validation!.isValid) {
      setState(() => _isValidating = true);
      await _validateUsername(username);
      setState(() => _isValidating = false);
    }

    // Now validate the form
    if (_formKey.currentState?.validate() ?? false) {
      HapticFeedback.lightImpact();
      setState(() => _currentStep = 1);
    }
  }

  Future<void> _createAccount() async {
    HapticFeedback.lightImpact();
    setState(() {
      _currentStep = 2;
      _processingStatus = 'Generating signature...';
    });

    try {
      // Simulate progress
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _processingStatus = 'Submitting to network...');

      // Create account
      final account = await widget.accountController.registerAccount(
        identity: widget.identity,
        username: _usernameController.text,
        displayName: _displayNameController.text,
        contactEmail: _contactEmailController.text.isEmpty ? null : _contactEmailController.text,
        contactTelegram: _contactTelegramController.text.isEmpty ? null : _contactTelegramController.text,
        contactTwitter: _contactTwitterController.text.isEmpty ? null : _contactTwitterController.text,
        contactDiscord: _contactDiscordController.text.isEmpty ? null : _contactDiscordController.text,
        websiteUrl: _websiteUrlController.text.isEmpty ? null : _websiteUrlController.text,
        bio: _bioController.text.isEmpty ? null : _bioController.text,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _processingStatus = 'Verifying...');

      await Future.delayed(const Duration(milliseconds: 500));

      // Success!
      setState(() {
        _createdAccount = account;
        _currentStep = 3;
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  String _truncateKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 10)}...${key.substring(key.length - 8)}';
  }

  String _truncatePrincipal(String principal) {
    if (principal.length <= 12) return principal;
    return '${principal.substring(0, 8)}...${principal.substring(principal.length - 6)}';
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
