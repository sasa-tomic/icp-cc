import 'package:flutter/material.dart';
import '../services/passkey_service.dart';
import '../theme/app_design_system.dart';

typedef VaultCreatedCallback = void Function();

class VaultPasswordSetupScreen extends StatefulWidget {
  const VaultPasswordSetupScreen({
    required this.accountId,
    this.onVaultCreated,
    super.key,
  });

  final String accountId;
  final VaultCreatedCallback? onVaultCreated;

  @override
  State<VaultPasswordSetupScreen> createState() =>
      _VaultPasswordSetupScreenState();
}

class _VaultPasswordSetupScreenState extends State<VaultPasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
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
      // A-4 W2: PasskeyService.createVault now encrypts '{}' locally via
      // VaultCryptoService before POSTing only the opaque blob. The password
      // never leaves the device.
      await PasskeyService().createVault(
        accountId: widget.accountId,
        password: _passwordController.text,
        plaintext: '{}',
      );

      if (mounted) {
        widget.onVaultCreated?.call();
        Navigator.pop(context, true);
      }
    } on PasskeyException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isCreating = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create vault: $e';
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
          'Set Vault Password',
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
      obscureText: _obscurePassword,
      validator: _validatePassword,
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

  Widget _buildConfirmField() {
    return TextFormField(
      controller: _confirmController,
      obscureText: _obscureConfirm,
      validator: _validateConfirm,
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

  Widget _buildCreateButton() {
    final isValid = _passwordController.text.length >= 12 &&
        RegExp(r'[A-Z]').hasMatch(_passwordController.text) &&
        RegExp(r'[a-z]').hasMatch(_passwordController.text) &&
        RegExp(r'[0-9]').hasMatch(_passwordController.text) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(_passwordController.text) &&
        _confirmController.text == _passwordController.text;

    return ElevatedButton(
      onPressed: _isCreating || !isValid ? null : _createVault,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignSystem.primaryLight,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isCreating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Text('Create Vault',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
