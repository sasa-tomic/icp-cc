import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/example_dapps.dart';
import '../controllers/account_controller.dart';
import '../models/profile_keypair.dart';
import '../rust/native_bridge.dart';
import '../services/script_runner.dart';
import '../services/secure_storage_readiness.dart';
import '../theme/app_design_system.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/profile_scope.dart';
import '../widgets/script_app_host.dart';
import 'unified_setup_wizard.dart';

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
    this.testSecureStorageReadiness,
    this.testBridge,
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

  /// Test-only override for the [SecureStorageReadiness] the deep-linked
  /// [UnifiedSetupWizard] probes. Production leaves this null and the runner
  /// constructs the real probe; tests inject a fixed result so the navigation
  /// test stays hermetic (the real probe would shell out to gnome-keyring-daemon
  /// on a Linux host). Mirrors the wizard's own `secureStorageReadiness` seam.
  @visibleForTesting
  final SecureStorageReadiness? testSecureStorageReadiness;

  /// Test-only canister-bridge override forwarded to [ScriptAppHost.testBridge]
  /// so widget tests can simulate a reachability failure (UX-12(b)) without
  /// touching the network or the real FFI. Production leaves this null.
  @visibleForTesting
  final ScriptBridge? testBridge;

  @override
  State<DappRunnerScreen> createState() => _DappRunnerScreenState();
}

class _DappRunnerScreenState extends State<DappRunnerScreen> {
  late final IScriptAppRuntime _runtime;
  late final TextEditingController _backendIdController;
  late final TextEditingController _hostController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // ─────────────────────────────────────────────────────────────────────────
  // Single source of truth for the keyless-user CTA copy. Pedagogically frames
  // HUMAN_EXPECTATIONS §3: browse anonymously, act with identity. Every label on
  // this screen that mentions the keyless state or the create-profile action
  // references these symbolic names — never re-spell the literals inline.
  //
  // W6-1 Bug 3: the copy is DAPP-AGNOSTIC (no poll-specific "vote" language).
  // A dapp MAY override the hint via [DappDescriptor.keylessHint]; otherwise
  // this generic default is used so unrelated dapps (e.g. the ICP Ledger)
  // don't show misleading "vote"/"polls" text.
  // ─────────────────────────────────────────────────────────────────────────
  static const String _kKeylessStatusText =
      'No active profile — viewing only';
  static const String _kKeylessStatusHintDefault =
      "You're browsing anonymously. Creating a profile lets you take signed "
      'actions.';
  static const String _kCreateProfileLabel = 'Create a profile';
  static const String _kUnreachableHintTitle = 'Canister unreachable';
  static const String _kUnreachableHintBody =
      'The dapp couldn\'t reach the canister at the configured id/host. '
      'Check the canister id and host below, then Apply.';
  static const String _kLocalReplicaBannerTitle =
      'Developer example — needs a local replica';
  static const String _kLocalReplicaBannerBody =
      'This dapp runs against a replica you start yourself. Bring it up with: '
      '`cd examples/icp_poll_dapp && dfx start --clean && dfx deploy`, then '
      'copy the printed backend canister id into Connection below. (Until then '
      'the canister is unreachable — that\'s expected.)';
  // Environment-aware Connection panel one-liners. The dfx setup commands live
  // ONLY in the local-replica banner (DRY); this panel hint explains how to use
  // the editable fields below — generic for mainnet (works as-is), tailored for
  // a local replica (ids change across replica restarts).
  static const String _kConnectionHintMainnet =
      'The defaults point at the real mainnet canister — no change needed. '
      'Edit below only to point at a different network.';
  static const String _kConnectionHintLocalReplica =
      'Replica restarts regenerate canister ids. If the dapp can\'t connect, '
      'paste the new id from your latest deploy output and Apply.';

  /// Effective connection values currently driving the [ScriptAppHost].
  String _backendId = '';
  String _host = '';

  /// The bundled TS app source. Null until [rootBundle] resolves; an empty
  /// never-null sentinel is avoided on purpose so the host never mounts with a
  /// missing bundle.
  String? _bundle;
  bool _bundleLoadFailed = false;

