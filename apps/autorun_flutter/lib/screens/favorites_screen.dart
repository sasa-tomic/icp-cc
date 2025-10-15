import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../rust/native_bridge.dart';
import '../services/favorites_events.dart';
import '../utils/json_format.dart';
import '../utils/candid_form_model.dart';
import '../utils/candid_type_resolver.dart';
import '../utils/candid_json_example.dart';
import '../utils/candid_json_validate.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.bridge, required this.onOpenClient});

  final RustBridgeLoader bridge;
  final Future<void> Function({String? initialCanisterId, String? initialMethodName}) onOpenClient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: <Widget>[
          IconButton(
            onPressed: () => onOpenClient(),
            tooltip: 'Canister client',
            icon: const Icon(Icons.cloud),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Well-known canisters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _WellKnownList(onSelect: (cid, method) {
            onOpenClient(initialCanisterId: cid, initialMethodName: method);
          }),
          const SizedBox(height: 16),
          Text('Your favorites', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _FavoritesList(
            bridge: bridge,
            onTapEntry: (cid, method) {
              onOpenClient(initialCanisterId: cid, initialMethodName: method);
            },
          ),
        ],
      ),
    );
  }
}

class CanisterClientSheet extends StatefulWidget {
  const CanisterClientSheet({super.key, required this.bridge, this.initialCanisterId, this.initialMethodName});
  final RustBridgeLoader bridge;
  final String? initialCanisterId;
  final String? initialMethodName;

  @override
  State<CanisterClientSheet> createState() => _CanisterClientSheetState();
}

class _CanisterClientSheetState extends State<CanisterClientSheet> {
  final TextEditingController _canisterController = TextEditingController();
  final TextEditingController _hostController = TextEditingController(text: 'https://ic0.app');
  final TextEditingController _methodController = TextEditingController();
  final TextEditingController _identityKeyController = TextEditingController();
  int _selectedKind = 0; // 0=query,1=update,2=comp
  // Args input
  final TextEditingController _jsonArgsController = TextEditingController();
  bool _useAutoForm = true;
  List<Map<String, dynamic>> _currentMethodSig = const <Map<String, dynamic>>[]; // [{"name": "arg0", "type": "text"}, ...]
  String? _resultJson;
  String? _candidRaw;
  List<Map<String, dynamic>> _methods = const <Map<String, dynamic>>[];
  bool _isFetching = false;
  String _expectedJsonExample = '';
  List<String> _resolvedArgs = const <String>[];
  List<String> _validationErrors = const <String>[];

