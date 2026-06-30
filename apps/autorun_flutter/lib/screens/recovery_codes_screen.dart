import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_design_system.dart';

typedef CodesConfirmedCallback = void Function();

class RecoveryCodesScreen extends StatefulWidget {
  const RecoveryCodesScreen({
    required this.codes,
    required this.accountId,
    this.onConfirmed,
    super.key,
  });

  final List<String> codes;
  final String accountId;
  final CodesConfirmedCallback? onConfirmed;

  @override
  State<RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends State<RecoveryCodesScreen> {
  bool _hasConfirmed = false;

  Future<void> _copyAllCodes() async {
    await Clipboard.setData(ClipboardData(text: widget.codes.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery codes copied to clipboard')),
      );
    }
  }

  void _confirmAndContinue() {
    setState(() => _hasConfirmed = true);
    widget.onConfirmed?.call();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text(
          'Recovery Codes',
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
            _buildWarningCard(),
            const SizedBox(height: 24),
            _buildCodesGrid(),
            const SizedBox(height: 24),
            _buildCopyButton(),
            const SizedBox(height: 16),
            _buildConfirmCheckbox(),
            const SizedBox(height: 24),
            _buildContinueButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignSystem.warningLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppDesignSystem.warningLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppDesignSystem.warningDark,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Save These Codes',
                style: AppDesignSystem.heading4.copyWith(
                  color: AppDesignSystem.warningDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'These recovery codes are the ONLY way to access your vault if you forget your password. Store them securely.',
            style: AppDesignSystem.bodyMedium.copyWith(
              color: AppDesignSystem.neutral800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Each code can only be used once.',
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodesGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignSystem.neutral100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppDesignSystem.neutral200),
      ),
      child: Column(
        children: [
          for (int i = 0; i < widget.codes.length; i += 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCodeItem(i + 1, widget.codes[i]),
                  ),
                  const SizedBox(width: 16),
                  if (i + 1 < widget.codes.length)
                    Expanded(
                      child: _buildCodeItem(i + 2, widget.codes[i + 1]),
                    )
                  else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCodeItem(int number, String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppDesignSystem.neutral200),
      ),
      child: Row(
        children: [
          Text(
            '$number.'.padLeft(3),
            style: AppDesignSystem.bodySmall.copyWith(
              color: AppDesignSystem.neutral500,
              fontFeatures: const [FontFeature('tnum')],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            code,
            style: AppDesignSystem.bodyMedium.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyButton() {
    return OutlinedButton.icon(
      onPressed: _copyAllCodes,
      icon: const Icon(Icons.copy),
      label: const Text('Copy All Codes'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppDesignSystem.primaryLight,
        side: BorderSide(color: AppDesignSystem.primaryLight),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildConfirmCheckbox() {
    return InkWell(
      onTap: () => setState(() => _hasConfirmed = !_hasConfirmed),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Checkbox(
              value: _hasConfirmed,
              onChanged: (v) => setState(() => _hasConfirmed = v ?? false),
              activeColor: AppDesignSystem.primaryLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'I have saved these recovery codes in a secure location',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: AppDesignSystem.neutral800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return ElevatedButton(
      onPressed: _hasConfirmed ? _confirmAndContinue : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignSystem.primaryLight,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppDesignSystem.neutral300,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        'Continue',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}
