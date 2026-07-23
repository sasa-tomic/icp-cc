import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/well_known_canisters.dart';
import '../models/canister_method.dart';
import '../services/candid_service.dart';
import '../utils/friendly_error.dart';
import '../utils/tech_terms.dart';
import '../widgets/candid_args_builder.dart';

/// Dialog for building canister method calls that generate a TypeScript snippet
class CanisterCallBuilderDialog extends StatefulWidget {
  const CanisterCallBuilderDialog({super.key, this.initialCallSpec});

  final Map<String, dynamic>? initialCallSpec;

  @override
  State<CanisterCallBuilderDialog> createState() =>
      _CanisterCallBuilderDialogState();

  /// UX-H12: pure snippet generator. Extracted from the State's `_generateBundle`
  /// so the contract is testable without pumping the dialog (the dialog ships
  /// with a fixed 800x600 SizedBox + long canister names that overflow the
  /// default test surface — testing the generator directly is faster,
  /// deterministic, and orthogonal to those layout issues).
  ///
  /// Emits the script-app host contract directly: an `icp_call` literal with
  /// `authenticated: true,` when [isAuthenticated]. The bundle NEVER carries
  /// raw key material — the host resolves the auth flag to the active profile
  /// keypair.
  @visibleForTesting
  static String generateBundle({
    required String? canisterId,
    required String? methodName,
    required int callMode,
    required String argsString,
    required bool isAuthenticated,
  }) {
    if (canisterId == null ||
        canisterId.isEmpty ||
        methodName == null ||
        methodName.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();

    if (isAuthenticated) {
      buffer.writeln('// Authenticated canister call');
    } else {
      buffer.writeln('// Anonymous canister call');
    }
    buffer.writeln('const result = icp_call({');
    buffer.writeln('  canister_id: "$canisterId",');
    buffer.writeln('  method: "$methodName",');
    buffer.writeln('  mode: $callMode, // ${_callModeLabel(callMode)}');
    buffer.writeln('  args: $argsString');

    // UX-H12: emit the host contract directly. The script-app host
    // (script_app_host.dart) resolves `authenticated: true` to the active
    // profile keypair; the bundle NEVER carries raw key material. Previously
    // this emitted a broken `keypair_id: "<id>"` (no such host field) plus a
    // 'set private_key_b64 or keypair_id' comment that produced a non-running
    // snippet.
    if (isAuthenticated) {
      buffer.writeln('  authenticated: true,');
    }

    buffer.writeln('});');
    buffer.writeln();
    buffer.writeln('// Use the result in your script');
    buffer.writeln('return result;');

    return buffer.toString();
  }

  static String _callModeLabel(int mode) {
    switch (mode) {
      case 1:
        return 'update';
      case 2:
        return 'composite';
      default:
        return 'query';
    }
  }

  /// UX-H11: builds the dropdown's full items list (the "Custom canister
  /// ID" placeholder plus one entry per canonical well-known canister).
  ///
  /// Shared by the Call Builder dialog, the Canister Client autocomplete, AND
  /// the Frontend Scaffold dialog — every "pick a canister" surface honors the
  /// single source of truth ([WellKnownCanister.all], no more, no less).
  ///
  /// Extracted as a static so the regression test can pin the single-source
  /// property without pumping the full dialog — the dialog ships with a fixed
  /// 800x600 SizedBox that overflows at the default test surface, mirroring
  /// the same pattern used for the snippet generator (`generateBundle` above).
  ///
  /// Before UX-H11 this list was a divergent 5-entry hard-coded const that
  /// omitted ICLighthouse / Cyql / Kinic / Canistergeek; the regression
  /// test in `canister_call_builder_dropdown_test.dart` fails loudly if a
  /// future change re-forks it.
  static List<DropdownMenuItem<String>> buildWellKnownDropdownItems() {
    return <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Custom canister ID'),
      ),
      ...WellKnownCanister.all.map(
        (canister) => DropdownMenuItem<String>(
          value: canister.canisterId,
          child: Text('${canister.label} (${canister.canisterId})'),
        ),
      ),
    ];
  }
}