  /// Live mirror of the current dapp's "Trust this dapp?" grant. Pre-seeded
  /// from [DappTrustStore] in [_loadTrustState] (so the indicator is correct
  /// even before the host boots), then kept in sync by the mounted
  /// [ScriptAppHost] via its `dappTrustState` parameter (load / grant / revoke
  /// all publish here). Drives the "Trusted" status chip and the manage-trust
  /// dialog copy. UX-10 completeness: makes the broad grant VISIBLE and gives
  /// the user a one-tap revoke.
  final ValueNotifier<bool> _trustState = ValueNotifier<bool>(false);

  /// Identifies the currently-mounted [ScriptAppHost]. Reassigning the field
  /// (via setState in [_applyConfig] / [_refreshDapp]) forces a fresh
  /// [ScriptAppHostState] → init re-runs with the new initialArg. Stable
  /// across non-remount rebuilds so [_revokeTrust] can reach into
  /// `currentState` and flip the in-memory trust flag WITHOUT remounting
  /// (preserving the dapp's JS state — the next canister call re-prompts).
  GlobalKey<ScriptAppHostState>? _hostKey;

  // ─────────────────────────────────────────────────────────────────────────
  // UX-12(b): reactive Connection-panel auto-expand. When the FIRST canister
  // call fails reachability (e.g. a stale id after `dfx start --clean`, or a
  // dead replica host), the panel auto-expands so the recovery hint + fields
  // are immediately visible — instead of leaving the panel collapsed and
  // hiding the fix. Driven by the typed [CanisterFailureKind] signal emitted
  // from the Rust FFI (match-style, not message string-matching).
  // ─────────────────────────────────────────────────────────────────────────
  final ExpansibleController _connectionController =
      ExpansibleController();

  /// True once a reachability failure has auto-expanded the panel + surfaced
  /// the "Canister unreachable" hint. Latched per host-mount: cleared whenever
  /// the host remounts (Apply / Refresh) so a fresh connection attempt starts
  /// from the clean, collapsed happy-path state.
  bool _showUnreachableHint = false;

  @override
  void initState() {
    super.initState();
    _runtime = widget.testRuntime ??
        ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
    _backendIdController = TextEditingController();
    _hostController = TextEditingController();
    _loadInitialConfig();
    _loadBundle();
    _loadTrustState();
  }

  @override
  void dispose() {
    _trustState.dispose();
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
      _hostKey = GlobalKey<ScriptAppHostState>(); // fresh State → init re-runs.
      _showUnreachableHint = false; // new connection attempt → clean slate.
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

  /// Copies the active profile's [principal] to the clipboard and confirms
  /// with a SnackBar (W7-19: dapp-runner auth chip now matches the Account
  /// screen's copyable principal).
  void _copyPrincipal(String principal) {
    Clipboard.setData(ClipboardData(text: principal));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      AppDesignSystem.successSnackBar('Principal copied to clipboard'),
    );
  }

  /// UX-9: remounts the [ScriptAppHost] (re-runs `init` → fresh polls/dapp
  /// state) without touching the saved connection. Bound to `R`.
  void _refreshDapp() {
    // Nothing to refresh until the bundle + connection are loaded — silently
    // no-op rather than bumping a generation that re-shows the spinner with
    // no source to mount.
    if (_bundle == null || _backendId.isEmpty) return;
    setState(() {
      _hostKey = GlobalKey<ScriptAppHostState>();
      _showUnreachableHint = false; // remount → re-evaluate from a clean state.
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar('Dapp refreshed'),
      );
    }
  }

