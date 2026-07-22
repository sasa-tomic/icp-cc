import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/example_dapps.dart';
import '../models/profile_keypair.dart';
import '../services/script_runner.dart';
import '../rust/native_bridge.dart';
import '../models/script_execution_progress.dart';
import 'ui_v1_renderer.dart';
import 'script_execution_progress_indicator.dart';

class ScriptAppHost extends StatefulWidget {
  const ScriptAppHost({
    super.key,
    required this.runtime,
    required this.script,
    this.initialArg,
    this.progressNotifier,
    this.authenticatedKeypair,
    this.dappTrustId,
    this.dappTrustState,
    this.testBridge,
    this.onCanisterCallFailure,
  });
  final IScriptAppRuntime runtime;
  final String script;
  final Map<String, dynamic>? initialArg;
  final ValueNotifier<ScriptExecutionProgress>? progressNotifier;

  /// Active profile keypair used to sign effects that opt in via
  /// `authenticated: true`. When null, such effects fail LOUDLY rather than
  /// silently degrading to anonymous. Raw private keys never enter the sandbox.
  final ProfileKeypair? authenticatedKeypair;

  /// When non-null, the host replaces the strict per-method permission gate
  /// with a single per-dapp "Trust this dapp?" prompt: choosing Trust allow lists
  /// ALL of this dapp's canister calls (any method/mode/auth) for the session
  /// AND persists the grant across restarts via [DappTrustStore] (keyed by this
  /// id). Only shipped example dapps set this (the runner passes
  /// `descriptor.id`); user/marketplace scripts leave it null so the strict
  /// per-method gate is preserved.
  final String? dappTrustId;

  /// Optional live mirror of the host's in-memory trust flag, written whenever
  /// it changes: after [DappTrustStore.isTrusted] resolves on boot, after the
  /// user grants the prompt, and after [ScriptAppHostState.revokeTrust].
  /// Parents listen (via [ValueListenableBuilder]) to surface a "Trusted"
  /// indicator and drive the revoke affordance. Only meaningful when
  /// [dappTrustId] is set; ignored otherwise. Owned by the parent.
  final ValueNotifier<bool>? dappTrustState;

  /// Test-only canister-bridge override. When null (production) the host
  /// constructs the real [RustScriptBridge]; tests inject a fake to assert
  /// which key material is passed to `callAuthenticated`.
  @visibleForTesting
  final ScriptBridge? testBridge;

  /// Called whenever a canister bridge call fails, with the failure classified
  /// by [CanisterFailureKind] — match-style on the stable `kind` tag emitted by
  /// the Rust FFI (NOT message string-matching). Fires once per failing call;
  /// the parent decides how to react. UX-12(b) keys off
  /// [CanisterFailureKind.isUnreachable] to auto-expand the Connection panel
  /// and surface a recovery hint on the stale-canister-id-after-`dfx-clean`
  /// path. Host-level failures (permission denied, missing auth) never reach
  /// the bridge and so never fire this callback.
  final void Function(CanisterCallFailure failure)? onCanisterCallFailure;

  @override
  State<ScriptAppHost> createState() => ScriptAppHostState();
}

