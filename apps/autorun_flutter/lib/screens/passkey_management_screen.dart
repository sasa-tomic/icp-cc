import 'package:flutter/material.dart';
import '../services/passkey_service.dart';
import '../theme/app_design_system.dart';
import '../utils/passkey_platform.dart';

class PasskeyManagementScreen extends StatefulWidget {
  const PasskeyManagementScreen({
    required this.accountId,
    required this.username,
    super.key,
  });

  final String accountId;
  final String username;

  @override
  State<PasskeyManagementScreen> createState() =>
      _PasskeyManagementScreenState();
}

class _PasskeyManagementScreenState extends State<PasskeyManagementScreen> {
  List<PasskeyInfo> _passkeys = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPasskeys();
  }

  Future<void> _loadPasskeys() async {
    if (!PasskeyPlatform.isSupported) {
      setState(() {
        _errorMessage =
            'Passkeys are not supported on Linux desktop. Use Flutter Web (chrome) for passkey authentication.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final passkeys = await PasskeyService().listPasskeys(widget.accountId);
      if (mounted) {
        setState(() {
          _passkeys = passkeys;
          _isLoading = false;
        });
      }
    } on PasskeyException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addPasskey() async {
    try {
      await PasskeyService().registerPasskey(
        accountId: widget.accountId,
        username: widget.username,
        deviceName: _getDeviceName(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passkey added successfully')),
        );
        _loadPasskeys();
      }
    } on PasskeyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add passkey: ${e.message}')),
        );
      }
    }
  }

  Future<void> _deletePasskey(PasskeyInfo passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Passkey?'),
        content: Text(
          'Are you sure you want to delete the passkey "${passkey.deviceName ?? 'Unknown device'}"? '
          'You will not be able to log in with this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
                foregroundColor: AppDesignSystem.errorDark),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PasskeyService().deletePasskey(
        passkeyId: passkey.id,
        accountId: widget.accountId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passkey deleted')),
        );
        _loadPasskeys();
      }
    } on PasskeyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete passkey: ${e.message}')),
        );
      }
    }
  }

  String _getDeviceName() {
    // This would typically use device_info_plus
    return 'This Device';
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    return '${date.day}/${date.month}/${date.year}';
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Passkeys',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPasskey,
        backgroundColor: AppDesignSystem.primaryLight,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Passkey'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: AppDesignSystem.errorDark),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppDesignSystem.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadPasskeys, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_passkeys.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _passkeys.length,
      itemBuilder: (context, index) => _buildPasskeyCard(_passkeys[index]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.key_off_outlined,
            size: 64,
            color: AppDesignSystem.neutral400,
          ),
          const SizedBox(height: 16),
          Text(
            'No Passkeys Yet',
            style: AppDesignSystem.heading4.copyWith(
              color: AppDesignSystem.neutral600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a passkey to enable secure, passwordless login',
            style: AppDesignSystem.bodyMedium.copyWith(
              color: AppDesignSystem.neutral500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasskeyCard(PasskeyInfo passkey) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppDesignSystem.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.key,
                color: AppDesignSystem.primaryLight,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    passkey.deviceName ?? 'Unknown Device',
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Added ${_formatDate(passkey.createdAt)}'
                    '${passkey.lastUsedAt != null ? ' • Last used ${_formatDate(passkey.lastUsedAt!)}' : ''}',
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: AppDesignSystem.neutral500,
                    ),
                  ),
                  if (passkey.deviceType != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppDesignSystem.neutral100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        passkey.deviceType!,
                        style: AppDesignSystem.caption.copyWith(
                          color: AppDesignSystem.neutral600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppDesignSystem.neutral400,
              onPressed: () => _deletePasskey(passkey),
            ),
          ],
        ),
      ),
    );
  }
}