  /// UX-9: bound to `Esc`. Pops the runner back to the catalog.
  void _handleBack() {
    Navigator.of(context).maybePop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Honest empty-state for local-replica examples (UXR-6). The Poll dapp needs
  // a replica the USER starts; without one the tab is non-functional. This
  // banner states that requirement up front — and the exact commands to bring
  // it up — instead of letting a first-time user stare at a "Canister
  // unreachable" error with no context. The runner's existing UX-12(b)
  // auto-expand still fires on an actual reachability failure.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLocalReplicaBanner(ThemeData theme) {
    final Color warn = AppDesignSystem.warningColor;
    return Container(
      key: const ValueKey<String>('dappLocalReplicaBanner'),
      margin: const EdgeInsets.fromLTRB(
          AppDesignSystem.spacing12, AppDesignSystem.spacing12, 12, 0),
      padding: const EdgeInsets.all(AppDesignSystem.spacing12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
        border: Border.all(color: warn.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.construction_rounded, color: warn, size: 20),
          const SizedBox(width: AppDesignSystem.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _kLocalReplicaBannerTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: warn),
                ),
                const SizedBox(height: 2),
                Text(
                  _kLocalReplicaBannerBody,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UX-12(b): reactive Connection-panel auto-expand on canister-unreachable.
  // ─────────────────────────────────────────────────────────────────────────

  /// Called by [ScriptAppHost] whenever a canister bridge call fails, with the
  /// failure classified by the typed [CanisterFailureKind] (match-style on the
  /// Rust FFI `kind` tag — never message string-matching). On the FIRST
  /// reachability failure ([CanisterFailureKind.isUnreachable]) this expands
  /// the Connection panel and shows the recovery hint, so the user lands on the
  /// fix instead of a collapsed panel hiding it. Non-reachability failures
  /// (Candid decode) and repeat reachability failures are ignored here — the
  /// panel only needs to open once per host-mount.
  void _onCanisterFailure(CanisterCallFailure failure) {
    if (!failure.kind.isUnreachable) return;
    if (!mounted) return;
    // Expand first (idempotent on an already-open tile), then latch the hint.
    _connectionController.expand();
    if (_showUnreachableHint) return;
    setState(() => _showUnreachableHint = true);
    debugPrint(
        'dapp_runner: canister unreachable — auto-expanded Connection panel '
        '(kind=${failure.kind.name}, error=${failure.error})');
  }

  /// The honest, non-alarmist hint shown at the top of the (now-expanded)
  /// Connection panel after a reachability failure. Uses warning amber, not
  /// error red, and points the user straight at the fields below — it names
  /// the symptom and the action, never panics.
  Widget _buildUnreachableHint(ThemeData theme) {
    final Color warn = AppDesignSystem.warningColor;
    return Container(
      key: const ValueKey<String>('dappUnreachableHint'),
      margin: const EdgeInsets.fromLTRB(
          AppDesignSystem.spacing16, AppDesignSystem.spacing8, 12, 0),
      padding: const EdgeInsets.all(AppDesignSystem.spacing12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
        border: Border.all(color: warn.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, color: warn, size: 20),
          const SizedBox(width: AppDesignSystem.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _kUnreachableHintTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: warn),
                ),
                const SizedBox(height: 2),
                Text(
                  _kUnreachableHintBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UX-10 completeness: trust-state visibility + revoke affordance.
  //
  // `DappTrustStore.setTrusted` was already wired (the host's "Trust this dapp?"
  // prompt), but `clear` had NO UI — a user who'd granted the broad allow-list
  // had no way to revoke it. The flow below closes that gap:
  //   - on boot, [_loadTrustState] reads the persisted grant so the indicator
  //     is correct before the host finishes mounting;
  //   - the host writes back to [_trustState] on load/grant/revoke via its
  //     `dappTrustState` notifier;
  //   - the "Manage trust" toolbar button opens a dialog that mirrors state
  //     and offers Revoke (with an explicit confirmation, since revocation
  //     resets the broad grant).
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadTrustState() async {
    try {
      final trusted = await DappTrustStore.isTrusted(widget.descriptor.id);
      if (!mounted) return;
      _trustState.value = trusted;
    } catch (e, st) {
      // Loud but non-fatal: leave the notifier at its safe default (false);
      // the host's own load will retry on mount.
      debugPrint('dapp_runner: trust-state load failed: $e\n$st');
    }
  }

  /// Opens the "Manage dapp trust" dialog. Mirrors the live [_trustState] so
  /// the body copy matches reality, and offers Revoke only when trusted.
  Future<void> _showManageTrustDialog() async {
    final bool trusted = _trustState.value;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(_kManageTrustDialogTitle),
          content: SingleChildScrollView(
            child: Text(trusted
                ? _kManageTrustTrustedBody
                : _kManageTrustNotTrustedBody),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(_kManageTrustCloseButton),
            ),
            if (trusted)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _confirmRevokeTrust();
                },
                icon: const Icon(Icons.remove_circle_outline_rounded),
                label: const Text(_kRevokeTrustButton),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignSystem.errorColor,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Explicit yes/no confirmation for revocation (the grant is broad, so a
  /// single accidental tap on the red button must not silently undo it).
  /// Cancel → no state change; Revoke → [_doRevokeTrust].
  Future<void> _confirmRevokeTrust() async {
    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(_kConfirmRevokeTitle),
          content: const SingleChildScrollView(
            child: Text(_kConfirmRevokeBody),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(_kConfirmRevokeCancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignSystem.errorColor,
              ),
              child: const Text(_kRevokeTrustButton),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _doRevokeTrust();
    }
  }

  /// Performs the revocation by calling the mounted host's `revokeTrust`,
  /// which clears [DappTrustStore] AND flips the in-memory trust flag (so the
  /// next canister call re-prompts) AND publishes `false` to [_trustState].
  /// Falls back to clearing the store directly when the host isn't mounted
  /// yet (e.g. bundle still loading) — the next mount will load trust=false.
  /// Errors surface LOUDLY: there is no silent fallback path.
  Future<void> _doRevokeTrust() async {
    final host = _hostKey?.currentState;
    try {
      if (host != null) {
        await host.revokeTrust();
      } else {
        await DappTrustStore.clear(widget.descriptor.id);
        _trustState.value = false;
      }
    } catch (e, st) {
      debugPrint('dapp_runner: revokeTrust failed: $e\n$st');
      if (mounted) {
        _showLoudError('Failed to revoke trust: $e');
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      AppDesignSystem.successSnackBar(_kTrustRevokedMessage),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Keyless-user CTA (HUMAN_EXPECTATIONS §3: teach the dual-path model — browse
  // anonymously, act with identity). The dapp runs view-only without a profile;
  // this gives a keyless user a one-tap path into the profile-creation wizard
  // so they can take signed actions, instead of hunting the profile menu.
  // ─────────────────────────────────────────────────────────────────────────

  /// Deep-links a keyless user into the [UnifiedSetupWizard] so they can create
  /// a profile in one tap and take signed actions. Mirrors the re-open-wizard
  /// path in `scripts_screen.dart` without introducing a circular import on the
  /// app entry point.
  ///
  /// The wizard itself probes [SecureStorageReadiness] (WU-S2 / AGENTS.md) and
  /// renders an actionable panel if secrets can't be persisted — that handling
  /// is intentionally NOT duplicated here. After the wizard pops, this screen
  /// rebuilds via [ProfileScope] (listen: true in [build]) and the CTA
  /// disappears because `activeKeypair` is now non-null.
  Future<void> _openCreateProfileWizard() async {
    final profileController = ProfileScope.of(context, listen: false);
    final accountController =
        AccountController(profileController: profileController);
    await Navigator.of(context).push<UnifiedSetupResult>(
      MaterialPageRoute<UnifiedSetupResult>(
        fullscreenDialog: true,
        builder: (_) => UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness:
              widget.testSecureStorageReadiness ?? SecureStorageReadiness(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ProfileKeypair? keypair = ProfileScope.of(context).activeKeypair;
    final String? principal = keypair?.principal;

    return ScreenShortcuts(
      onRefresh: _refreshDapp,
      onBack: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.descriptor.emoji} ${widget.descriptor.title}'),
          actions: [
            ShortcutTooltip(
              label: 'Refresh dapp',
              shortcut: DesktopShortcuts.getShortcutLabel('dapp_refresh'),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refreshDapp,
              ),
            ),
            if (widget.descriptor.hasFrontendBrowser)
              IconButton(
                tooltip: 'Open frontend in browser',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: _openFrontend,
              ),
            // UX-10 completeness: the only entry point for revoking the broad
            // per-dapp trust grant. Always present (even when not trusted) so
            // a user can inspect the state at any time. The "Trusted" status
            // chip below the app bar reinforces the indicator.
            IconButton(
              tooltip: _kManageTrustTooltip,
              icon: const Icon(Icons.shield_outlined),
              onPressed: _showManageTrustDialog,
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
              if (widget.descriptor.isLocalReplica)
                SliverToBoxAdapter(child: _buildLocalReplicaBanner(theme)),
              SliverToBoxAdapter(child: _buildConnectionPanel(theme)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppDesignSystem.spacing12,
                      AppDesignSystem.spacing12,
                      AppDesignSystem.spacing12,
                      AppDesignSystem.spacing4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildAuthStatus(
                          hasProfile: keypair != null, principal: principal),
                      _buildTrustStatus(),
                    ],
                  ),
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
          controller: _connectionController,
          initiallyExpanded: false,
          leading: const Icon(Icons.cable_rounded),
          title: const Text('Connection'),
          subtitle: Text(
            _backendId.isEmpty
                ? 'Reading saved connection…'
                : '$_backendId · $_host',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            if (_showUnreachableHint) _buildUnreachableHint(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppDesignSystem.spacing16, 0, AppDesignSystem.spacing16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppDesignSystem.spacing8),
                      Expanded(
                        child: Text(
                          widget.descriptor.isLocalReplica
                              ? _kConnectionHintLocalReplica
                              : _kConnectionHintMainnet,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignSystem.spacing16),
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

  Widget _buildAuthStatus({required bool hasProfile, String? principal}) {
    if (hasProfile) {
      final hasPrincipal = principal != null && principal.isNotEmpty;
      // W7-19: show the FULL principal (monospace, wraps) and make it
      // tap-to-copy, so the dapp-runner chip matches the Account screen's
      // copyable principal instead of a dead, clipped "qtjow-…-cae" string.
      return _StatusChip(
        icon: Icons.verified_user_outlined,
        text: hasPrincipal ? 'Signed as: $principal' : 'Signed in with the active profile',
        color: AppDesignSystem.successColor,
        monospace: hasPrincipal,
        onTap: hasPrincipal ? () => _copyPrincipal(principal) : null,
      );
    }
    // Keyless user: show the view-only status (teaches the dual-path model)
    // PLUS a prominent one-tap CTA into the profile-creation wizard. The chip
    // explains "what is"; the button is the "do this" path to signed actions.
    // The hint prefers the dapp's own [DappDescriptor.keylessHint] when set,
    // otherwise the dapp-agnostic default (W6-1 Bug 3).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(
          icon: Icons.warning_amber_rounded,
          text: _kKeylessStatusText,
          hint: widget.descriptor.keylessHint ?? _kKeylessStatusHintDefault,
          color: AppDesignSystem.warningColor,
        ),
        const SizedBox(height: AppDesignSystem.spacing8),
        FilledButton.icon(
          key: const Key('dappCreateProfileToVoteCta'),
          onPressed: _openCreateProfileWizard,
          icon: const Icon(Icons.person_add_rounded),
          label: const Text(_kCreateProfileLabel),
        ),
      ],
    );
  }

  /// UX-10 visibility: surfaces the broad per-dapp "Trust this dapp?" grant as
  /// a success-coloured "Trusted" chip while it is active, so the user never
  /// wonders "did I trust this?". Hidden when not trusted (the absence + the
  /// next prompt answers the same question). The hint directs the user to the
  /// toolbar shield to revoke.
  Widget _buildTrustStatus() {
    return ValueListenableBuilder<bool>(
      valueListenable: _trustState,
      builder: (BuildContext context, bool trusted, Widget? _) {
        if (!trusted) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppDesignSystem.spacing8),
          child: _StatusChip(
            icon: Icons.verified_user_rounded,
            text: _kTrustedChipLabel,
            hint: _kTrustedChipHint,
            color: AppDesignSystem.successColor,
          ),
        );
      },
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.spacing24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppDesignSystem.spacing12),
              Text(
                'Reading the bundled app and saved connection…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    // The host's key is the GlobalKey stored in [_hostKey]. Reassigning the
    // field forces a fresh State (used by Connection Apply + Refresh to re-run
    // init). When stable, the same State is reused across rebuilds — letting
    // _doRevokeTrust reach into `currentState.revokeTrust()` without remount.
    final GlobalKey<ScriptAppHostState> hostKey =
        _hostKey ??= GlobalKey<ScriptAppHostState>();
    return ScriptAppHost(
      key: hostKey,
      runtime: _runtime,
      script: _bundle!,
      initialArg: <String, dynamic>{
        'backend_id': _backendId,
        'host': _host,
        // W7-10: inject the host-known principal so the bundle's INITIAL
        // render shows the right identity (matching the runner chrome's
        // "Signed as: …" chip) without waiting for a `whoami` canister
        // round-trip. The Polls bundle used to derive the caller's principal
        // via `whoami` — when the replica was unreachable (the documented,
        // expected state for the local-replica example), `whoami` failed and
        // the body showed "No profile — view-only" while the chrome
        // correctly showed the real principal. The host already had the
        // principal locally (from the active profile's keypair); this just
        // threads it through. Empty string for a keyless user → the bundle
        // renders its honest view-only state from the first frame.
        'principal':
            ProfileScope.of(context).activeKeypair?.principal ?? '',
      },
      // The shipped example dapp uses the per-dapp "Trust this dapp?" gate
      // (UX-10) so a first-run user sees at most ONE prompt, then all of the
      // dapp's methods run without further prompts. The grant is keyed by the
      // descriptor's stable id and persists across restarts. User/marketplace
      // scripts (which don't go through this screen) keep the strict
      // per-method gate by leaving dappTrustId unset.
      dappTrustId: widget.descriptor.id,
      // The host publishes trust-state changes (load / grant / revoke) back to
      // this notifier so the "Trusted" chip and the manage-trust dialog stay
      // in sync with the actual gate.
      dappTrustState: _trustState,
      // UX-12(b): the host classifies every failed canister bridge call by the
      // typed `kind` tag from the Rust FFI and reports it here. On a
      // reachability failure (stale id / dead host) we auto-expand the
      // Connection panel + surface a recovery hint. Permission denials and
      // Candid decode errors never fire this (denial is host-side; candid
      // `kind` is not unreachable).
      onCanisterCallFailure: _onCanisterFailure,
      testBridge: widget.testBridge,
      authenticatedKeypair: ProfileScope.of(context).activeKeypair,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.color,
    this.hint,
    this.monospace = false,
    this.onTap,
  });
  final IconData icon;
  final String text;
  final Color color;
  final String? hint;

  /// Render [text] in a monospace font (used for principals / ids).
  final bool monospace;

  /// When set the chip becomes a tappable copy affordance (ripple + trailing
  /// copy icon). Used by the auth-status chip to make the principal copyable
  /// instead of a dead, clipped string (W7-19).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final core = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.spacing12,
        vertical: AppDesignSystem.spacing8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
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
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
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
          if (onTap != null) ...[
            const SizedBox(width: AppDesignSystem.spacing8),
            Icon(Icons.copy_outlined, color: color, size: 16),
          ],
        ],
      ),
    );

    if (onTap == null) return core;
    return Tooltip(
      message: 'Copy principal',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
        child: core,
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

// =============================================================================
// "Manage trust" / "Revoke trust" affordance copy (UX-10 completeness).
// Distinct from the host's "Trust this dapp?" grant dialog: this is the
// RE-ENTRY surface for an existing grant. Single source of truth — referenced
// by name from the IconButton tooltip, the Trusted status chip, and the
// manage/confirm dialogs above.
// =============================================================================
const String _kManageTrustTooltip = 'Manage trust';
const String _kManageTrustDialogTitle = 'Manage dapp trust';
const String _kManageTrustTrustedBody =
    'This dapp is trusted: it can call any canister (any method, signed or '
    'anonymous) without asking. Revoke to be prompted again on the next call.';
const String _kManageTrustNotTrustedBody =
    'This dapp is not trusted. You\'ll be asked once on the next canister call.';
const String _kManageTrustCloseButton = 'Close';
const String _kRevokeTrustButton = 'Revoke trust';
const String _kConfirmRevokeTitle = 'Revoke trust?';
const String _kConfirmRevokeBody =
    'Future canister calls from this dapp will prompt you again. The current '
    'call (if any) is not affected.';
const String _kConfirmRevokeCancelButton = 'Cancel';
const String _kTrustRevokedMessage =
    'Trust revoked — you\'ll be asked again on the next canister call';
const String _kTrustedChipLabel = 'Trusted';
const String _kTrustedChipHint =
    'This dapp can call any canister without asking. It can also see your '
    'principal and identify you on every call. Use "Manage trust" in the '
    'toolbar to revoke.';
