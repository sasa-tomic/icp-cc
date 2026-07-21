import 'package:flutter/material.dart';
import '../models/profile_keypair.dart';
import '../services/passkey_service.dart';
import '../services/vault_crypto_service.dart';
import '../rust/native_bridge.dart';
import '../theme/app_design_system.dart';
import '../utils/friendly_error.dart';
import 'vault_password_setup_screen.dart';

/// Called after the vault is successfully decrypted locally.
/// [decryptedVaultContents] is the plaintext that was encrypted in the blob
/// (surfaced to the caller so downstream code can use it — A-4 W3).
typedef VaultUnlockedCallback = void Function(String decryptedVaultContents);

class VaultUnlockScreen extends StatefulWidget {
  const VaultUnlockScreen({
    required this.accountId,
    required this.keypair,
    this.onUnlocked,
    this.onUseRecoveryCode,
    this.vaultCrypto = const VaultCryptoService(),
    super.key,
  });

  final String accountId;

  /// The active profile keypair — used to sign the signature-gated vault read
  /// (W7-12). Keypairs live in local secure storage (independent of the vault
  /// blob), so this is available at unlock time. The backend resolves
  /// `accountId` from its public key.
  final ProfileKeypair keypair;
  final VaultUnlockedCallback? onUnlocked;
  final VoidCallback? onUseRecoveryCode;

  /// Vault crypto service used to decrypt the blob locally. Injected so widget
  /// tests can substitute a deterministic fake (the real FFI crypto is
  /// unit-tested separately in vault_crypto_service_test.dart).
  final VaultCryptoService vaultCrypto;

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

  /// A-4 W3: GET the opaque blob → decrypt LOCALLY with the entered password
  /// → surface the decrypted contents. The password never leaves the device
  /// (it is consumed only by [VaultCryptoService.decrypt] via the FFI, which
  /// runs off the UI isolate via `compute()` so the spinner animates honestly
  /// through the ~0.1–1 s Argon2id derivation).
  Future<void> _unlockVault() async {
    if (_passwordController.text.isEmpty) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

    try {
      final vaultData = await PasskeyService().getVault(
        keypair: widget.keypair,
        accountId: widget.accountId,
      );
      if (vaultData == null) {
        throw PasskeyException('Vault not found');
      }

      final blob = EncryptedVaultResult(
        encryptedDataB64: vaultData.encryptedData,
        saltB64: vaultData.salt,
        nonceB64: vaultData.nonce,
      );

      final plaintext = await widget.vaultCrypto.decrypt(
        password: _passwordController.text,
        blob: blob,
      );

      if (mounted) {
        widget.onUnlocked?.call(plaintext);
        Navigator.pop(context, true);
      }
    } on VaultDecryptionException {
      // Wrong password OR tampered blob: AES-256-GCM auth-tag failure.
      // Fail loud with a clear, honest error (never silent).
      if (mounted) {
        setState(() {
          _failedAttempts++;
          _errorMessage = _failedAttempts >= 3
              ? 'Multiple failed attempts. Consider using a recovery code.'
              : 'Incorrect password. Please try again.';
          _isUnlocking = false;
        });
      }
    } on VaultUnavailableException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isUnlocking = false;
        });
      }
    } on PasskeyException catch (e) {
      if (mounted) {
        setState(() {
          _failedAttempts++;
          _errorMessage = _failedAttempts >= 3
              ? 'Multiple failed attempts. Consider using a recovery code.'
              : e.message;
          _isUnlocking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(e, context: 'Failed to unlock vault');
          _isUnlocking = false;
        });
      }
    }
  }

  /// "Use recovery code" — verify a saved one-time code against the backend,
  /// then route to [VaultPasswordSetupScreen] in reset mode (PUT /vault with a
  /// new password). A verified code proves ownership, so the reset is
  /// legitimate.
  ///
  /// This replaces the dead `Navigator.pushNamed(context, '/recovery')` (the
  /// route never existed → it threw at runtime).
  Future<void> _useRecoveryCode() async {
    widget.onUseRecoveryCode?.call();

    final code = await _showRecoveryCodeEntryDialog();
    if (code == null || code.isEmpty || !mounted) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

    try {
      final valid = await PasskeyService().verifyRecoveryCode(
        accountId: widget.accountId,
        code: code,
      );
      if (!mounted) return;

      if (valid) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => VaultPasswordSetupScreen(
              accountId: widget.accountId,
              keypair: widget.keypair,
              isReset: true,
            ),
          ),
        );
        if (!mounted) return;
        setState(() => _isUnlocking = false);
      } else {
        setState(() {
          _failedAttempts++;
          _errorMessage = _failedAttempts >= 3
              ? 'Multiple failed attempts. Please check your recovery codes.'
              : 'Invalid or already-used recovery code.';
          _isUnlocking = false;
        });
      }
    } on PasskeyException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isUnlocking = false;
        });
      }
    }
  }

  /// Prompts the user to enter a one-time recovery code. Returns the trimmed
  /// code, or `null` if cancelled.
  Future<String?> _showRecoveryCodeEntryDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use Recovery Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a one-time recovery code you saved when you set up your '
              'vault. After verification you can set a new vault password.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Recovery code',
                hintText: 'e.g. ABCD-1234',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
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
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        disabledBackgroundColor: AppDesignSystem.neutral300,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isUnlocking
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
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
