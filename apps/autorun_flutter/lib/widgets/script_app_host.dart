import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/script_runner.dart';
import '../rust/native_bridge.dart';
import 'ui_v1_renderer.dart';

class ScriptAppHost extends StatefulWidget {
  const ScriptAppHost({super.key, required this.runtime, required this.script, this.initialArg});
  final ScriptAppRuntime runtime;
  final String script;
  final Map<String, dynamic>? initialArg;

  @override
  State<ScriptAppHost> createState() => _ScriptAppHostState();
}

class _ScriptAppHostState extends State<ScriptAppHost> {
  bool _busy = true;
  String? _error;
  Map<String, dynamic>? _state;
  Map<String, dynamic>? _ui;
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() { _busy = true; _error = null; });
    try {
      final initOut = await widget.runtime.init(script: widget.script, initialArg: widget.initialArg);
      final Map<String, dynamic> st = (initOut['state'] as Map<String, dynamic>? ?? const <String, dynamic>{});
      final List<dynamic> fx = (initOut['effects'] as List<dynamic>? ?? const <dynamic>[]);
      await _applyStateAndRender(st);
      await _executeEffects(fx);
    } catch (e, st) {
      debugPrint('boot failed: $e\n$st');
      if (!mounted) return;
      setState(() { _error = '$e'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  Future<void> _applyStateAndRender(Map<String, dynamic> st) async {
    _state = st;
    final viewOut = await widget.runtime.view(script: widget.script, state: st);
    final Map<String, dynamic> ui = (viewOut['ui'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    if (!mounted) return;
    setState(() { _ui = ui; });
  }

  Future<void> _executeEffects(List<dynamic> effects) async {
    if (effects.isEmpty) return;
    for (final dynamic eff in effects) {
      if (eff is! Map<String, dynamic>) {
        _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': 'invalid', 'ok': false, 'error': 'invalid effect' });
        continue;
      }
      await _runEffect(eff);
    }
  }

  Future<void> _runEffect(Map<String, dynamic> eff) async {
    final String kind = (eff['kind'] as String? ?? '').trim();
    final String id = (eff['id'] as String? ?? kind);
    try {
      if (kind == 'icp_call') {
        final int mode = (eff['mode'] as num? ?? 0).toInt();
        final String canisterId = (eff['canister_id'] as String? ?? '').trim();
        final String method = (eff['method'] as String? ?? '').trim();
        final String args = (eff['args'] as String? ?? '()');
        final String? host = (eff['host'] as String?)?.trim().isEmpty == true ? null : eff['host'] as String?;
        final String? key = (eff['private_key_b64'] as String?)?.trim();
        final ScriptBridge bridge = RustScriptBridge(const RustBridgeLoader());
        String? out;
        if (key == null || key.isEmpty) {
          out = bridge.callAnonymous(canisterId: canisterId, method: method, kind: mode, args: args, host: host);
        } else {
          out = bridge.callAuthenticated(canisterId: canisterId, method: method, kind: mode, privateKeyB64: key, args: args, host: host);
        }
        if (out == null || out.trim().isEmpty) {
          _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': false, 'error': 'empty response' });
          return;
        }
        try {
          final dynamic parsed = json.decode(out);
          _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': true, 'data': parsed });
        } catch (_) {
          _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': true, 'data': out });
        }
        return;
      }
      if (kind == 'icp_batch') {
        final List<dynamic> items = (eff['items'] as List<dynamic>? ?? const <dynamic>[]);
        final Map<String, dynamic> outputs = <String, dynamic>{};
        final ScriptBridge bridge = RustScriptBridge(const RustBridgeLoader());
        for (final dynamic item in items) {
          if (item is! Map<String, dynamic>) continue;
          final String label = ((item['label'] as String?) ?? (item['method'] as String? ?? '')).trim();
          final int mode = (item['mode'] as num? ?? 0).toInt();
          final String canisterId = (item['canister_id'] as String? ?? '').trim();
          final String method = (item['method'] as String? ?? '').trim();
          final String args = (item['args'] as String? ?? '()');
          final String? host = (item['host'] as String?)?.trim().isEmpty == true ? null : item['host'] as String?;
          final String? key = (item['private_key_b64'] as String?)?.trim();
          String? out;
          if (key == null || key.isEmpty) {
            out = bridge.callAnonymous(canisterId: canisterId, method: method, kind: mode, args: args, host: host);
          } else {
            out = bridge.callAuthenticated(canisterId: canisterId, method: method, kind: mode, privateKeyB64: key, args: args, host: host);
          }
          if (out == null || out.trim().isEmpty) {
            outputs[label.isEmpty ? method : label] = { 'ok': false, 'error': 'empty' };
          } else {
            try {
              outputs[label.isEmpty ? method : label] = json.decode(out);
            } catch (_) {
              outputs[label.isEmpty ? method : label] = out;
            }
          }
        }
        _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': true, 'data': outputs });
        return;
      }
      _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': false, 'error': 'unsupported effect' });
    } catch (e) {
      _enqueueMsg(<String, dynamic>{ 'type': 'effect/result', 'id': id, 'ok': false, 'error': '$e' });
    }
  }

  Future<void> _dispatch(Map<String, dynamic> msg) async {
    if (_state == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final upd = await widget.runtime.update(script: widget.script, msg: msg, state: _state!);
      final Map<String, dynamic> st = (upd['state'] as Map<String, dynamic>? ?? const <String, dynamic>{});
      final List<dynamic> fx = (upd['effects'] as List<dynamic>? ?? const <dynamic>[]);
      await _applyStateAndRender(st);
      await _executeEffects(fx);
    } catch (e, st) {
      debugPrint('dispatch failed: $e\n$st');
      if (!mounted) return;
      setState(() { _error = '$e'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  void _enqueueMsg(Map<String, dynamic> msg) {
    // Immediate dispatch; could be queued/coalesced if needed.
    unawaited(_dispatch(msg));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
    }
    if (_busy && _ui == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final Map<String, dynamic> ui = _ui ?? const <String, dynamic>{ 'type': 'column', 'children': <dynamic>[] };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: UiV1Renderer(
        ui: ui,
        onEvent: (msg) => _enqueueMsg(msg),
      ),
    );
  }
}
