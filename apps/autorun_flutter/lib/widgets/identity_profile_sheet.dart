import 'package:flutter/material.dart';

import '../models/identity_profile.dart';
import '../models/identity_record.dart';
import '../utils/principal.dart';

Future<IdentityProfileDraft?> showIdentityProfileSheet({
  required BuildContext context,
  required IdentityRecord identity,
  IdentityProfile? existingProfile,
}) {
  return showModalBottomSheet<IdentityProfileDraft>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return _IdentityProfileForm(
        identity: identity,
        existingProfile: existingProfile,
      );
    },
  );
}

class _IdentityProfileForm extends StatefulWidget {
  const _IdentityProfileForm({
    required this.identity,
    this.existingProfile,
  });

  final IdentityRecord identity;
  final IdentityProfile? existingProfile;

  @override
  State<_IdentityProfileForm> createState() => _IdentityProfileFormState();
}

class _IdentityProfileFormState extends State<_IdentityProfileForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _displayNameController;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final IdentityProfile? profile = widget.existingProfile;
    _displayNameController = TextEditingController(
      text: profile?.displayName ?? (widget.identity.label.isEmpty ? null : widget.identity.label),
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.of(context).viewInsets +
        const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
    return Padding(
      padding: padding,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Identity profile',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Set a display name for this identity. Contact details are managed in your marketplace account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _displayNameController,
                label: 'Display name *',
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _handleSubmit,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save profile'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final IdentityProfileDraft draft = IdentityProfileDraft(
        principal: PrincipalUtils.textFromRecord(widget.identity),
        displayName: _displayNameController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(draft);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
