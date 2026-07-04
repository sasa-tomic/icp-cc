import 'package:flutter/material.dart';
import '../services/passkey_service.dart';
import '../theme/app_design_system.dart';

typedef VaultUnlockedCallback = void Function();

class VaultUnlockScreen extends StatefulWidget {
  const VaultUnlockScreen({
    required this.accountId,
    this.onUnlocked,
    this.onUseRecoveryCode,
    super.key,
  });

  final String accountId;
  final VaultUnlockedCallback? onUnlocked;
  final VoidCallback? onUseRecoveryCode;

  @override
  State<VaultUnlockScreen> createState() => _VaultUnlockScreenState();
}

class _VaultUnlockScreenState extends State<VaultUnlockScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isUnlocking = false;
  String? _errorMessage;
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlockVault() async {
    if (_passwordController.text.isEmpty) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

    try {
      final vaultData = await PasskeyService().getVault(widget.accountId);
      if (vaultData == null) {
        throw PasskeyException('Vault not found');
      }

      // TODO(A-4 W3): the unlock currently only confirms the vault exists.
      // The next commit rewrites this to decrypt vaultData locally via
      // VaultCryptoService.decrypt (using the entered password) and surface
      // the decrypted contents — replacing today's get→update no-op.
      // Until then, no client-side decryption is performed.
      if (mounted) {
        widget.onUnlocked?.call();
        Navigator.pop(context, true);
      }
    } on PasskeyException catch (e) {
      setState(() {
        _failedAttempts++;
        _errorMessage = _failedAttempts >= 3
            ? 'Multiple failed attempts. Consider using a recovery code.'
            : e.message;
        _isUnlocking = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to unlock vault: $e';
        _isUnlocking = false;
      });
    }
  }

  void _useRecoveryCode() {
    widget.onUseRecoveryCode?.call();
    Navigator.pop(context);
    // Navigate to recovery screen
    Navigator.pushNamed(context, '/recovery');
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
          onPressed: _isUnlocking ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Unlock Vault',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLockIcon(),
            const SizedBox(height: 24),
            _buildPasswordField(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
            const SizedBox(height: 24),
            _buildUnlockButton(),
            const SizedBox(height: 16),
            _buildRecoveryLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildLockIcon() {
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppDesignSystem.primaryLight.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.lock_outline,
          size: 40,
          color: AppDesignSystem.primaryLight,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your vault password',
          style: AppDesignSystem.bodyMedium.copyWith(
            color: AppDesignSystem.neutral600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          onFieldSubmitted: (_) => _unlockVault(),
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter vault password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppDesignSystem.errorLight.withValues(alpha: 0.3),
        ),
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

  Widget _buildUnlockButton() {
    return ElevatedButton(
      onPressed: _isUnlocking || _passwordController.text.isEmpty
          ? null
          : _unlockVault,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignSystem.primaryLight,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppDesignSystem.neutral300,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isUnlocking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Text('Unlock',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildRecoveryLink() {
    return Center(
      child: TextButton(
        onPressed: _isUnlocking ? null : _useRecoveryCode,
        child: Text(
          'Forgot password? Use recovery code',
          style: AppDesignSystem.bodyMedium.copyWith(
            color: AppDesignSystem.primaryLight,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
