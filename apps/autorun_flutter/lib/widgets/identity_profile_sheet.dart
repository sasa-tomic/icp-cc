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
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _telegramController;
  late final TextEditingController _twitterController;
  late final TextEditingController _discordController;
  late final TextEditingController _websiteController;
  late final TextEditingController _bioController;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final IdentityProfile? profile = widget.existingProfile;
    _displayNameController = TextEditingController(
      text: profile?.displayName ?? (widget.identity.label.isEmpty ? null : widget.identity.label),
    );
    _usernameController = TextEditingController(text: profile?.username);
    _emailController = TextEditingController(text: profile?.contactEmail);
    _telegramController = TextEditingController(text: profile?.contactTelegram);
    _twitterController = TextEditingController(text: profile?.contactTwitter);
    _discordController = TextEditingController(text: profile?.contactDiscord);
    _websiteController = TextEditingController(text: profile?.websiteUrl);
    _bioController = TextEditingController(text: profile?.bio);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _telegramController.dispose();
    _twitterController.dispose();
    _discordController.dispose();
    _websiteController.dispose();
    _bioController.dispose();
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
                'Add contact details so collaborators can reach you. These values are stored on the server.',
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
              const SizedBox(height: 12),
              _buildTextField(
                controller: _usernameController,
                label: 'Username',
                hint: '@handle or short alias',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                label: 'Contact email',
                keyboardType: TextInputType.emailAddress,
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return null;
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildTextField(
                      controller: _telegramController,
                      label: 'Telegram',
                      hint: '@username',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _twitterController,
                      label: 'X / Twitter',
                      hint: '@username',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _discordController,
                label: 'Discord',
                hint: 'user#1234',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _websiteController,
                label: 'Website',
                hint: 'https://example.com',
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return null;
                  }
                  if (!value.startsWith('http://') && !value.startsWith('https://')) {
                    return 'Website must include http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _bioController,
                label: 'Short bio',
                hint: 'Share a sentence about what you build.',
                maxLines: 3,
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
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        contactEmail: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        contactTelegram:
            _telegramController.text.trim().isEmpty ? null : _telegramController.text.trim(),
        contactTwitter:
            _twitterController.text.trim().isEmpty ? null : _twitterController.text.trim(),
        contactDiscord:
            _discordController.text.trim().isEmpty ? null : _discordController.text.trim(),
        websiteUrl: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
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
