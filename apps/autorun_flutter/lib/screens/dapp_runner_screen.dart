import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/example_dapps.dart';
import '../models/profile_keypair.dart';
import '../rust/native_bridge.dart';
import '../services/script_runner.dart';
import '../theme/app_design_system.dart';
import '../widgets/profile_scope.dart';
import '../widgets/script_app_host.dart';

/// Runs ONE example dapp via Path B (Backend Direct): mounts [ScriptAppHost]
/// with the dapp's bundled TS app, pointing at the (editable) backend canister
/// + replica host. Authenticated effects sign as the active profile keypair;
/// with no profile the bundle runs view-only.
///
/// Path A (open the hosted frontend in the system browser) is a secondary
/// action in the app bar.
class DappRunnerScreen extends StatefulWidget {
  const DappRunnerScreen({
    super.key,
    required this.descriptor,
    this.testRuntime,
    this.testBundle,
  });

  final DappDescriptor descriptor;

  /// Test-only runtime override. Production leaves this null and the runner
  /// builds the real FFI-backed [ScriptAppRuntime]. Tests inject a fake to
  /// assert the [ScriptAppHost] is mounted with the correct `initialArg`
  /// without executing the bundle or touching the network.
  @visibleForTesting
  final IScriptAppRuntime? testRuntime;

  /// Test-only bundle-string override so widget tests don't depend on
  /// [rootBundle] / FFI. Production leaves this null and the runner loads the
  /// bundle from [DappDescriptor.bundleAssetPath].
  @visibleForTesting
  final String? testBundle;

  @override
  State<DappRunnerScreen> createState() => _DappRunnerScreenState();
}

class _DappRunnerScreenState extends State<DappRunnerScreen> {
  late final IScriptAppRuntime _runtime;
  late final TextEditingController _backendIdController;
  late final TextEditingController _hostController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Effective connection values currently driving the [ScriptAppHost].
  String _backendId = '';
  String _host = '';

  /// The bundled TS app source. Null until [rootBundle] resolves; an empty
  /// never-null sentinel is avoided on purpose so the host never mounts with a
  /// missing bundle.
  String? _bundle;
  bool _bundleLoadFailed = false;

  /// Bumped on every successful Apply → changes the [ScriptAppHost] key so the
  /// host is rebuilt and the bundle re-runs init with the new `initialArg`.
  int _hostGeneration = 0;

  @override
  void initState() {
    super.initState();
    _runtime = widget.testRuntime ??
        ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
    _backendIdController = TextEditingController();
    _hostController = TextEditingController();
    _loadInitialConfig();
    _loadBundle();
  }

  @override
  void dispose() {
    _backendIdController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialConfig() async {
    final cfg = await DappRuntimeConfig.load(widget.descriptor);
    if (!mounted) return;
    setState(() {
      _backendId = cfg.backendCanisterId;
      _host = cfg.host;
      _backendIdController.text = cfg.backendCanisterId;
      _hostController.text = cfg.host;
    });
  }

  Future<void> _loadBundle() async {
    if (widget.testBundle != null) {
      if (!mounted) return;
      setState(() => _bundle = widget.testBundle);
      return;
    }
    try {
      final src =
          await rootBundle.loadString(widget.descriptor.bundleAssetPath);
      if (!mounted) return;
      if (src.isEmpty) {
        // An empty shipped asset is a packaging bug — surface it loudly.
        setState(() => _bundleLoadFailed = true);
        return;
      }
      setState(() => _bundle = src);
    } catch (e, st) {
      debugPrint('dapp_runner: bundle load failed: $e\n$st');
      if (!mounted) return;
      setState(() => _bundleLoadFailed = true);
    }
  }

  Future<void> _applyConfig() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final newId = _backendIdController.text.trim();
    final newHost = _hostController.text.trim();
    await DappRuntimeConfig.save(
      widget.descriptor.id,
      backendCanisterId: newId,
      host: newHost,
    );
    if (!mounted) return;
    setState(() {
      _backendId = newId;
      _host = newHost;
      _hostGeneration++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      AppDesignSystem.successSnackBar('Connection updated — dapp restarted'),
    );
  }

  Future<void> _openFrontend() async {
    final uri = Uri.parse(widget.descriptor.frontendUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showLoudError(
            'Could not open the browser for\n${widget.descriptor.frontendUrl}');
      }
    } catch (e, st) {
      debugPrint('dapp_runner: url_launcher failed: $e\n$st');
      if (mounted) {
        _showLoudError('Failed to open browser: $e');
      }
    }
  }

