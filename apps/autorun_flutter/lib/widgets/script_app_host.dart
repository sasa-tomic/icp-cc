import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

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
    this.testBridge,
  });
  final IScriptAppRuntime runtime;
  final String script;
  final Map<String, dynamic>? initialArg;
  final ValueNotifier<ScriptExecutionProgress>? progressNotifier;

  /// Active profile keypair used to sign effects that opt in via
  /// `authenticated: true`. When null, such effects fail LOUDLY rather than
  /// silently degrading to anonymous. Raw private keys never enter the sandbox.
  final ProfileKeypair? authenticatedKeypair;

  /// Test-only canister-bridge override. When null (production) the host
  /// constructs the real [RustScriptBridge]; tests inject a fake to assert
  /// which key material is passed to `callAuthenticated`.
  @visibleForTesting
  final ScriptBridge? testBridge;

  @override
  State<ScriptAppHost> createState() => _ScriptAppHostState();
}

class _ScriptAppHostState extends State<ScriptAppHost> {
  bool _busy = true;
  String? _error;
  Map<String, dynamic>? _state;
  Map<String, dynamic>? _ui;
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];
  final Map<String, bool> _sessionAllow = <String, bool>{};
  bool _cancelled = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProgress(ScriptExecutionProgress.initializing());
    });
    _boot();
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
    });
    try {
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
      _updateProgress(ScriptExecutionProgress.error(e.toString()));
      setState(() {
        _error = '$e';
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
          out = bridge.callAnonymous(
              canisterId: canisterId,
              method: method,
              kind: mode,
              args: args,
              host: host);
        } else {
          out = bridge.callAuthenticated(
              canisterId: canisterId,
              method: method,
              kind: mode,
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
            out = bridge.callAnonymous(
                canisterId: canisterId,
                method: method,
                kind: mode,
                args: args,
                host: host);
          } else {
            out = bridge.callAuthenticated(
                canisterId: canisterId,
                method: method,
                kind: mode,
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
              outputs[outputKey] = json.decode(out);
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
      _enqueueMsg(<String, dynamic>{
        'type': 'effect/result',
        'id': id,
        'ok': false,
        'error': '$e'
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

  Future<_Decision> _showPermissionDialog(
      {required String title,
      required String details,
      required String allowLabel,
      required String allowAlwaysLabel}) async {
    if (!mounted) return _Decision.deny;
    final _Decision? choice = await showDialog<_Decision>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(details)),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(context).pop(_Decision.deny),
                child: const Text('Deny')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(_Decision.allowOnce),
                child: Text(allowLabel)),
            FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_Decision.allowAlways),
                child: Text(allowAlwaysLabel)),
          ],
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

  List<dynamic> _effectsListOf(dynamic raw) {
    if (raw == null) return const <dynamic>[];
    if (raw is List<dynamic>) return raw;
    return const <dynamic>[];
  }

  Future<void> _dispatch(Map<String, dynamic> msg) async {
    if (_state == null) return;
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
      setState(() {
        _error = '$e';
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)));
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: UiV1Renderer(
        ui: ui,
        onEvent: (msg) => _enqueueMsg(msg),
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
