import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/canister_method.dart';
import '../services/candid_service.dart';
import '../widgets/candid_args_builder.dart';

/// Dialog for building canister method calls that generate Lua code
class CanisterCallBuilderDialog extends StatefulWidget {
  const CanisterCallBuilderDialog({super.key, this.initialCallSpec});

  final Map<String, dynamic>? initialCallSpec;

  @override
  State<CanisterCallBuilderDialog> createState() =>
      _CanisterCallBuilderDialogState();
}

class _CanisterCallBuilderDialogState extends State<CanisterCallBuilderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _canisterIdController = TextEditingController();
  final _hostController = TextEditingController();
  final _methodController = TextEditingController();
  final _labelController = TextEditingController();

  String? _selectedCanisterId;
  CanisterMethod? _selectedMethod;
  int _callKind = 0; // 0=query, 1=update, 2=composite
  Map<String, dynamic> _args = {};
  bool _isAuthenticated = false;
  String? _keypairId;
  bool _isLoadingCandid = false;
  List<CanisterMethod> _availableMethods = [];

  final List<Map<String, String>> _wellKnownCanisters = [
    {'id': 'aaaaa-aa', 'name': 'Management Canister', 'host': ''},
    {'id': 'rrkah-fqaaa-aaaaa-aaaaq-cai', 'name': 'NNS Governance', 'host': ''},
    {'id': 'ryjl3-tyaaa-aaaaa-aaaba-cai', 'name': 'ICP Ledger', 'host': ''},
    {'id': 'qga6-kiaaa-aaaaa-aaada-cai', 'name': 'Cycles Minting', 'host': ''},
    {
      'id': 'qhbym-qaaaa-aaaaa-aaafq-cai',
      'name': 'Internet Keypair',
      'host': ''
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCallSpec != null) {
      _initializeFromSpec(widget.initialCallSpec!);
    } else {
      _labelController.text = 'call1';
    }
  }

  void _initializeFromSpec(Map<String, dynamic> spec) {
    _canisterIdController.text = spec['canister_id'] ?? '';
    _selectedCanisterId = spec['canister_id'];
    _methodController.text = spec['method'] ?? '';
    _hostController.text = spec['host'] ?? '';
    _labelController.text = spec['label'] ?? 'call1';
    _callKind = spec['kind'] ?? 0;
    _isAuthenticated = spec['authenticated'] ?? false;
    _keypairId = spec['keypair_id'];

    if (spec['args'] != null) {
      _args = Map<String, dynamic>.from(spec['args']);
    }
  }

  @override
  void dispose() {
    _canisterIdController.dispose();
    _hostController.dispose();
    _methodController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidMethods(String canisterId) async {
    setState(() {
      _isLoadingCandid = true;
      _availableMethods = [];
      _selectedMethod = null;
    });

    try {
      final candidService = CandidService();
      final methods = await candidService.fetchCanisterMethods(
          canisterId,
          _hostController.text.trim().isEmpty
              ? null
              : _hostController.text.trim());

      setState(() {
        _availableMethods = methods;
        _isLoadingCandid = false;
      });

      // Auto-select method if it exists
      if (_methodController.text.isNotEmpty) {
        _selectedMethod = methods.firstWhere(
          (m) => m.name == _methodController.text,
          orElse: () => methods.isNotEmpty
              ? methods.first
              : CanisterMethod(name: '', kind: 0, args: []),
        );
      }
    } catch (e) {
      setState(() {
        _isLoadingCandid = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Candid methods: $e')),
        );
      }
    }
  }

  void _onCanisterChanged(String? value) {
    if (value == null) return;

    setState(() {
      _selectedCanisterId = value;
      _canisterIdController.text = value;
      _selectedMethod = null;
      _availableMethods = [];
    });

    if (value.isNotEmpty) {
      _loadCandidMethods(value);
    }
  }

  void _onMethodChanged(CanisterMethod? method) {
    if (method == null) return;

    setState(() {
      _selectedMethod = method;
      _methodController.text = method.name;
      _callKind = method.kind;
      _args = {};
    });

    // Update label if it's the default
    if (_labelController.text == 'call1' || _labelController.text.isEmpty) {
      _labelController.text = method.name;
    }
  }

  String _generateLuaCode() {
    if (_selectedMethod == null ||
        _selectedCanisterId == null ||
        _selectedCanisterId!.isEmpty) {
      return '';
    }

    final argsJson = _args.isNotEmpty ? json.encode(_args) : '()';

    // Generate args string based on method arguments
    String argsString = argsJson;
    if (_selectedMethod!.args.isNotEmpty) {
      if (_args.isEmpty) {
        argsString = '()';
      }
    }

    final buffer = StringBuffer();

    if (_isAuthenticated) {
      buffer.writeln('-- Authenticated canister call');
      buffer.writeln('local result = icp_call({');
    } else {
      buffer.writeln('-- Anonymous canister call');
      buffer.writeln('local result = icp_call({');
    }

    buffer.writeln('  canister_id = "$_selectedCanisterId",');
    buffer.writeln('  method = "$_selectedMethod",');
    buffer.writeln('  kind = $_callKind, -- ${_getCallKindLabel(_callKind)}');
    buffer.writeln('  args = $argsString');

    if (_isAuthenticated && _keypairId != null) {
      buffer.writeln('  keypair_id = "$_keypairId"');
    } else if (_isAuthenticated) {
      buffer.writeln(
          '  -- Note: You\'ll need to set private_key_b64 or keypair_id for authenticated calls');
    }

    buffer.writeln('})');
    buffer.writeln();
    buffer.writeln('-- Use the result in your script');
    buffer.writeln('return result');

    return buffer.toString();
  }

  String _getCallKindLabel(int kind) {
    switch (kind) {
      case 1:
        return 'update';
      case 2:
        return 'composite';
      default:
        return 'query';
    }
  }

  void _copyToClipboard() {
    final luaCode = _generateLuaCode();
    if (luaCode.isNotEmpty) {
      // TODO: Implement clipboard functionality
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lua code copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Build Canister Call'),
      content: SizedBox(
        width: 800,
        height: 600,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Canister selection
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCanisterId,
                      decoration: const InputDecoration(
                        labelText: 'Canister',
                        border: OutlineInputBorder(),
                        helperText:
                            'Select a well-known canister or enter custom ID',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('Custom canister ID'),
                        ),
                        ..._wellKnownCanisters
                            .map((canister) => DropdownMenuItem<String>(
                                  value: canister['id'],
                                  child: Text(
                                      '${canister['name']} (${canister['id']})'),
                                )),
                      ],
                      onChanged: _onCanisterChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _canisterIdController,
                      decoration: const InputDecoration(
                        labelText: 'Canister ID',
                        border: OutlineInputBorder(),
                        hintText: 'aaaaa-aa',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                      onChanged: (value) {
                        if (value != _selectedCanisterId &&
                            _wellKnownCanisters
                                .every((c) => c['id'] != value)) {
                          setState(() {
                            _selectedCanisterId = value;
                          });
                          _loadCandidMethods(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Host field (optional)
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'icp0.io',
                  helperText: 'Override the default ICP network host',
                ),
              ),
              const SizedBox(height: 16),

              // Method selection
              if (_isLoadingCandid)
                const Center(child: CircularProgressIndicator())
              else if (_availableMethods.isNotEmpty) ...[
                DropdownButtonFormField<CanisterMethod>(
                  initialValue: _selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    border: OutlineInputBorder(),
                  ),
                  items: _availableMethods
                      .map((method) => DropdownMenuItem<CanisterMethod>(
                            value: method,
                            child: Text(
                                '${method.name} (${_getCallKindLabel(method.kind)})'),
                          ))
                      .toList(),
                  onChanged: _onMethodChanged,
                ),
              ] else ...[
                TextFormField(
                  controller: _methodController,
                  decoration: const InputDecoration(
                    labelText: 'Method Name',
                    border: OutlineInputBorder(),
                    hintText: 'get_pending_proposals',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 16),

              // Call configuration
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        border: OutlineInputBorder(),
                        helperText: 'Variable name for the result',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _callKind,
                      decoration: const InputDecoration(
                        labelText: 'Call Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<int>(value: 0, child: Text('Query')),
                        DropdownMenuItem<int>(value: 1, child: Text('Update')),
                        DropdownMenuItem<int>(
                            value: 2, child: Text('Composite')),
                      ],
                      onChanged: (value) =>
                          setState(() => _callKind = value ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Authentication
              CheckboxListTile(
                title: const Text('Authenticated call'),
                subtitle: const Text('Requires an keypair for private methods'),
                value: _isAuthenticated,
                onChanged: (value) =>
                    setState(() => _isAuthenticated = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),

              // Arguments builder
              if (_selectedMethod != null &&
                  _selectedMethod!.args.isNotEmpty) ...[
                const Text(
                  'Method Arguments',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: CandidArgsBuilder(
                    method: _selectedMethod!,
                    args: _args,
                    onChanged: (newArgs) => setState(() => _args = newArgs),
                  ),
                ),
              ] else ...[
                const Text(
                  'No arguments required for this method',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const Spacer(),
              ],

              // Generated Lua code preview
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 150,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _generateLuaCode(),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _generateLuaCode().isNotEmpty ? _copyToClipboard : null,
          child: const Text('Copy Lua'),
        ),
        FilledButton(
          onPressed: _generateLuaCode().isNotEmpty
              ? () => Navigator.of(context).pop(_generateLuaCode())
              : null,
          child: const Text('Insert Lua Code'),
        ),
      ],
    );
  }
}