class _CanisterCallBuilderDialogState extends State<CanisterCallBuilderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _canisterIdController = TextEditingController();
  final _hostController = TextEditingController();
  final _methodController = TextEditingController();
  final _labelController = TextEditingController();

  String? _selectedCanisterId;
  CanisterMethod? _selectedMethod;
  int _callMode = 0; // 0=query, 1=update, 2=composite
  Map<String, dynamic> _args = {};
  bool _isAuthenticated = false;
  bool _isLoadingCandid = false;
  List<CanisterMethod> _availableMethods = [];

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
    _callMode = spec['mode'] ?? 0;
    _isAuthenticated = spec['authenticated'] ?? false;

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
               : CanisterMethod(name: '', mode: 0, args: []),
        );
      }
    } on CandidFetchException catch (e) {
      setState(() {
        _isLoadingCandid = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } catch (e) {
      setState(() {
        _isLoadingCandid = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyErrorMessage(e,
                  context: 'Failed to load Candid methods'))),
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
      _callMode = method.mode;
      _args = {};
    });

    // Update label if it's the default
    if (_labelController.text == 'call1' || _labelController.text.isEmpty) {
      _labelController.text = method.name;
    }
  }

  String _generateBundle() {
    // Prefer the structured [CanisterMethod] (loaded from Candid), but fall
    // back to the manually-typed method name so the snippet is functional
    // even when the canister interface couldn't be fetched. UX-H12: a
    // functional snippet is the user-visible contract — never an empty
    // preview when the user has clearly entered both a canister and method.
    final String typedMethod = _methodController.text.trim();
    final String? methodName =
        _selectedMethod?.name ?? (typedMethod.isEmpty ? null : typedMethod);

    // The script-app host accepts an inline JSON argument or `()` for zero-arg
    // methods. When the user has built structured args via the form, emit them;
    // otherwise emit `()` for zero-arg methods.
    final String argsJson = _args.isNotEmpty ? json.encode(_args) : '()';
    final String argsString =
        (_selectedMethod?.args.isNotEmpty ?? false) && _args.isEmpty
            ? '()'
            : argsJson;

    return CanisterCallBuilderDialog.generateBundle(
      canisterId: _selectedCanisterId,
      methodName: methodName,
      callMode: _callMode,
      argsString: argsString,
      isAuthenticated: _isAuthenticated,
    );
  }

  Future<void> _copyToClipboard() async {
    final snippet = _generateBundle();
    if (snippet.isNotEmpty) {
      // Capture before the await (the dialog may close while we yield).
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: snippet));
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Snippet copied to clipboard!')),
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
              Row(
                children: [
                  Text(
                    'Canister',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: TechTerm.canister.fullExplanation,
                    preferBelow: true,
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCanisterId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        helperText:
                            'Select a well-known canister or enter custom ID',
                      ),
                      items: CanisterCallBuilderDialog.buildWellKnownDropdownItems(),
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
                            WellKnownCanister.all
                                .every((c) => c.canisterId != value)) {
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
                                  '${method.name} (${CanisterCallBuilderDialog._callModeLabel(method.mode)})'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Call Type',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 4),
                            Tooltip(
                              message:
                                  '${TechTerm.query.fullExplanation}\n\n${TechTerm.update.fullExplanation}',
                              preferBelow: true,
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _callMode,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem<int>(
                              value: 0,
                              child: Row(
                                children: [
                                  const Text('Read'),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: TechTerm.query.plainExplanation,
                                    child: Icon(Icons.info_outline,
                                        size: 14, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem<int>(
                              value: 1,
                              child: Row(
                                children: [
                                  const Text('Write'),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: TechTerm.update.plainExplanation,
                                    child: Icon(Icons.info_outline,
                                        size: 14, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            const DropdownMenuItem<int>(
                                value: 2, child: Text('Complex Read')),
                          ],
                          onChanged: (value) =>
                              setState(() => _callMode = value ?? 0),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Tooltip(
                message: TechTerm.keypair.fullExplanation,
                preferBelow: true,
                child: CheckboxListTile(
                  title: const Text('Authenticated call'),
                  subtitle:
                      const Text('Requires a keypair for private methods'),
                  value: _isAuthenticated,
                  onChanged: (value) =>
                      setState(() => _isAuthenticated = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
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

              // Generated TypeScript snippet preview
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
                    _generateBundle(),
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
          onPressed: _generateBundle().isNotEmpty ? _copyToClipboard : null,
          child: const Text('Copy Snippet'),
        ),
        FilledButton(
          onPressed: _generateBundle().isNotEmpty
              ? () => Navigator.of(context).pop(_generateBundle())
              : null,
          child: const Text('Insert Snippet'),
        ),
      ],
    );
  }
}
