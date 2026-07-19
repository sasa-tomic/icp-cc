import 'package:flutter/material.dart';

/// UX-H1 trust badges.
///
/// The product promise is *signed + sandboxed* scripts. These chips surface
/// that promise at the three decision moments:
///   - browse tile subtitle (`SandboxedChip` + `SignedByChip`)
///   - details dialog header (`SignedByChip(verified: true)` + `SignatureVerifiedChip`)
///   - run-panel header (status row assembled by the caller)
///
/// All chips are theme-driven so they render correctly in light AND dark
/// modes. DRY: defined once here, used everywhere scripts are surfaced.
///
/// Style intent:
///   - Sandboxed → reassuring green tint (the runtime guarantee).
///   - Signed / Verified → primary tint (the identity guarantee).
///   - Signature verified → success-tinted, emphasises the check itself.

/// "Sandboxed ✓" — always shown for any script (the QuickJS runtime guarantee
/// is universal). Green-tinted to read as a safety signal.
class SandboxedChip extends StatelessWidget {
  const SandboxedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _TrustChip(
      icon: Icons.shield_outlined,
      label: 'Sandboxed',
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
    );
  }
}

/// "Signed by {author}" — shown when author info is present. When the author
/// is a verified developer, an inline verified badge is appended so the user
/// can distinguish marketplace-blessed authors from arbitrary publishers at a
/// glance.
class SignedByChip extends StatelessWidget {
  const SignedByChip({
    required this.author,
    this.verified = false,
    super.key,
  });

  final String author;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _TrustChip(
      icon: Icons.draw_outlined,
      label: 'Signed by $author',
      trailing: verified
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.verified_user_outlined, size: 14, color: colors.primary),
            )
          : null,
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
    );
  }
}

/// "Signature verified ✓" — shown when the script's `uploadSignature` has
/// been checked against the author's public key. Success-tinted to emphasise
/// the verification itself (not just the presence of a signature).
class SignatureVerifiedChip extends StatelessWidget {
  const SignatureVerifiedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _TrustChip(
      icon: Icons.check_circle_outline,
      label: 'Signature verified',
      backgroundColor: colors.tertiaryContainer,
      foregroundColor: colors.onTertiaryContainer,
    );
  }
}

/// Internal chip skeleton — Material `Chip` would force a fixed look; a
/// custom container keeps the badge compact (no fat Material padding) and
/// lets each public chip swap colors/icons while sharing layout + a11y.
class _TrustChip extends StatelessWidget {
  const _TrustChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
