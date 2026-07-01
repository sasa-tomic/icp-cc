import 'package:flutter/material.dart';

/// Dialog prompt for account registration when trying to publish without account
class AccountRegistrationPromptDialog extends StatelessWidget {
  const AccountRegistrationPromptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.cloud_upload_outlined,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      title: const Text('Share to Marketplace'),
      content: const Text(
        'To share scripts publicly, you\'ll need to register a @username.\n\n'
        'This lets the community identify you as the script author.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Register Username'),
        ),
      ],
    );
  }
}
