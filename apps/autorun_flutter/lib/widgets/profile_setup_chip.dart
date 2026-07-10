import 'package:flutter/material.dart';

/// Persistent, non-blocking "complete your profile" affordance shown in the app
/// shell whenever the user has no profile yet (IH-9 / UXR-8).
///
/// A brand-new user who dismisses the first-run wizard without creating a
/// profile would otherwise land in a "Guest" limbo with no obvious path back to
/// profile creation — the empty-state CTA is off-screen as soon as the user has
/// any content, and the wizard would force-reappear on every restart. This chip
/// fixes both halves of that: it lives in the always-visible top-right affordance
/// cluster (so it is reachable on every tab regardless of content), and tapping
/// it re-opens the [UnifiedSetupWizard]. The first-run gate separately remembers
/// a deliberate dismissal so the wizard never loops on restart.
///
/// Browsing the marketplace as a guest is unaffected — the chip never blocks the
/// content below it.
class ProfileSetupChip extends StatelessWidget {
  const ProfileSetupChip({super.key, required this.onSetUp});

  /// Re-opens profile setup (the [UnifiedSetupWizard]).
  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      key: const Key('profileSetupChip'),
      onPressed: onSetUp,
      icon: const Icon(Icons.person_add_outlined, size: 18),
      label: const Text('Set up profile'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