  void _showLoudError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _shortenPrincipal(String p) {
    if (p.length <= 20) return p;
    return '${p.substring(0, 14)}…${p.substring(p.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ProfileKeypair? keypair = ProfileScope.of(context).activeKeypair;
    final String? principal = keypair?.principal;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.descriptor.emoji} ${widget.descriptor.title}'),
        actions: [
          if (widget.descriptor.hasFrontendBrowser)
            IconButton(
              tooltip: 'Open frontend in browser',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: _openFrontend,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        // The body scrolls as a whole. The host is given a fixed generous
        // height derived from the FULL screen (not keyboard viewInsets) so the
        // on-screen keyboard can never squeeze it below its content — that
        // would overflow the host's internal progress indicator.
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildConnectionPanel(theme)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppDesignSystem.spacing12,
                    AppDesignSystem.spacing12,
                    AppDesignSystem.spacing12,
                    AppDesignSystem.spacing4),
                child: _buildAuthStatus(theme,
                    hasProfile: keypair != null, principal: principal),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: _hostHeight(context),
                width: double.infinity,
                child: _buildHostArea(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A generous, keyboard-independent height for the dapp host region. Based
  /// on the full screen so the host is never squeezed by the on-screen
  /// keyboard; the surrounding scroll view reveals what doesn't fit.
  double _hostHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.58;
    if (h < 300) return 300;
    if (h > 1000) return 1000;
    return h;
  }

  Widget _buildConnectionPanel(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.fromLTRB(
          AppDesignSystem.spacing12, AppDesignSystem.spacing12, 12, 0),
      child: Form(
        key: _formKey,
        child: ExpansionTile(
          key: const ValueKey<String>('dappConnectionPanel'),
          initiallyExpanded: false,
          leading: const Icon(Icons.cable_rounded),
          title: const Text('Connection'),
          subtitle: Text(
            _backendId.isEmpty
                ? 'Loading saved connection…'
                : '$_backendId · $_host',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppDesignSystem.spacing16, 0, AppDesignSystem.spacing16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('dappBackendIdField'),
                    controller: _backendIdController,
                    decoration: InputDecoration(
                      labelText: 'Backend canister id',
                      hintText: 'e.g. $kLocalPollBackendCanisterId',
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Canister id is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppDesignSystem.spacing12),
                  TextFormField(
                    key: const Key('dappHostField'),
                    controller: _hostController,
                    decoration: InputDecoration(
                      labelText: 'Replica host',
                      hintText: 'e.g. $kLocalPollHost',
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Host is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppDesignSystem.spacing12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _applyConfig,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthStatus(ThemeData theme,
      {required bool hasProfile, String? principal}) {
    if (hasProfile) {
      final label = (principal == null || principal.isEmpty)
          ? 'Signed in with the active profile'
          : 'Signed as: ${_shortenPrincipal(principal)}';
      return _StatusChip(
        icon: Icons.verified_user_outlined,
        text: label,
        color: AppDesignSystem.successColor,
        background: AppDesignSystem.successColor,
      );
    }
    return _StatusChip(
      icon: Icons.warning_amber_rounded,
      text: 'No active profile — create/vote disabled (view-only)',
      hint: 'Open the profile menu (top-right) to create or switch a profile.',
      color: AppDesignSystem.warningColor,
      background: AppDesignSystem.warningColor,
    );
  }

  Widget _buildHostArea(ThemeData theme) {
    if (_bundleLoadFailed) {
      return _CenteredMessage(
        icon: Icons.error_outline_rounded,
        color: theme.colorScheme.error,
        title: 'Could not load the dapp bundle',
        detail:
            'Asset "${widget.descriptor.bundleAssetPath}" is missing or empty. '
            'This is a packaging bug — please report it.',
      );
    }
    // Wait for both the bundle source and the effective config before mounting
    // the host, so init always runs with a real backend_id + host.
    if (_bundle == null || _backendId.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ScriptAppHost(
      key: ValueKey<int>(_hostGeneration),
      runtime: _runtime,
      script: _bundle!,
      initialArg: <String, dynamic>{
        'backend_id': _backendId,
        'host': _host,
      },
      authenticatedKeypair: ProfileScope.of(context).activeKeypair,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
    this.hint,
  });
  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing12,
        vertical: AppDesignSystem.spacing8,
      ),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
        border: Border.all(color: background.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppDesignSystem.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600, color: color)),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.spacing24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: AppDesignSystem.spacing12),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: color)),
            const SizedBox(height: AppDesignSystem.spacing8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
