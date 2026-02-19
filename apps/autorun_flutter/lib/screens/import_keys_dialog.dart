import 'package:flutter/material.dart';
import '../controllers/profile_controller.dart';
import '../theme/app_design_system.dart';

class ImportKeysDialog extends StatefulWidget {
  const ImportKeysDialog({
    required this.profileController,
    super.key,
  });

  final ProfileController profileController;

  @override
  State<ImportKeysDialog> createState() => _ImportKeysDialogState();
}

class _ImportKeysDialogState extends State<ImportKeysDialog> {
  final _encryptedTextController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isImporting = false;
  bool _obscurePassword = true;
  int? _importedCount;

  @override
  void dispose() {
    _encryptedTextController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _importKeys() async {
    if (_encryptedTextController.text.trim().isEmpty) {
      _showError('Please paste the encrypted backup');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showError('Please enter the password');
      return;
    }

    setState(() => _isImporting = true);
    try {
      final profile = await widget.profileController.importProfileBackup(
        _encryptedTextController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        setState(() => _importedCount = profile.keypairs.length);
      }
    } on FormatException catch (e) {
      if (mounted) {
        _showError('Invalid backup format: ${e.message}');
      }
    } on StateError catch (e) {
      if (mounted) {
        if (e.message.contains('already exists')) {
          _showError(
              'Profile already exists. Delete it first or use a different backup.');
        } else if (e.message.contains('Decryption failed')) {
          _showError('Invalid password or corrupted backup');
        } else {
          _showError('Import failed: ${e.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Invalid password or corrupted backup');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
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
    if (_importedCount != null) {
      return _buildSuccessDialog();
    }
    return _buildImportDialog();
  }

  Widget _buildImportDialog() {
    return AlertDialog(
      title: const Text('Import Keys'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restore your keypairs from an encrypted backup.',
              style: AppDesignSystem.bodySmall.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _encryptedTextController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Encrypted Backup',
                hintText: 'Paste your encrypted backup here',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _importKeys,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
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
          const Text('Import Complete'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Successfully imported $_importedCount keypair(s).',
            style: AppDesignSystem.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'The imported profile is now available in your profile list.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