  void _onArgsChanged() {
    if (_resolvedArgs.isEmpty) return;
    final String args = _jsonArgsController.text.trim();
    try {
      final v = validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: args);
      if (mounted) setState(() => _validationErrors = v.errors);
    } catch (e) {
      if (mounted) setState(() => _validationErrors = <String>['Validation error: $e']);
    }
  }

  @override
  void dispose() {
    _canisterController.dispose();
    _hostController.dispose();
    _methodController.dispose();
    _identityKeyController.dispose();
    _jsonArgsController.removeListener(_onArgsChanged);
    _jsonArgsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _jsonArgsController.addListener(_onArgsChanged);
    if ((widget.initialCanisterId ?? '').isNotEmpty) {
      _canisterController.text = widget.initialCanisterId!.trim();
    }
    if ((widget.initialMethodName ?? '').isNotEmpty) {
      _methodController.text = widget.initialMethodName!.trim();
    }
    // Auto-fetch methods if we have a target canister and method preset
    if (_canisterController.text.trim().isNotEmpty && _methodController.text.trim().isNotEmpty) {
      // Defer to next microtask to allow build context to settle
      scheduleMicrotask(_fetchAndParse);
    }
  }

  Future<void> _fetchAndParse() async {
    final String cid = _canisterController.text.trim();
    if (cid.isEmpty || _isFetching) return;
    setState(() => _isFetching = true);
    try {
      final String? did = await widget.bridge.fetchCandid(
        canisterId: cid,
        host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
      );
      if (did == null || did.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to fetch Candid')));
        return;
      }
      final String? parsedJson = widget.bridge.parseCandid(candidText: did);
      if (parsedJson == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to parse Candid')));
        return;
      }
      final Map<String, dynamic> parsed = json.decode(parsedJson) as Map<String, dynamic>;
      final List<dynamic> methods = (parsed['methods'] as List<dynamic>? ?? <dynamic>[]);
      setState(() {
        _candidRaw = did;
        _methods = methods
            .whereType<Map<String, dynamic>>()
            .map((m) => {
                  'name': m['name'] as String? ?? '',
                  'kind': m['kind'] as String? ?? '',
                  'args': (m['args'] as List<dynamic>? ?? const <dynamic>[]).map((e) => e.toString()).toList(),
                  'rets': (m['rets'] as List<dynamic>? ?? const <dynamic>[]).map((e) => e.toString()).toList(),
                })
            .toList();
        // If a method was preselected, align kind and arg fields to its signature
        final String preset = _methodController.text.trim();
        Map<String, dynamic>? selected;
        if (preset.isNotEmpty) {
          selected = _methods.cast<Map<String, dynamic>?>().firstWhere(
                (m) => (m?['name'] as String? ?? '') == preset,
                orElse: () => null,
              );
        }
        if (selected != null) {
          final String kind = (selected['kind'] as String).toLowerCase();
          _selectedKind = kind.contains('update') ? 1 : (kind.contains('composite') ? 2 : 0);
          // Expand aliases using Candid source
          final resolver = CandidTypeResolver(_candidRaw ?? '');
          _resolvedArgs = resolver.resolveArgTypes((selected['args'] as List<String>));
          _currentMethodSig = _resolvedArgs
              .asMap()
              .entries
              .map((e) => {'name': 'arg${e.key}', 'type': e.value})
              .toList();
          _expectedJsonExample = buildJsonExampleForArgs(_resolvedArgs);
          _jsonArgsController.text = _expectedJsonExample;
          // Trigger validation display for the example
          final v = validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: _jsonArgsController.text.trim());
          _validationErrors = v.errors;
          _useAutoForm = false;
        } else if (_methods.isNotEmpty) {
          // Fallback to the first method as a hint when nothing preset matches
          if (_methodController.text.trim().isEmpty) {
            _methodController.text = (_methods.first['name'] as String?) ?? '';
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget argsEditor = _ArgsEditor(
      useAuto: _useAutoForm,
      argTypes: _currentMethodSig.map((m) => m['type'] as String).toList(),
      controller: _jsonArgsController,
      onToggle: (v) => setState(() => _useAutoForm = v),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: <Widget>[
          Text('ICP Canister Client', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Connection (optional)'),
            subtitle: const Text('Canister ID and Replica host'),
            children: <Widget>[
              TextField(
                key: const Key('canisterField'),
                controller: _canisterController,
                decoration: const InputDecoration(
                  labelText: 'Canister ID',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Replica Host (optional)',
                  hintText: 'https://ic0.app',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('methodField'),
            controller: _methodController,
            decoration: const InputDecoration(
              labelText: 'Method name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Method kind',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedKind,
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(value: 0, child: Text('Query')),
                  DropdownMenuItem<int>(value: 1, child: Text('Update')),
                  DropdownMenuItem<int>(value: 2, child: Text('Composite Query')),
                ],
                onChanged: (int? v) => setState(() => _selectedKind = v ?? 0),
              ),
            ),
          ),
          const SizedBox(height: 12),
          argsEditor,
          if (_validationErrors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text('Input issues', style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 4),
            ..._validationErrors.map(
              (e) => Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
          if (_expectedJsonExample.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('Expected args (JSON)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SelectableText(_expectedJsonExample),
            ),
          ],
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Authenticated (optional)'),
            subtitle: const Text('Ed25519 private key (base64)'),
            children: <Widget>[
              TextField(
                controller: _identityKeyController,
                decoration: const InputDecoration(
                  labelText: 'Private key (base64)',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _isFetching ? null : _fetchAndParse,
                  child: _isFetching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Fetch & List Methods'),
                ),
              ),
              const SizedBox(width: 8),
              if (_candidRaw != null)
                OutlinedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Candid (raw)'),
                        content: SingleChildScrollView(child: SelectableText(_candidRaw!)),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                  child: const Text('View Candid'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Call method'),
            onPressed: () {
              final String cid = _canisterController.text.trim();
              final String method = _methodController.text.trim();
              if (cid.isEmpty || method.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter canister and method')));
                return;
              }
              final String args = _jsonArgsController.text.trim();
              // Live validation before sending
              if (_resolvedArgs.isNotEmpty) {
                final v = validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: args);
                setState(() => _validationErrors = v.errors);
                if (!v.ok) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fix input errors')));
                  return;
                }
              }
                // Fail-fast check: do not allow accidental empty JSON for single-arg non-empty types
                if (_resolvedArgs.length == 1 && args.isEmpty) {
                  setState(() => _validationErrors = <String>['(root) expected value for ${_resolvedArgs.first}']);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide argument value')));
                  return;
                }
              final String? host = _hostController.text.trim().isEmpty ? null : _hostController.text.trim();
              final String key = _identityKeyController.text.trim();
              String? out;
              if (key.isEmpty) {
                out = widget.bridge.callAnonymous(
                  canisterId: cid,
                  method: method,
                  kind: _selectedKind,
                  args: args,
                  host: host,
                );
              } else {
                out = widget.bridge.callAuthenticated(
                  canisterId: cid,
                  method: method,
                  kind: _selectedKind,
                  privateKeyB64: key,
                  args: args,
                  host: host,
                );
              }
              setState(() {
                final raw = out ?? '';
                _resultJson = raw.isEmpty ? '' : formatJsonIfPossible(raw);
              });
            },
          ),
          if ((_resultJson ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('Result (JSON)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SelectableText(_resultJson!),
            ),
          ],
          const SizedBox(height: 12),
          if (_methods.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Methods', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _methods.length,
                  separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final m = _methods[index];
                    final String name = m['name'] as String;
                    final String kind = (m['kind'] as String).toString();
                    final List<String> args = (m['args'] as List<dynamic>).cast<String>();
                    final List<String> rets = (m['rets'] as List<dynamic>).cast<String>();
                    final String sig = '(${args.join(', ')}) -> (${rets.join(', ')})';
                    return ListTile(
                      leading: Icon(
                        kind.toLowerCase().contains('update') ? Icons.sync_alt : Icons.search,
                      ),
                      title: Text(name),
                      subtitle: Text('$kind • $sig'),
                      trailing: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Use method',
                            icon: const Icon(Icons.input),
                          onPressed: () {
                              _methodController.text = name;
                              setState(() {
                                _selectedKind = kind.toLowerCase().contains('update')
                                    ? 1
                                    : (kind.toLowerCase().contains('composite') ? 2 : 0);
                              final resolver = CandidTypeResolver(_candidRaw ?? '');
                              _resolvedArgs = resolver.resolveArgTypes(args);
                              _currentMethodSig = _resolvedArgs
                                  .asMap()
                                  .entries
                                  .map((e) => {'name': 'arg${e.key}', 'type': e.value})
                                  .toList();
                              _expectedJsonExample = buildJsonExampleForArgs(_resolvedArgs);
                              _jsonArgsController.text = _expectedJsonExample;
                              final v = validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: _jsonArgsController.text.trim());
                              _validationErrors = v.errors;
                              _useAutoForm = false;
                              });
                            },
                          ),
                          IconButton(
                            tooltip: 'Favorite',
                            icon: const Icon(Icons.favorite_border),
                            onPressed: () {
                              final cid = _canisterController.text.trim();
                              if (cid.isEmpty) return;
                              widget.bridge.favoritesAdd(canisterId: cid, method: name);
                              FavoritesEvents.notifyChanged();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to favorites')));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text('Well-known canisters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _WellKnownList(onSelect: (cid, method) {
            _canisterController.text = cid;
            _methodController.text = method;
          }),
          const SizedBox(height: 16),
          Text('Favorites', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _FavoritesList(
            bridge: widget.bridge,
            onTapEntry: (cid, method) {
              _canisterController.text = cid;
              _methodController.text = method;
            },
          ),
        ],
      ),
    );
  }
}

class _ArgsEditor extends StatefulWidget {
  const _ArgsEditor({
    required this.useAuto,
    required this.argTypes,
    required this.controller,
    required this.onToggle,
  });
  final bool useAuto;
  final List<String> argTypes;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;
  // Note: parent listens to controller and shows errors; keeping API minimal

  @override
  State<_ArgsEditor> createState() => _ArgsEditorState();
}

class _ArgsEditorState extends State<_ArgsEditor> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.argTypes.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void didUpdateWidget(covariant _ArgsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.argTypes.length != widget.argTypes.length) {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = List<TextEditingController>.generate(
        widget.argTypes.length,
        (_) => TextEditingController(),
      );
      _rebuildJson();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildJson() {
    try {
      final model = CandidFormModel(widget.argTypes);
      if (!model.isSupportedByForm || !widget.useAuto) {
        return;
      }
      final List<dynamic> values = <dynamic>[];
      for (int i = 0; i < widget.argTypes.length; i += 1) {
        values.add(_controllers[i].text.trim());
      }
      widget.controller.text = model.buildJson(values);
    } catch (_) {
      // Let the user fall back to raw JSON
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = CandidFormModel(widget.argTypes);

    // Header with toggle
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text('Arguments', style: Theme.of(context).textTheme.titleMedium),
        Row(children: <Widget>[
          const Text('Auto'),
          Switch(value: widget.useAuto, onChanged: widget.onToggle),
        ]),
      ],
    );

    if (!widget.useAuto || widget.argTypes.isEmpty || !model.isSupportedByForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          const SizedBox(height: 8),
          if (!widget.useAuto && widget.argTypes.isNotEmpty)
            const SizedBox.shrink()
          else if (!model.isSupportedByForm)
            const Text('Some argument types are not supported by auto form. Use raw JSON below.'),
          if (widget.argTypes.isEmpty)
            const Text('No input required for this method')
          else
            TextField(
              controller: widget.controller,
              decoration: const InputDecoration(
                labelText: 'Args JSON',
                hintText: '[] for multiple args; object/array/scalar for single arg',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 8,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        header,
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.argTypes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final String t = widget.argTypes[index];
            final String label = 'Arg ${index + 1} ($t)';
            final String lower = t.toLowerCase();
            final TextInputType inputType = (lower.contains('int') || lower.contains('float') || lower.contains('nat'))
                ? TextInputType.number
                : TextInputType.text;
            final String? hint = lower.startsWith('record')
                ? 'JSON object or array matching record fields'
                : (lower.startsWith('vec')
                    ? 'JSON array for vector values'
                    : (lower.startsWith('opt') ? 'Value or null' : null));
            return TextField(
              controller: _controllers[index],
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              keyboardType: inputType,
              onChanged: (_) {
                _rebuildJson();
                // Best-effort live validation comparing built JSON vs expected types
                try {
                  final model = CandidFormModel(widget.argTypes);
                  final List<dynamic> values = _controllers.map((c) => c.text.trim()).toList();
                  final jsonStr = model.buildJson(values);
                  validateJsonArgs(resolvedArgTypes: widget.argTypes, jsonText: jsonStr);
                  // Bubble up? The parent shows errors from main controller text; skip here.
                } catch (_) {}
              },
            );
          },
        ),
      ],
    );
  }
}

class _WellKnownList extends StatelessWidget {
  const _WellKnownList({required this.onSelect});
  final void Function(String canisterId, String method) onSelect;

  static const List<Map<String, String>> _items = <Map<String, String>>[
    // NNS Registry
    {'label': 'NNS Registry', 'cid': 'rwlgt-iiaaa-aaaaa-aaaaa-cai', 'method': 'get_value'},
    // NNS Governance
    {'label': 'NNS Governance', 'cid': 'rrkah-fqaaa-aaaaa-aaaaq-cai', 'method': 'get_neuron_ids'},
    // NNS Ledger
    {'label': 'NNS Ledger', 'cid': 'ryjl3-tyaaa-aaaaa-aaaba-cai', 'method': 'account_balance_dfx'},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final e = _items[index];
        return ListTile(
          leading: const Icon(Icons.star_border),
          title: Text(e['label'] ?? ''),
          subtitle: Text('${e['cid']} • ${e['method']}'),
          onTap: () => onSelect(e['cid'] ?? '', e['method'] ?? ''),
        );
      },
    );
  }
}

class _FavoritesList extends StatefulWidget {
  const _FavoritesList({required this.bridge, required this.onTapEntry});
  final RustBridgeLoader bridge;
  final void Function(String canisterId, String method) onTapEntry;

  @override
  State<_FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<_FavoritesList> {
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _reload();
    _listener = _reload;
    FavoritesEvents.listenable.addListener(_listener);
  }

  @override
  void dispose() {
    FavoritesEvents.listenable.removeListener(_listener);
    super.dispose();
  }

  void _reload() {
    final jsonStr = widget.bridge.favoritesList();
    if (jsonStr == null) return;
    final List<dynamic> arr = json.decode(jsonStr) as List<dynamic>;
    setState(() {
      _entries = arr
          .whereType<Map<String, dynamic>>()
          .map((e) => {
                'canister_id': e['canister_id'] as String? ?? '',
                'method': e['method'] as String? ?? '',
                'label': e['label'] as String?,
              })
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return const Text('No favorites yet');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final e = _entries[index];
        final cid = e['canister_id'] as String;
        final method = e['method'] as String;
        final label = (e['label'] as String?) ?? '';
        return ListTile(
          title: Text(label.isNotEmpty ? label : method),
          subtitle: Text('$cid • $method'),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              widget.bridge.favoritesRemove(canisterId: cid, method: method);
              FavoritesEvents.notifyChanged();
            },
          ),
          onTap: () => widget.onTapEntry(cid, method),
        );
      },
    );
  }
}
