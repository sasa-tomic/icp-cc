import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../models/profile_keypair.dart';
import '../controllers/account_controller.dart';
import '../theme/app_design_system.dart';
import '../utils/passkey_platform.dart';
import '../utils/friendly_error.dart';
import 'passkey_management_screen.dart';

/// Default passkey-support probe. A top-level function so it can be used as a
/// const default argument (tear-offs of top-level functions are constants),
/// while still being injectable in tests.
bool _defaultIsPasskeySupported() => PasskeyPlatform.isSupported;

/// Account registration screen with single-page form
///
/// Collects all account information in one form:
/// - Username selection with real-time validation
/// - Display name and optional contact details
/// - Single "Register" button submits the form
class AccountRegistrationWizard extends StatefulWidget {
  const AccountRegistrationWizard({
    required this.keypair,
    required this.accountController,
    this.initialDisplayName,
    this.isPasskeySupported = _defaultIsPasskeySupported,
    super.key,
  });

  final ProfileKeypair keypair;
  final AccountController accountController;

  /// Pre-filled display name (typically from profile name)
  final String? initialDisplayName;

  /// Whether passkey setup is offered after a successful registration.
  /// Defaults to [PasskeyPlatform.isSupported]. Injectable in tests so the
  /// passkey branch can be exercised on Linux desktop (where it is normally
  /// false).
  final bool Function() isPasskeySupported;

  @override
  State<AccountRegistrationWizard> createState() =>
      _AccountRegistrationWizardState();
}

class _AccountRegistrationWizardState extends State<AccountRegistrationWizard> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactTelegramController = TextEditingController();
  final _contactTwitterController = TextEditingController();
  final _contactDiscordController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _bioController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _displayNameFocusNode = FocusNode();

  // Validation state
  bool _isValidating = false;
  UsernameValidation? _validation;
  Timer? _debounceTimer;

  // Processing state
  bool _isRegistering = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialDisplayName != null) {
      _displayNameController.text = widget.initialDisplayName!;
    }
  }

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
    _displayNameFocusNode.dispose();
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
          onPressed: _isRegistering ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Register Username',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildRegistrationForm(),
    );
  }

  Widget _buildRegistrationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _displayNameFocusNode.requestFocus(),
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
              focusNode: _displayNameFocusNode,
              decoration: InputDecoration(
                labelText: 'Display Name *',
                hintText: 'Alice Developer',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (_canRegister && !_isRegistering) _registerAccount();
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Display name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Optional contact details are collapsed by default so the primary
            // task ("pick a @username so I can publish") stays front and center.
            // Matches the contact-info expander used in account_profile_screen.
            ExpansionTile(
              title: Text(
                'Add contact details (optional)',
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Email, social links, website, and bio',
                style: AppDesignSystem.bodySmall.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              leading: Icon(
                Icons.contact_mail_outlined,
                color: AppDesignSystem.primaryLight,
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: [
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
                    hintText: '@your_handle',
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
              ],
            ),
            const SizedBox(height: 24),

            // Error message (if any)
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

            // Register button
            FilledButton(
              onPressed:
                  (_canRegister && !_isRegistering) ? _registerAccount : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppDesignSystem.primaryLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isRegistering
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Text(
                      'Register',
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
    _debounceTimer = Timer(AppDurations.debounce, () {
      _validateUsername(value);
    });
  }

  Future<void> _validateUsername(String username) async {
    setState(() {
      _isValidating = true;
    });

    try {
      // Check format first
      final formatValidation =
          widget.accountController.validateUsername(username);
      if (!formatValidation.isValid) {
        setState(() {
          _validation = formatValidation;
          _isValidating = false;
        });
        return;
      }

      // Check availability
      final isAvailable =
          await widget.accountController.isUsernameAvailable(username);
      setState(() {
        _validation = isAvailable
            ? UsernameValidation.valid
            : UsernameValidation.invalid('Username already taken');
        _isValidating = false;
      });
    } catch (e) {
      setState(() {
        _validation =
            UsernameValidation.invalid('Failed to check availability');
        _isValidating = false;
      });
    }
  }

  bool get _canRegister {
    return _usernameController.text.trim().isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty &&
        _validation?.isValid == true;
  }

  Future<void> _registerAccount() async {
    // Validate username if not already validated
    final username = _usernameController.text.trim();
    if (_validation == null || !_validation!.isValid) {
      setState(() => _isValidating = true);
      await _validateUsername(username);
      setState(() => _isValidating = false);
    }

    // Validate the form
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      // Create account
      final account = await widget.accountController.registerAccount(
        keypair: widget.keypair,
        username: _usernameController.text.trim(),
        displayName: _displayNameController.text.trim(),
        contactEmail: _contactEmailController.text.isEmpty
            ? null
            : _contactEmailController.text,
        contactTelegram: _contactTelegramController.text.isEmpty
            ? null
            : _contactTelegramController.text,
        contactTwitter: _contactTwitterController.text.isEmpty
            ? null
            : _contactTwitterController.text,
        contactDiscord: _contactDiscordController.text.isEmpty
            ? null
            : _contactDiscordController.text,
        websiteUrl: _websiteUrlController.text.isEmpty
            ? null
            : _websiteUrlController.text,
        bio: _bioController.text.isEmpty ? null : _bioController.text,
      );

      HapticFeedback.mediumImpact();

      if (!mounted) return;

      // Registration succeeded: stop the in-progress spinner now. Without this
      // the Register button's CircularProgressIndicator keeps ticking forever
      // behind the passkey prompt (or after pop), which never lets
      // `pumpAndSettle` settle in tests and burns a ticker in production.
      setState(() => _isRegistering = false);

      if (widget.isPasskeySupported()) {
        final shouldSetupPasskey = await _showPasskeySetupPrompt(account);
        if (!mounted) return;
        if (shouldSetupPasskey == true) {
          // Replace this wizard with passkey management for the new account,
          // resolving the caller's `Navigator.push<Account>` with the account
          // via [result]. Returning a record here previously crashed every
          // caller (which reads `.username`) on web/mobile where passkeys are
          // supported; the wizard now always resolves with an [Account].
          await Navigator.of(context).pushReplacement<Account, Account>(
            MaterialPageRoute<Account>(
              builder: (_) => PasskeyManagementScreen(
                accountId: account.id,
                username: account.username,
                keypair: widget.keypair,
              ),
            ),
            result: account,
          );
          return;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, account);
    } catch (e) {
      setState(() {
        _errorMessage = friendlyErrorMessage(e);
        _isRegistering = false;
      });
    }
  }

  Future<bool?> _showPasskeySetupPrompt(Account account) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.key, color: AppDesignSystem.primaryLight),
            const SizedBox(width: 12),
            const Text('Set Up Passkey?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account has been created successfully!',
              style: AppDesignSystem.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Would you like to add a passkey for secure, passwordless login?',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: AppDesignSystem.neutral600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can always set this up later from your account settings.',
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.neutral500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip for now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignSystem.primaryLight,
            ),
            child: const Text('Set Up Passkey'),
          ),
        ],
      ),
    );
  }
}
