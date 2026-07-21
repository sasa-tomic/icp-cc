/// UX-H6 — shared post-registration security prompt.
///
/// Both onboarding wizards (`UnifiedSetupWizard` and `AccountRegistrationWizard`)
/// finish by handing the user a freshly-registered account. Without surfacing
/// the security features (vault password + passkey), the user has to discover
/// them buried behind the profile menu — a post-onboarding security gap.
///
/// This helper renders a single, honest, skippable dialog that nudges the user
/// toward BOTH optional steps. It is the single source of truth: both wizards
/// call it with the freshly-registered [Account], and the helper returns the
/// user's selection. The caller decides how to navigate for each choice (so
/// each wizard keeps its own routing semantics — `pushReplacement` vs. `push`).
///
/// Design rules (from OPEN_ISSUES.md UX-H6):
/// - **Skippable, never blocking.** The user can always finish the wizard
///   without setting up either. There is no shame copy on Skip.
/// - **Honest about platform support.** When [defaultIsPasskeySupported]
///   returns `false` (Linux desktop today), the passkey tile is **disabled**
///   with a one-line explanation — it never silently disappears.
/// - **Vault is always available.** Vault encryption is pure local crypto via
///   the Rust FFI; it needs no platform authenticator.
/// - **No raw exceptions.** The helper itself only renders UI; setup errors
///   are surfaced by the vault/passkey screens the caller navigates to, which
///   already use [friendlyErrorMessage].
library;

import 'package:flutter/material.dart';

import '../models/account.dart';
import '../theme/app_design_system.dart';
import '../utils/passkey_platform.dart';

/// The user's selection from [showPostRegistrationSecurityPrompt].
enum PostRegistrationSecurityChoice {
  /// User opted to set up the vault password.
  setUpVault,

  /// User opted to enroll a passkey.
  enrollPasskey,

  /// User chose to skip the prompt.
  skip,
}

/// Default platform probe used when callers don't inject one. A top-level
/// function (not a property tear-off — [PasskeyPlatform.isSupported] is a
/// getter) so it can be used as a const default argument value, while still
/// being injectable in tests (e.g. to exercise the disabled-passkey branch on
/// a non-Linux host).
bool defaultIsPasskeySupported() => PasskeyPlatform.isSupported;

/// UX-H6: shows the optional post-registration security prompt as a modal
/// dialog. The dialog offers two tappable tiles — vault password setup
/// (always enabled) and passkey enrollment (disabled with honest copy when
/// [isPasskeySupported] returns `false`) — plus an explicit Skip action.
///
/// Both options are skippable: this is a nudge, not a trap. The dialog is
/// non-dismissable via the barrier (the user must tap Skip or a tile), but
/// the OS back gesture still cancels it (returned as `null`).
///
/// Returns the user's choice, or `null` if the dialog was dismissed via the
/// OS back gesture (treat as [PostRegistrationSecurityChoice.skip]).
///
/// The helper never navigates — each caller handles its own routing for the
/// selected choice. This keeps the helper pure UI and respects each wizard's
/// `push` vs. `pushReplacement` semantics.
Future<PostRegistrationSecurityChoice?>
    showPostRegistrationSecurityPrompt({
  required BuildContext context,
  required Account account,
  bool Function() isPasskeySupported = defaultIsPasskeySupported,
}) {
  return showDialog<PostRegistrationSecurityChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _PostRegistrationSecurityPromptDialog(
      account: account,
      isPasskeySupported: isPasskeySupported,
    ),
  );
}

class _PostRegistrationSecurityPromptDialog extends StatelessWidget {
  const _PostRegistrationSecurityPromptDialog({
    required this.account,
    required this.isPasskeySupported,
  });

  final Account account;
  final bool Function() isPasskeySupported;

  @override
  Widget build(BuildContext context) {
    final passkeySupported = isPasskeySupported();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: Row(
        children: [
          Icon(Icons.shield_outlined, color: AppDesignSystem.primaryLight),
          const SizedBox(width: 12),
          const Expanded(child: Text('Secure your account')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account @${account.username} is ready. Add an optional '
              'security step now — you can always do this later from your '
              'account settings.',
              style: AppDesignSystem.bodyMedium.copyWith(
                color: AppDesignSystem.neutral700,
              ),
            ),
            const SizedBox(height: 16),
            _SecurityTile(
              icon: Icons.lock_outline,
              iconColor: AppDesignSystem.accentDark,
              title: 'Set up vault password',
              description:
                  'Encrypts your stored credentials with a password only '
                  'you know. Lose it and your data is unrecoverable — '
                  'recovery codes are generated on setup.',
              onTap: () => Navigator.of(context).pop(
                PostRegistrationSecurityChoice.setUpVault,
              ),
            ),
            const SizedBox(height: 8),
            _SecurityTile(
              icon: Icons.key_outlined,
              iconColor: AppDesignSystem.primaryLight,
              title: 'Enroll a passkey',
              description: passkeySupported
                  ? 'Passwordless, phishing-resistant login from this device.'
                  : 'Passkeys need macOS, Windows, Android, or a browser. '
                      'This device doesn\'t support them yet.',
              enabled: passkeySupported,
              onTap: passkeySupported
                  ? () => Navigator.of(context).pop(
                        PostRegistrationSecurityChoice.enrollPasskey,
                      )
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(PostRegistrationSecurityChoice.skip),
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

/// A single selectable security option inside the prompt dialog.
///
/// Visually a [Card]-style tappable row with an icon + title + description.
/// When [enabled] is `false`, the tile is greyed out, the tap handler is
/// dropped, and the description text is replaced by the platform-specific
/// explanation supplied by the caller.
class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledColor = theme.disabledColor;
    final titleColor = enabled
        ? theme.colorScheme.onSurface
        : disabledColor;
    final descriptionColor = enabled
        ? AppDesignSystem.neutral600
        : disabledColor;
    final effectiveIconColor = enabled ? iconColor : disabledColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: effectiveIconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppDesignSystem.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppDesignSystem.bodySmall.copyWith(
                        color: descriptionColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
