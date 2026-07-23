import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/example_dapps.dart';
import '../services/script_runner.dart';
import '../services/service_locator.dart';
import '../theme/app_design_system.dart';
import 'dapp_runner_screen.dart';
import 'scaffolded_frontend_screen.dart';
import '../widgets/frontend_scaffold_dialog.dart';

/// The Dapps catalog tab. Lists every shipped example dapp as a tappable card;
/// tapping one opens [DappRunnerScreen] (Path B: backend direct).
///
/// Header explains what Dapps are in one line (mirrors the BookmarksScreen
/// subtitle pattern so the tab label and screen header stay consistent).
class DappsScreen extends StatelessWidget {
  const DappsScreen({super.key, this.testBridge});

  /// Test-only canister-bridge override forwarded to the pushed
  /// [DappRunnerScreen.testBridge] so the headline e2e flow test
  /// (`integration_test/ux_probe/f_dapp_vote_flow_test.dart`) can drive the full
  /// catalog→runner→trust→vote→revoke loop with canned canister responses
  /// through a real `app.main()` boot. Production leaves this null and the
  /// runner uses the real FFI bridge. Mirrors [DappRunnerScreen.testBridge].
  @visibleForTesting
  final ScriptBridge? testBridge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Constructor param wins (direct unit-test injection); else the process-wide
    // service-locator override (integration-test boot via app.main). Both null
    // in production → the runner builds its own real FFI bridge.
    final ScriptBridge? bridge = testBridge ?? scriptBridgeOverride;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Dapps'),
            SizedBox(height: 2),
            Text(
              'Live Internet Computer apps — talk to the backend directly or '
              'open the frontend.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scaffold frontend from canister',
            icon: const Icon(Icons.auto_fix_high_rounded),
            onPressed: () => _openScaffoldDialog(context, bridge),
          ),
          const SizedBox(width: AppDesignSystem.spacing4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.primaryContainer.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: exampleDapps.isEmpty
              ? const _EmptyDapps()
              : ListView.separated(
                  padding: const EdgeInsets.all(AppDesignSystem.spacing16),
                  itemCount: exampleDapps.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppDesignSystem.spacing12),
                  itemBuilder: (context, i) => _DappCard(
                    descriptor: exampleDapps[i],
                    testBridge: bridge,
                  ),
                ),
        ),
      ),
    );
  }

  /// Opens the "Scaffold frontend from canister" dialog (Phase 1). On a
  /// successful generation, pushes [ScaffoldedFrontendScreen] with the bundle
  /// + connection values so the user immediately runs the generated UI.
  Future<void> _openScaffoldDialog(
      BuildContext context, ScriptBridge? testBridge) async {
    final FrontendScaffoldResult? result = await showDialog<FrontendScaffoldResult>(
      context: context,
      builder: (_) => const FrontendScaffoldDialog(),
    );
    if (result == null) return;
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ScaffoldedFrontendScreen(
        title: 'Scaffolded · ${result.canisterId}',
        bundle: result.bundle,
        canisterId: result.canisterId,
        host: result.host,
        testBridge: testBridge,
      ),
    ));
  }
}

class _EmptyDapps extends StatelessWidget {
  const _EmptyDapps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.spacing32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apps_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppDesignSystem.spacing12),
            Text('No example dapps yet', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _DappCard extends StatelessWidget {
  const _DappCard({required this.descriptor, this.testBridge});
  final DappDescriptor descriptor;
  // Forwarded to DappRunnerScreen so the catalog→runner push honors the
  // DappsScreen test seam (constructor param or service-locator override).
  final ScriptBridge? testBridge;

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DappRunnerScreen(
        descriptor: descriptor,
        testBridge: testBridge,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // W6-10 (b): the ENTIRE card used to be one giant button with a huge
    // concatenated label (title + description + every badge merged together)
    // so sub-actions weren't individually focusable. Now the primary "Open"
    // action is a clean `Semantics(button:)` node labelled only with the
    // title; the description and each path badge live in their OWN containers
    // so screen-reader users can focus them individually. The whole card stays
    // tappable (InkWell) for mouse/touch + keyboard (`_KeyboardActivable`).
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _KeyboardActivable(
        onActivate: () => _open(context),
        child: Semantics(
          button: true,
          container: true,
          label: 'Open ${descriptor.title}',
          child: InkWell(
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.all(AppDesignSystem.spacing16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Decorative emoji — exclude from semantics (the title is
                  // already in the button label above).
                  ExcludeSemantics(child: _DappEmoji(emoji: descriptor.emoji)),
                  const SizedBox(width: AppDesignSystem.spacing16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title already announced via the button label.
                        ExcludeSemantics(
                          child: Text(
                            descriptor.title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.spacing4),
                        // Description = its own focusable node.
                        Semantics(
                          container: true,
                          child: Text(
                            descriptor.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.spacing12),
                        // Each path/environment badge = its own focusable
                        // node so they're announced individually (W6-10 b).
                        Wrap(
                          spacing: AppDesignSystem.spacing8,
                          runSpacing: AppDesignSystem.spacing4,
                          children: [
                            Semantics(
                              container: true,
                              child:
                                  _EnvironmentBadge(descriptor: descriptor),
                            ),
                            if (descriptor.hasBackendDirect)
                              Semantics(
                                container: true,
                                child: _PathBadge(
                                  icon: Icons.cable_rounded,
                                  label: 'Backend direct',
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            if (descriptor.hasFrontendBrowser)
                              Semantics(
                                container: true,
                                child: _PathBadge(
                                  icon: Icons.open_in_new_rounded,
                                  label: 'Frontend in browser',
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DappEmoji extends StatelessWidget {
  const _DappEmoji({required this.emoji});
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    );
  }
}

class _PathBadge extends StatelessWidget {
  const _PathBadge({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing8,
        vertical: AppDesignSystem.spacing4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Distinguishes a real-mainnet example ("Works now") from a local-replica
/// developer example ("Local replica"). Makes the catalog HONEST at a glance —
/// a user instantly sees which examples need their own replica vs which work the
/// moment they tap in. (UXR-6: never ship a silently-dead tab.)
class _EnvironmentBadge extends StatelessWidget {
  const _EnvironmentBadge({required this.descriptor});
  final DappDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final bool mainnet = descriptor.isMainnet;
    final Color color = mainnet
        ? AppDesignSystem.successColor
        : AppDesignSystem.warningColor;
    return _PathBadge(
      icon: mainnet ? Icons.cloud_done_rounded : Icons.developer_mode_rounded,
      label: mainnet ? 'Works now · Mainnet' : 'Local replica',
      color: color,
    );
  }
}

/// Wraps a child in a focusable node that activates on Enter / Space (in
/// addition to mouse/touch via [InkWell]). Kept as a small local widget so a
/// card is operable from the keyboard alone — premium desktop UX.
class _KeyboardActivable extends StatelessWidget {
  const _KeyboardActivable({required this.onActivate, required this.child});
  final VoidCallback onActivate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