class ScriptAppHostState extends State<ScriptAppHost> {
  bool _busy = true;
  String? _error;
  /// Raw error detail backing the collapsible "Details" section (W6-1 Bug 2).
  /// [_error] holds the friendly (primary) text; this holds the verbatim
  /// exception for advanced users. Only meaningful while [_error] is non-null.
  String? _errorDetail;
  Map<String, dynamic>? _state;
  Map<String, dynamic>? _ui;
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];
  final Map<String, bool> _sessionAllow = <String, bool>{};
  bool _cancelled = false;

  /// True once the user has granted the per-dapp "Trust this dapp?" prompt
  /// (loaded from [DappTrustStore] at boot, set true on grant). Only consulted
  /// when [widget.dappTrustId] is non-null. When true, the trust gate bypasses
  /// the strict per-method permission dialog for ALL canister calls.
  bool _dappTrusted = false;

  /// UX-H4: true when the user picked "Allow once" on the trust dialog.
  /// Session-scoped: lives only in this host instance, never persisted, never
  /// published to [widget.dappTrustState]. Covers the rest of this dapp
  /// session's calls without writing the persistent grant.
  bool _sessionAllowed = false;

  /// Completes when the persisted trust grant (if any) has been loaded. Awaited
  /// before showing the trust dialog so a restart with persisted trust yields
  /// ZERO prompts instead of flashing a redundant one.
  late final Future<void> _dappTrustLoaded;

  void _updateProgress(ScriptExecutionProgress progress) {
    widget.progressNotifier?.value = progress;
  }

  /// Resolve the canister bridge: test override when provided, else the real
  /// FFI-backed [RustScriptBridge].
  ScriptBridge _bridge() =>
      widget.testBridge ?? RustScriptBridge(const RustBridgeLoader());

  @override
  void initState() {
    super.initState();
    _dappTrustLoaded = _loadDappTrust();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProgress(ScriptExecutionProgress.initializing());
    });
    _boot();
  }

  /// Loads the persisted trust grant (if any) into [_dappTrusted]. Always
  /// completes — a storage failure logs loudly and leaves trust as false
  /// (the safe default; the user simply re-answers the prompt). Publishes the
  /// resolved value to [widget.dappTrustState] so parents can render an
  /// indicator / drive the revoke affordance.
  Future<void> _loadDappTrust() async {
    final String? id = widget.dappTrustId;
    if (id == null) return;
    try {
      _dappTrusted = await DappTrustStore.isTrusted(id);
    } catch (e, st) {
      debugPrint('script_app_host: failed to load dapp trust for "$id": $e\n$st');
      _dappTrusted = false;
    }
    widget.dappTrustState?.value = _dappTrusted;
  }

  /// Programmatically revokes the per-dapp trust grant (UX-10 completeness).
  ///
  /// Clears the persisted value via [DappTrustStore.clear] AND flips the
  /// in-memory [_dappTrusted] flag, so the very next canister call hits
  /// [_ensureDappTrust] again and re-surfaces the one-time "Trust this dapp?"
  /// dialog. The dapp's in-memory JS state is preserved — the user keeps their
  /// context, only the broad grant is rolled back. Publishes the new state to
  /// [widget.dappTrustState].
  ///
  /// No-op when [widget.dappTrustId] is null (the trust gate isn't active for
  /// this host). Persistence failures PROPAGATE — the caller must surface them
  /// loudly. We never flip [_dappTrusted] on a failed clear, so the UI cannot
  /// claim "revoked" while the grant still lives on disk (it would re-assert
  /// itself on the next restart).
  Future<void> revokeTrust() async {
    final String? id = widget.dappTrustId;
    if (id == null) return;
    await DappTrustStore.clear(id); // may throw — propagate loudly.
    _dappTrusted = false;
    widget.dappTrustState?.value = false;
  }

  void _cancel() {
    _cancelled = true;
    _updateProgress(ScriptExecutionProgress.error('Operation cancelled'));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _boot() async {
    if (_cancelled) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      // R-3 (Web): the QuickJS-WASM engine must be LOADED before any sync eval.
      // On native this is an immediate no-op (QuickJsReady). On Web it kicks off
      // + awaits the singleton engine load; while loading the existing _busy
      // progress indicator shows, and a load failure surfaces as _error (never
      // a silent no-op). Evaluated before init() so the loading state is honest.
      final readiness = await probeQuickJsReadiness();
      if (readiness is QuickJsUnavailable) {
        throw StateError(readiness.reason);
      }
      // R-3b (Web): the agent-js IC-agent bundle must be LOADED before any
      // canister call (callAnonymous / callAuthenticated / fetchCandid). On
      // native this is an immediate no-op (IcAgentReady — the Rust FFI is the
      // production path; agent-js is Web-only). On Web it loads + awaits the
      // singleton agent (bounded by a 30s timeout); a load failure surfaces as
      // _error via the existing busy/error path — never a silent no-op later.
      final icReadiness = await probeIcAgentReadiness();
      if (icReadiness is IcAgentUnavailable) {
        throw StateError(icReadiness.reason);
      }
      final initOut = await widget.runtime
          .init(script: widget.script, initialArg: widget.initialArg);
      if (_cancelled) return;
      final Map<String, dynamic> st =
          (initOut['state'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      final Map<String, dynamic>? initUi =
          initOut['ui'] as Map<String, dynamic>?;
      final List<dynamic> fx = _effectsListOf(initOut['effects']);
      if (initUi != null) {
        if (!mounted) return;
        setState(() {
          _state = st;
          _ui = initUi;
        });
      }
      _updateProgress(ScriptExecutionProgress.processingResponse());
      await _applyStateAndRender(st);
      await _executeEffects(fx);
      if (!_cancelled) {
        _updateProgress(ScriptExecutionProgress.complete());
      }
    } catch (e, st) {
      debugPrint('boot failed: $e\n$st');
      if (!mounted) return;
      // W6-1 Bug 2: map raw exception dumps (HTTP headers / HTML bodies from a
      // misconfigured proxy, or an IcAgentLoadException) to a friendly primary
      // message; keep the verbatim text for the collapsible Details section.
      _updateProgress(ScriptExecutionProgress.error(e.toString()));
      setState(() {
        _error = friendlyIcErrorMessage('$e');
        _errorDetail = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _applyStateAndRender(Map<String, dynamic> st) async {
    _state = st;
    final viewOut = await widget.runtime.view(script: widget.script, state: st);
    final Map<String, dynamic> ui =
        (viewOut['ui'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    if (!mounted) return;
    setState(() {
      _ui = ui;
    });
  }

  Future<void> _executeEffects(List<dynamic> effects) async {
    if (effects.isEmpty) return;
    for (final dynamic eff in effects) {
      if (eff is! Map<String, dynamic>) {
        _enqueueMsg(<String, dynamic>{
          'type': 'effect/result',
          'id': 'invalid',
          'ok': false,
          'error': 'invalid effect'
        });
        continue;
      }
      await _runEffect(eff);
    }
  }

  Future<void> _runEffect(Map<String, dynamic> eff) async {
    if (_cancelled) return;
    final String kind = (eff['kind'] as String? ?? '').trim();
    final String id = (eff['id'] as String? ?? kind);
    try {
      if (kind == 'icp_call') {
        final int mode = (eff['mode'] as num? ?? 0).toInt();
        final String canisterId = (eff['canister_id'] as String? ?? '').trim();
        final String method = (eff['method'] as String? ?? '').trim();
        _updateProgress(
            ScriptExecutionProgress.callingCanister(canisterId, method));
        final String args = (eff['args'] as String? ?? '()');
        final String? host = (eff['host'] as String?)?.trim().isEmpty == true
            ? null
            : eff['host'] as String?;
        final _ResolvedAuth auth = _resolveAuthForCall(eff);
        if (auth.missingAuth) {
          _enqueueMsg(<String, dynamic>{
            'type': 'effect/result',
            'id': id,
            'ok': false,
            'error': _kMissingAuthMessage,
          });
          return;
        }
        final bool authenticated = auth.isAuthenticated;
        final bool permitted = await _ensurePermissionForCall(
          canisterId: canisterId,
          method: method,
          mode: mode,
          authenticated: authenticated,
          authLabel: auth.label,
          argsPreview: args,
        );
        if (!permitted) {
          _enqueueMsg(<String, dynamic>{
            'type': 'effect/result',
            'id': id,
            'ok': false,
            'error': 'permission denied'
          });
          return;
        }
        final ScriptBridge bridge = _bridge();
        String? out;
        if (!authenticated) {
          out = await bridge.callAnonymous(
              canisterId: canisterId,
              method: method,
              mode: mode,
              args: args,
              host: host);
        } else {
          out = await bridge.callAuthenticated(
              canisterId: canisterId,
              method: method,
              mode: mode,
              privateKeyB64: auth.privateKey!,
              args: args,
              host: host);
        }
        if (out == null || out.trim().isEmpty) {
          _enqueueMsg(<String, dynamic>{
            'type': 'effect/result',
            'id': id,
            'ok': false,
            'error': 'empty response'
          });
          return;
        }
        try {
          final dynamic parsed = json.decode(out);
          _reportBridgeFailureIfAny(parsed);
          _enqueueMsg(<String, dynamic>{
            'type': 'effect/result',
            'id': id,
            'ok': true,
            'data': parsed
          });
        } on FormatException catch (e) {
          debugPrint('script_app_host: call result not JSON, passing raw: $e');
          _enqueueMsg(<String, dynamic>{
            'type': 'effect/result',
            'id': id,
            'ok': true,
            'data': out
          });
        }
        return;
      }
      if (kind == 'icp_batch') {
        final List<dynamic> items =
            (eff['items'] as List<dynamic>? ?? const <dynamic>[]);
        final Map<String, dynamic> outputs = <String, dynamic>{};
        final ScriptBridge bridge = _bridge();
        final List<Map<String, dynamic>> unknown = <Map<String, dynamic>>[];
        for (final dynamic item in items) {
          if (item is! Map<String, dynamic>) continue;
          final int mode = (item['mode'] as num? ?? 0).toInt();
          final String canisterId =
              (item['canister_id'] as String? ?? '').trim();
          final String method = (item['method'] as String? ?? '').trim();
          final bool authenticated = _resolveAuthForCall(item).isAuthenticated;
          if (!_isAllowed(
              canisterId: canisterId,
              method: method,
              mode: mode,
              authenticated: authenticated)) {
            unknown.add(item);
          }
        }
        if (unknown.isNotEmpty) {
          final bool permitted = await _ensurePermissionForBatch(items);
          if (!permitted) {
            _enqueueMsg(<String, dynamic>{
              'type': 'effect/result',
              'id': id,
              'ok': false,
              'error': 'permission denied'
            });
            return;
          }
        }
        for (final dynamic item in items) {
          if (item is! Map<String, dynamic>) continue;
          final String label =
              ((item['label'] as String?) ?? (item['method'] as String? ?? ''))
                  .trim();
          final int mode = (item['mode'] as num? ?? 0).toInt();
          final String canisterId =
              (item['canister_id'] as String? ?? '').trim();
          final String method = (item['method'] as String? ?? '').trim();
          _updateProgress(
              ScriptExecutionProgress.callingCanister(canisterId, method));
          final String args = (item['args'] as String? ?? '()');
          final String? host = (item['host'] as String?)?.trim().isEmpty == true
              ? null
              : item['host'] as String?;
          final _ResolvedAuth auth = _resolveAuthForCall(item);
          final String outputKey = label.isEmpty ? method : label;
          if (auth.missingAuth) {
            outputs[outputKey] = <String, dynamic>{
              'ok': false,
              'error': _kMissingAuthMessage,
            };
            continue;
          }
          final bool authenticated = auth.isAuthenticated;
          if (!_isAllowed(
              canisterId: canisterId,
              method: method,
              mode: mode,
              authenticated: authenticated)) {
            outputs[outputKey] = <String, dynamic>{
              'ok': false,
              'error': 'denied'
            };
            continue;
          }
          String? out;
          if (!authenticated) {
            out = await bridge.callAnonymous(
                canisterId: canisterId,
                method: method,
                mode: mode,
                args: args,
                host: host);
          } else {
            out = await bridge.callAuthenticated(
                canisterId: canisterId,
                method: method,
                mode: mode,
                privateKeyB64: auth.privateKey!,
                args: args,
                host: host);
          }
          if (out == null || out.trim().isEmpty) {
            outputs[outputKey] = <String, dynamic>{
              'ok': false,
              'error': 'empty'
            };
          } else {
            try {
              final dynamic parsed = json.decode(out);
              _reportBridgeFailureIfAny(parsed);
              outputs[outputKey] = parsed;
            } on FormatException catch (e) {
              debugPrint(
                  'script_app_host: batch result not JSON, passing raw: $e');
              outputs[outputKey] = out;
            }
          }
        }
        _enqueueMsg(<String, dynamic>{
          'type': 'effect/result',
          'id': id,
          'ok': true,
          'data': outputs
        });
        return;
      }
      _enqueueMsg(<String, dynamic>{
        'type': 'effect/result',
        'id': id,
        'ok': false,
        'error': 'unsupported effect'
      });
    } catch (e) {
      // W6-1 Bug 2: a thrown IcAgentLoadException (e.g. the singleton agent's
      // bootstrap failed) carries raw HTTP headers / HTML bodies. Map raw dumps
      // to the friendly message so they never render verbatim as result text.
      _enqueueMsg(<String, dynamic>{
        'type': 'effect/result',
        'id': id,
        'ok': false,
        'error': friendlyIcErrorMessage('$e')
      });
    }
  }

  String _keyFor(
      {required String canisterId,
      required String method,
      required int mode,
      required bool authenticated}) {
    return '${authenticated ? 'auth' : 'anon'}|$mode|$canisterId|$method';
  }

  bool _isAllowed(
      {required String canisterId,
      required String method,
      required int mode,
      required bool authenticated}) {
    // The per-dapp trust gate (when active) covers every canister call without
    // consulting the per-method map.
    if (_dappTrusted) return true;
    final String key = _keyFor(
        canisterId: canisterId,
        method: method,
        mode: mode,
        authenticated: authenticated);
    return _sessionAllow[key] == true;
  }

  Future<bool> _ensurePermissionForCall(
      {required String canisterId,
      required String method,
      required int mode,
      required bool authenticated,
      required String authLabel,
      String? argsPreview}) async {
    if (widget.dappTrustId != null) {
      return _ensureDappTrust();
    }
    final String key = _keyFor(
        canisterId: canisterId,
        method: method,
        mode: mode,
        authenticated: authenticated);
    if (_sessionAllow[key] == true) return true;
    final _Decision decision = await _showPermissionDialog(
      title: 'Allow canister call?',
      details:
          '$authLabel ${_modeLabel(mode)}\n$canisterId.$method\nargs: ${_truncate(argsPreview ?? '()')}',
      allowLabel: 'Allow once',
      allowAlwaysLabel: 'Always allow',
    );
    if (decision == _Decision.allowAlways) {
      _sessionAllow[key] = true;
      return true;
    }
    if (decision == _Decision.allowOnce) {
      return true;
    }
    return false;
  }

  Future<bool> _ensurePermissionForBatch(List<dynamic> items) async {
    // The per-dapp trust gate is all-or-nothing for the whole dapp, regardless
    // of which/how many methods are in this batch.
    if (widget.dappTrustId != null) {
      return _ensureDappTrust();
    }
    final List<String> lines = <String>[];
    for (final dynamic item in items) {
      if (item is! Map<String, dynamic>) continue;
      final int mode = (item['mode'] as num? ?? 0).toInt();
      final String canisterId = (item['canister_id'] as String? ?? '').trim();
      final String method = (item['method'] as String? ?? '').trim();
      final _ResolvedAuth auth = _resolveAuthForCall(item);
      if (auth.missingAuth) continue; // surfaced as an error in execution
      final bool authenticated = auth.isAuthenticated;
      final String k = _keyFor(
          canisterId: canisterId,
          method: method,
          mode: mode,
          authenticated: authenticated);
      if (_sessionAllow[k] == true) continue;
      lines.add('${auth.label} ${_modeLabel(mode)} $canisterId.$method');
    }
    if (lines.isEmpty) return true;
    final _Decision decision = await _showPermissionDialog(
      title: 'Allow batch canister calls?',
      details: lines.join('\n'),
      allowLabel: 'Allow once',
      allowAlwaysLabel: 'Always allow all',
    );
    if (decision == _Decision.allowAlways) {
      for (final dynamic item in items) {
        if (item is! Map<String, dynamic>) continue;
        final int mode = (item['mode'] as num? ?? 0).toInt();
        final String canisterId = (item['canister_id'] as String? ?? '').trim();
        final String method = (item['method'] as String? ?? '').trim();
        final bool authenticated = _resolveAuthForCall(item).isAuthenticated;
        final String k = _keyFor(
            canisterId: canisterId,
            method: method,
            mode: mode,
            authenticated: authenticated);
        _sessionAllow[k] = true;
      }
      return true;
    }
    if (decision == _Decision.allowOnce) {
      return true;
    }
    return false;
  }

  /// Single per-dapp "Trust this dapp?" gate. When the user grants trust:
  ///  - all current and future canister calls from this host instance run
  ///    without further prompts (`_dappTrusted == true` short-circuits both
  ///    [_isAllowed] and the per-call/batch permission paths), and
  ///  - the grant persists across app restarts via [DappTrustStore].
  /// On Deny, returns false (effect -> "permission denied"); the user is asked
  /// again on the next canister effect.
  ///
  /// UX-H4 adds the third affordance: "Allow once" grants permission for the
  /// current session (the rest of this host instance's calls run without
  /// re-prompting) but does NOT persist. Implemented via a separate in-memory
  /// [_sessionAllowed] flag so the parent's "Trusted" indicator (driven by
  /// [widget.dappTrustState]) only lights up for actually-persistent trust.
  Future<bool> _ensureDappTrust() async {
    if (_dappTrusted) return true;
    if (_sessionAllowed) return true;
    // Wait for the persisted trust grant to load so a restart with prior trust
    // does NOT flash a redundant prompt.
    try {
      await _dappTrustLoaded;
    } catch (e, st) {
      debugPrint('script_app_host: dapp trust load failed: $e\n$st');
    }
    if (!mounted) return false;
    if (_dappTrusted) return true;
    final _Decision decision = await _showPermissionDialog(
      title: _kTrustDappDialogTitle,
      details: _kTrustDappDialogBody,
      allowLabel: _kTrustDappAllowOnceButton,
      allowAlwaysLabel: _kTrustDappButton,
    );
    if (decision == _Decision.allowAlways) {
      _dappTrusted = true;
      widget.dappTrustState?.value = true;
      final String? id = widget.dappTrustId;
      if (id != null) {
        try {
          await DappTrustStore.setTrusted(id);
        } catch (e, st) {
          // Persistence failure is loud but non-blocking: the in-session grant
          // still applies so the user is not stranded; next restart will
          // re-prompt.
          debugPrint('script_app_host: failed to persist dapp trust for "$id": $e\n$st');
        }
      }
      return true;
    }
    if (decision == _Decision.allowOnce) {
      // Session-only grant: covers the rest of this host instance without
      // writing to [DappTrustStore] or publishing to [widget.dappTrustState]
      // (the parent's "Trusted" chip reflects persistent trust only).
      _sessionAllowed = true;
      return true;
    }
    return false;
  }

  Future<_Decision> _showPermissionDialog(
      {required String title,
      required String details,
      String? allowLabel,
      required String allowAlwaysLabel}) async {
    if (!mounted) return _Decision.deny;
    final _Decision? choice = await showDialog<_Decision>(
      context: context,
      builder: (BuildContext context) {
        return Focus(
          autofocus: true,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  Navigator.of(context).pop(
                    allowLabel != null
                        ? _Decision.allowOnce
                        : _Decision.allowAlways,
                  ),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(context).pop(_Decision.deny),
            },
            child: AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(details)),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.of(context).pop(_Decision.deny),
                    child: const Text('Deny')),
                if (allowLabel != null)
                  TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_Decision.allowOnce),
                      child: Text(allowLabel)),
                FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_Decision.allowAlways),
                    child: Text(allowAlwaysLabel)),
              ],
            ),
          ),
        );
      },
    );
    return choice ?? _Decision.deny;
  }

  String _modeLabel(int mode) {
    switch (mode) {
      case 1:
        return 'Update';
      case 2:
        return 'Composite';
      default:
        return 'Query';
    }
  }

  /// Resolve the private key for a single effect/item with this priority:
  ///   1. explicit `private_key_b64` (compat),
  ///   2. `authenticated: true` + [widget.authenticatedKeypair] (sign as me),
  ///   3. anonymous.
  /// When auth is requested but no keypair is available, returns
  /// [missingAuth] = true so the caller surfaces a LOUD error instead of
  /// silently degrading to anonymous.
  _ResolvedAuth _resolveAuthForCall(Map<String, dynamic> spec) {
    final String? explicitKey =
        (spec['private_key_b64'] as String?)?.trim();
    if (explicitKey != null && explicitKey.isNotEmpty) {
      return _ResolvedAuth(
          privateKey: explicitKey, label: 'Authenticated (explicit key)');
    }
    final bool wantAuth = (spec['authenticated'] as bool?) ?? false;
    if (wantAuth) {
      final ProfileKeypair? kp = widget.authenticatedKeypair;
      if (kp == null) {
        return const _ResolvedAuth(
            label: 'Authenticated (no keypair)', missingAuth: true);
      }
      return _ResolvedAuth(
          privateKey: kp.privateKey, label: 'Authenticated (active profile)');
    }
    return const _ResolvedAuth(label: 'Anonymous');
  }

  String _truncate(String s, {int max = 160}) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }

  /// Inspects a parsed bridge result for the typed error shape
  /// `{"ok": false, "kind": "<tag>", "error": "..."}` and, when present, fires
  /// [widget.onCanisterCallFailure] with the classified [CanisterFailureKind].
  ///
  /// Match-style on the stable `kind` tag emitted by the Rust FFI
  /// (`canister_err_ptr` in `ffi.rs`) — never string-matches the human-readable
  /// `error` body. Unknown `kind` tags (or non-error shapes) are left
  /// unclassified on purpose: the call still surfaces to the script as a failed
  /// effect/result (the script's `readEffect` handles `data.ok === false`), we
  /// just don't pretend to know it's a reachability failure.
  void _reportBridgeFailureIfAny(dynamic parsed) {
    if (parsed is! Map<String, dynamic>) return;
    if (parsed['ok'] != false) return;
    final CanisterFailureKind? kind = _matchFailureKind(parsed['kind']);
    if (kind == null) return;
    final String error = (parsed['error']?.toString().isNotEmpty ?? false)
        ? parsed['error'].toString()
        : kind.name;
    widget.onCanisterCallFailure
        ?.call(CanisterCallFailure(kind: kind, error: error));
  }

  /// Maps the stable FFI `kind` string to a typed [CanisterFailureKind].
  /// Returns `null` for anything unrecognized so the caller can skip
  /// classification rather than guess.
  static CanisterFailureKind? _matchFailureKind(dynamic kind) {
    if (kind is! String) return null;
    switch (kind) {
      case 'net':
        return CanisterFailureKind.net;
      case 'invalid_canister_id':
        return CanisterFailureKind.invalidCanisterId;
      case 'candid':
        return CanisterFailureKind.candid;
      default:
        return null;
    }
  }

  List<dynamic> _effectsListOf(dynamic raw) {
    if (raw == null) return const <dynamic>[];
    if (raw is List<dynamic>) return raw;
    return const <dynamic>[];
  }

  Future<void> _dispatch(Map<String, dynamic> msg) async {
    if (_state == null) return;
    // E2E-D-RESUME-1: `_dispatch` is scheduled via `unawaited(_dispatch(msg))`
    // from `_enqueueMsg`, which itself runs inside `_boot`'s async chain. When
    // the parent remounts the host (DappRunnerScreen._applyConfig /
    // _refreshDapp reassign the GlobalKey), this State is disposed mid-boot;
    // the unawaited microtask then lands on a defunct State. Guard against
    // that here — canonical fix per
    // https://api.flutter.dev/flutter/widgets/State/mounted.html.
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final upd = await widget.runtime
          .update(script: widget.script, msg: msg, state: _state!);
      final Map<String, dynamic> st =
          (upd['state'] as Map<String, dynamic>? ?? const <String, dynamic>{});
      final List<dynamic> fx = _effectsListOf(upd['effects']);
      await _applyStateAndRender(st);
      await _executeEffects(fx);
    } catch (e, st) {
      debugPrint('dispatch failed: $e\n$st');
      if (!mounted) return;
      // W6-1 Bug 2: same friendly-error + raw-Detail treatment as _boot.
      setState(() {
        _error = friendlyIcErrorMessage('$e');
        _errorDetail = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _enqueueMsg(Map<String, dynamic> msg) {
    unawaited(_dispatch(msg));
  }

  /// W6-1 Bug 2: re-attempts the failed boot. Clears the error and re-runs
  /// `_boot` (which re-evaluates the readiness gates + init). For a transient
  /// failure (a backend that came back up, a fixed proxy origin) this recovers
  /// without forcing the user to leave and re-open the dapp.
  void _retry() => _boot();

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _DappErrorView(
        message: _error!,
        detail: _errorDetail,
        onRetry: _retry,
      );
    }
    if (_busy && _ui == null) {
      return ScriptExecutionProgressIndicator(
        progress: widget.progressNotifier?.value ??
            ScriptExecutionProgress.initializing(),
        onCancel: _cancel,
      );
    }
    final Map<String, dynamic> ui = _ui ??
        const <String, dynamic>{'type': 'column', 'children': <dynamic>[]};
    return _wrapWithTheme(
      context,
      ui,
      SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: UiV1Renderer(
          ui: ui,
          onEvent: (msg) => _enqueueMsg(msg),
        ),
      ),
    );
  }

  /// Applies an optional bundle-supplied theme to [child].
  ///
  /// A bundle opts into theming by including a `theme` map on the root UI node
  /// returned from `view()`:
  ///
  ///   { type: 'column', theme: { background, card_background, accent,
  ///                              text, text_muted }, children: [...] }
  ///
  /// Each value is a hex string (`#RRGGBB`, `RRGGBB`, `#RGB` shorthand, or
  /// `#AARRGGBB`). Missing/invalid values are skipped silently — bundles may
  /// ship only the fields they care about. When no field survives parsing the
  /// child is returned unchanged (no extra widgets inserted), so theme-less
  /// bundles render exactly as before.
  ///
  /// Mapping:
  ///   - background      → ColoredBox around the scroll view (page bg).
  ///   - card_background → colorScheme.surface + cardColor (sections / Cards).
  ///   - accent          → colorScheme.primary (FilledButtons, highlights).
  ///   - text            → textTheme body/display color (body Text).
  ///   - text_muted      → hintColor + colorScheme.onSurfaceVariant.
  Widget _wrapWithTheme(BuildContext context, Map<String, dynamic> ui,
      Widget child) {
    final Map<String, dynamic> raw =
        (ui['theme'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Color? background = _parseHexColor(raw['background']);
    final Color? card = _parseHexColor(raw['card_background']);
    final Color? accent = _parseHexColor(raw['accent']);
    final Color? text = _parseHexColor(raw['text']);
    final Color? textMuted = _parseHexColor(raw['text_muted']);

    if (background != null) {
      child = ColoredBox(color: background, child: child);
    }
    final bool hasSchemeOverride =
        card != null || accent != null || text != null || textMuted != null;
    if (hasSchemeOverride) {
      final ThemeData base = Theme.of(context);
      child = Theme(
        data: base.copyWith(
          cardColor: card ?? base.cardColor,
          colorScheme: base.colorScheme.copyWith(
            surface: card,
            primary: accent,
            onSurfaceVariant: textMuted,
          ),
          hintColor: textMuted,
          textTheme: text == null
              ? base.textTheme
              : base.textTheme.apply(
                  bodyColor: text,
                  displayColor: text,
                ),
        ),
        child: child,
      );
    }
    return child;
  }
}

/// Parse a bundle-supplied hex color string into a [Color], or return null
/// when the value is missing/invalid. Accepts `#RRGGBB`, `RRGGBB`, `#RGB`
/// (shorthand, expanded to `#RRGGBB`), and `#AARRGGBB` (with alpha). A
/// 6-digit value is implicitly fully opaque (alpha = 0xFF). Non-string values
/// (numbers, maps, lists) are rejected silently — bundles that ship a
/// malformed theme must not crash the host.
Color? _parseHexColor(Object? raw) {
  if (raw is! String) return null;
  String s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((String c) => '$c$c').join();
  }
  if (s.length != 6 && s.length != 8) return null;
  final int? value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  if (s.length == 6) return Color(0xFF000000 | value);
  return Color(value);
}

