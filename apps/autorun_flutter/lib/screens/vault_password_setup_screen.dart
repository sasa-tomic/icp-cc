import 'package:flutter/material.dart';
import '../models/profile_keypair.dart';
import '../services/passkey_service.dart';
import '../services/vault_crypto_service.dart';
import '../theme/app_design_system.dart';
import '../utils/password_strength.dart';
import '../utils/friendly_error.dart';
import 'recovery_codes_screen.dart';

typedef VaultCreatedCallback = void Function();

class VaultPasswordSetupScreen extends StatefulWidget {
  const VaultPasswordSetupScreen({
    required this.accountId,
    required this.keypair,
    this.onVaultCreated,
    this.vaultCrypto = const VaultCryptoService(),
    this.isReset = false,
    super.key,
  });

  final String accountId;

  /// The active profile keypair — used to sign the signature-gated vault
  /// request (W7-12). The backend resolves `accountId` from its public key.
  final ProfileKeypair keypair;
  final VaultCreatedCallback? onVaultCreated;

  /// Vault crypto service used to encrypt locally before POSTing. Injected so
  /// widget tests can substitute a deterministic fake (the real FFI crypto is
  /// unit-tested separately in vault_crypto_service_test.dart).
  final VaultCryptoService vaultCrypto;

  /// When `true`, the screen updates the existing vault blob (PUT /vault)
  /// instead of creating a new one (POST /vault). Used by the recovery-code
  /// reset flow reached from [VaultUnlockScreen]: a verified recovery code
  /// proves ownership, after which the user sets a new password.
  final bool isReset;

  @override
  State<VaultPasswordSetupScreen> createState() =>
      _VaultPasswordSetupScreenState();
}

class _VaultPasswordSetupScreenState extends State<VaultPasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onFormChanged);
    _confirmController.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onFormChanged);
    _confirmController.removeListener(_onFormChanged);
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 12) {
      return 'Password must be at least 12 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain special character';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _createVault() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final service = PasskeyService();
      // A-4 W2/W3: encrypt '{}' locally, then POST (create) or PUT (reset)
      // only the opaque blob. The password never leaves the device.
      if (widget.isReset) {
        await service.updateVault(
          keypair: widget.keypair,
          accountId: widget.accountId,
          password: _passwordController.text,
          plaintext: '{}',
          vaultCrypto: widget.vaultCrypto,
        );
      } else {
        await service.createVault(
          keypair: widget.keypair,
          accountId: widget.accountId,
          password: _passwordController.text,
          plaintext: '{}',
          vaultCrypto: widget.vaultCrypto,
        );
      }

      if (!mounted) return;

      // After a fresh CREATE, generate one-time recovery codes and show them
      // so the user can save them (the only way back if they forget this
      // password). Skipped on reset — existing codes remain valid.
      if (!widget.isReset) {
        try {
          final result = await service.generateRecoveryCodes(
            keypair: widget.keypair,
            accountId: widget.accountId,
          );
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => RecoveryCodesScreen(
                codes: result.codes,
                accountId: widget.accountId,
              ),
            ),
          );
        } on PasskeyException catch (e) {
          // The vault WAS created; failing to generate codes must not undo
          // that. Surface the error loudly but continue to success.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Vault created, but recovery codes unavailable: ${e.message}'),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      widget.onVaultCreated?.call();
      Navigator.pop(context, true);
    } on PasskeyException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isCreating = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = friendlyErrorMessage(
          e,
          context: "Failed to ${widget.isReset ? 'reset' : 'create'} vault",
        );
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isCreating ? null : () => Navigator.pop(context),
        ),
        title: Text(
          widget.isReset ? 'Reset Vault Password' : 'Set Vault Password',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoCard(),
              const SizedBox(height: 32),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildStrengthMeter(),
              const SizedBox(height: 16),
              _buildConfirmField(),
              const SizedBox(height: 16),
              _buildPasswordRequirements(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildErrorCard(),
              ],
              const SizedBox(height: 32),
              _buildCreateButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignSystem.accentLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppDesignSystem.accentLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: AppDesignSystem.accentDark,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Encryption Password',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: AppDesignSystem.accentDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This password encrypts your keypairs. It cannot be recovered if lost. Use a strong, memorable password.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: _obscurePassword,
      validator: _validatePassword,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _confirmFocusNode.requestFocus(),
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: 'Enter strong password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon:
              Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStrengthMeter() {
    final score = passwordStrength(_passwordController.text);
    final label = passwordStrengthLabel(score);
    final color = _strengthColor(score);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (score + 1) / 4,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              backgroundColor:
                  color.withValues(alpha: 0.18),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: AppDesignSystem.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _strengthColor(int score) {
    final colors = Theme.of(context).colorScheme;
    if (score <= 1) return colors.error;
    if (score == 2) return AppDesignSystem.warningColor;
    if (score == 3) return AppDesignSystem.accentLight;
    return AppDesignSystem.successColor;
  }

  Widget _buildConfirmField() {
    return TextFormField(
      controller: _confirmController,
      focusNode: _confirmFocusNode,
      obscureText: _obscureConfirm,
      validator: _validateConfirm,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) {
        if (_isFormValid && !_isCreating) _createVault();
      },
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        hintText: 'Re-enter password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignSystem.neutral100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requirements:',
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral700,
            ),
          ),
          const SizedBox(height: 8),
          _buildRequirement('At least 12 characters'),
          _buildRequirement('One uppercase letter (A-Z)'),
          _buildRequirement('One lowercase letter (a-z)'),
          _buildRequirement('One number (0-9)'),
          _buildRequirement('One special character (!@#\$%^&*)'),
        ],
      ),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: AppDesignSystem.neutral500),
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

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppDesignSystem.errorLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppDesignSystem.errorDark, size: 20),
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
    );
  }

  bool get _isFormValid {
    return _passwordController.text.length >= 12 &&
        RegExp(r'[A-Z]').hasMatch(_passwordController.text) &&
        RegExp(r'[a-z]').hasMatch(_passwordController.text) &&
        RegExp(r'[0-9]').hasMatch(_passwordController.text) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(_passwordController.text) &&
        _confirmController.text == _passwordController.text;
  }

  Widget _buildCreateButton() {
    final isValid = _isFormValid;

    return ElevatedButton(
      onPressed: _isCreating || !isValid ? null : _createVault,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignSystem.primaryLight,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isCreating
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
            )
          : Text(widget.isReset ? 'Reset Vault' : 'Create Vault',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
