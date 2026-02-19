import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/profile_controller.dart';
import '../theme/app_design_system.dart';

class ExportKeysDialog extends StatefulWidget {
  const ExportKeysDialog({
    required this.profileId,
    required this.profileController,
    super.key,
  });

  final String profileId;
  final ProfileController profileController;

  @override
  State<ExportKeysDialog> createState() => _ExportKeysDialogState();
}

class _ExportKeysDialogState extends State<ExportKeysDialog> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isExporting = false;
  String? _encryptedExport;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _exportKeys() async {
    if (_passwordController.text.isEmpty) {
      _showError('Please enter a password');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_passwordController.text.length < 8) {
      _showError('Password must be at least 8 characters');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final encrypted = await widget.profileController.exportProfileBackup(
        widget.profileId,
        _passwordController.text,
      );
      if (mounted) {
        setState(() => _encryptedExport = encrypted);
      }
    } catch (e) {
      if (mounted) {
        _showError('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _copyToClipboard() {
    if (_encryptedExport == null) return;
    Clipboard.setData(ClipboardData(text: _encryptedExport!));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Encrypted backup copied to clipboard'),
        backgroundColor: AppDesignSystem.successLight,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppDesignSystem.errorLight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_encryptedExport != null) {
      return _buildSuccessDialog();
    }
    return _buildPasswordDialog();
  }

  Widget _buildPasswordDialog() {
    return AlertDialog(
      title: const Text('Export Keys'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create an encrypted backup of your keypairs for disaster recovery.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  );
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Password must be at least 8 characters. Keep it safe - it cannot be recovered.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.warningDark,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isExporting ? null : _exportKeys,
          child: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Export'),
        ),
      ],
    );
  }

  Widget _buildSuccessDialog() {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: AppDesignSystem.successLight),
          const SizedBox(width: 8),
          const Text('Export Complete'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your encrypted backup is ready. Copy it to a safe location.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_encryptedExport!.length} characters encrypted',
              style: AppDesignSystem.bodySmall.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _copyToClipboard,
          icon: const Icon(Icons.copy),
          label: const Text('Copy to Clipboard'),
        ),
      ],
    );
  }
}