// =============================================================================
// W6-1 Bug 2 — friendly dapp error view.
// Replaces the raw `Text(_error)` dump with a concise friendly message + a
// Retry affordance, keeping the verbatim exception in a collapsible "Details"
// section (never the primary text). Raw IcAgentLoadException dumps (HTTP
// status lines, server banners, HTML bodies) are sanitized BEFORE reaching
// here (friendlyIcErrorMessage in _boot/_dispatch/_runEffect), so the primary
// text is always actionable; Details is for advanced users / bug reports.
// =============================================================================

class _DappErrorView extends StatefulWidget {
  const _DappErrorView({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  /// The friendly primary message (already sanitized).
  final String message;
  /// The verbatim exception text (nullable — hidden when absent/identical).
  final String? detail;
  /// Re-attempts the failed boot.
  final VoidCallback onRetry;

  @override
  State<_DappErrorView> createState() => _DappErrorViewState();
}

class _DappErrorViewState extends State<_DappErrorView> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetail = widget.detail != null &&
        widget.detail!.isNotEmpty &&
        widget.detail != widget.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded,
                size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('dappErrorRetry'),
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
            if (hasDetail) ...<Widget>[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('dappErrorDetailsToggle'),
                  onPressed: () =>
                      setState(() => _detailsExpanded = !_detailsExpanded),
                  icon: Icon(_detailsExpanded
                      ? Icons.expand_less
                      : Icons.expand_more),
                  label: Text(_detailsExpanded
                      ? 'Hide details'
                      : 'Show details'),
                ),
              ),
              if (_detailsExpanded)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.detail!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Decision { deny, allowOnce, allowAlways }

/// Resolved signing identity + human label for a single effect/item.
class _ResolvedAuth {
  const _ResolvedAuth({this.privateKey, required this.label, this.missingAuth = false});
  final String? privateKey;
  final String label;
  final bool missingAuth;
  bool get isAuthenticated => privateKey != null && privateKey!.isNotEmpty;
}

/// Surfaced verbatim when an effect opts into `authenticated: true` but no
/// active-profile keypair is wired into the host. Never a silent anon fallback.
const String _kMissingAuthMessage =
    'authenticated call requested but no active profile keypair';

// =============================================================================
// Canister bridge failure classification (UX-12(b)).
//
// The Rust FFI emits a typed `kind` discriminator on every failed canister call
// (see `canister_err_ptr` in `crates/icp_core/src/ffi.rs`): the Dart host
// matches on that tag — NOT on the human-readable `error` string — to decide
// whether a failure is "canister unreachable" (point the user at the Connection
// panel) vs. e.g. a Candid decode error (the call reached the canister, so the
// connection is fine).
// =============================================================================

/// Typed discriminator for a failed canister bridge call. Mirrors the Rust
/// `CanisterClientError` variant tag carried in the FFI error JSON (`"kind"`).
enum CanisterFailureKind {
  /// Network / timeout / replica unreachable / canister-not-found. The
  /// connection config (canister id or host) can't reach a working canister.
  net,

