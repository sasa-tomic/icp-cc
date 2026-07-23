import 'package:flutter/material.dart';

import '../config/well_known_canisters.dart';
import '../models/canister_method.dart';
import '../services/candid_service.dart';
import '../services/frontend_scaffold_generator.dart';
import '../utils/friendly_error.dart';
import 'canister_call_builder.dart';

/// Result of [FrontendScaffoldDialog]: the generated bundle source plus the
/// connection values to feed the host's `initialArg`.
class FrontendScaffoldResult {
  const FrontendScaffoldResult({
    required this.bundle,
    required this.canisterId,
    required this.host,
    required this.methodCount,
  });

  final String bundle;
  final String canisterId;
  final String host;
  final int methodCount;
}

/// Phase 1 entry point ("Scaffold frontend from canister"): paste any canister
/// id, the app loads its Candid interface (via the certified `read_state` path
/// fixed in WS-1a), then [FrontendScaffoldGenerator] emits a starter
/// one-button-per-method UI bundle ready to run.
///
/// The canister-id + well-known catalog reuse
/// [CanisterCallBuilderDialog.buildWellKnownDropdownItems] so the single source
/// of truth ([WellKnownCanister.all]) is honored here too.
class FrontendScaffoldDialog extends StatefulWidget {
  const FrontendScaffoldDialog({super.key, this.candidService});

  /// Production leaves this null (the dialog constructs a default
  /// [CandidService]); tests inject one with a fake `fetchCandid` to drive the
  /// generate flow without the real FFI / network.
  final CandidService? candidService;

  @override
  State<FrontendScaffoldDialog> createState() => _FrontendScaffoldDialogState();
}

class _FrontendScaffoldDialogState extends State<FrontendScaffoldDialog> {
  final _formKey = GlobalKey<FormState>();
  final _canisterIdController = TextEditingController();
  final _hostController = TextEditingController(text: 'https://ic0.app');

  bool _loading = false;
  String? _error;
  List<CanisterMethod> _previewMethods = const [];

  @override
  void dispose() {
    _canisterIdController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  String get _canisterId => _canisterIdController.text.trim();
  String get _host => _hostController.text.trim();

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _previewMethods = const [];
    });
    try {
      final service = widget.candidService ?? CandidService();
      final methods = await service.fetchCanisterMethods(_canisterId, _host);
      if (!mounted) return;
      if (methods.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No methods found in the Candid interface for '
              '$_canisterId.';
        });
        return;
      }
      final bundle = const FrontendScaffoldGenerator().generateBundle(
        canisterId: _canisterId,
        methods: methods,
        host: _host,
      );
      if (!mounted) return;
      Navigator.of(context).pop(FrontendScaffoldResult(
        bundle: bundle,
        canisterId: _canisterId,
        host: _host,
        methodCount: methods.length,
      ));
    } on CandidFetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e,
            context: 'Failed to generate a frontend scaffold');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Scaffold frontend from canister'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste any canister id — the app loads its Candid interface and '
                'generates a starter UI with one callable section per method. '
                'Zero-arg queries work immediately.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Well-known canister',
                  border: OutlineInputBorder(),
                  helperText: 'Or type a custom id below',
                ),
                items: CanisterCallBuilderDialog.buildWellKnownDropdownItems(),
                onChanged: (value) {
                  if (value == null || value.isEmpty) return;
                  setState(() {
                    _canisterIdController.text = value;
                    _error = null;
                    _previewMethods = const [];
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _canisterIdController,
                decoration: const InputDecoration(
                  labelText: 'Canister ID',
                  border: OutlineInputBorder(),
                  hintText: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Required' : null,
                onChanged: (_) {
                  if (_error != null || _previewMethods.isNotEmpty) {
                    setState(() {
                      _error = null;
                      _previewMethods = const [];
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'https://ic0.app',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: theme.colorScheme.error, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _generate,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