  /// The canister id text failed to parse as a principal (malformed id).
  invalidCanisterId,

  /// The call reached the canister but the response / args could not be
  /// (en)coded as Candid. NOT a reachability problem.
  candid;

  /// True when this failure means the Connection config can't reach a working
  /// canister — the recovery is to fix the id/host in the Connection panel.
  /// This is the predicate UX-12(b) auto-expand keys off.
  bool get isUnreachable => this == net || this == invalidCanisterId;
}

/// A canister bridge call that failed, classified by [kind]. Surfaced to the
/// parent via [ScriptAppHost.onCanisterCallFailure] so it can react (e.g.
/// UX-12(b): auto-expand the Connection panel when [kind].isUnreachable).
class CanisterCallFailure {
  const CanisterCallFailure({required this.kind, required this.error});
  final CanisterFailureKind kind;

  /// The human-readable error body from the bridge (for logging / diagnostics).
  final String error;
}

// =============================================================================
// "Trust this dapp" prompt copy (UX-10, UX-H4).
// Distinct from the per-method "Allow canister call? / Always allow" dialog:
// the trust grant covers ALL current + future methods of one shipped example
// dapp. Single source of truth — referenced by name from `_ensureDappTrust`.
//
// UX-H4 additions:
//   - principal-visibility warning (the dapp can identify you on every
//     authenticated call);
//   - `_kTrustDappAllowOnceButton` (the session-only third affordance).
// =============================================================================
const String _kTrustDappDialogTitle = 'Trust this dapp?';
const String _kTrustDappDialogBody =
    'Allow ALL current and future canister calls from this dapp — any method, '
    'signed or anonymous. You won\'t be asked again.\n'
    'The dapp will see your principal and can identify you on every call.\n'
    'Only trust dapps you recognize.';
const String _kTrustDappButton = 'Trust this dapp';
const String _kTrustDappAllowOnceButton = 'Allow once';
