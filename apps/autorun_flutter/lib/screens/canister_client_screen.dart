import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/native_bridge.dart';
import '../services/bookmarks_service.dart';
import '../services/canister_history_service.dart';
import '../services/canister_registry_service.dart';
import '../utils/candid_form_model.dart';
import '../utils/candid_json_example.dart';
import '../utils/candid_json_validate.dart';
import '../utils/candid_type_resolver.dart';
import '../utils/json_format.dart';
import '../utils/tech_terms.dart';

enum _ClientStep { canister, function, call }

class CanisterClientScreen extends StatefulWidget {
  const CanisterClientScreen({
    super.key,
    required this.bridge,
    this.initialCanisterId,
    this.initialMethodName,
  });

  final RustBridgeLoader bridge;
  final String? initialCanisterId;
  final String? initialMethodName;

  @override
  State<CanisterClientScreen> createState() => _CanisterClientScreenState();
}

class _CanisterClientScreenState extends State<CanisterClientScreen> {
  _ClientStep _currentStep = _ClientStep.canister;
  final TextEditingController _canisterController = TextEditingController();
  final FocusNode _canisterFocusNode = FocusNode();
  final TextEditingController _hostController =
      TextEditingController(text: 'https://ic0.app');
  final TextEditingController _methodController = TextEditingController();
  final TextEditingController _keypairKeyController = TextEditingController();
  int _selectedKind = 0;
  final TextEditingController _jsonArgsController = TextEditingController();
  bool _useAutoForm = true;
  List<Map<String, dynamic>> _currentMethodSig = const <Map<String, dynamic>>[];
  String? _resultJson;
  String? _candidRaw;
  List<Map<String, dynamic>> _methods = const <Map<String, dynamic>>[];
  bool _isFetching = false;
  String _expectedJsonExample = '';
  List<String> _resolvedArgs = const <String>[];
  List<String> _validationErrors = const <String>[];
  Map<String, dynamic>? _selectedMethod;
  String? _errorMessage;
  List<CanisterCallRecord> _callHistory = [];

  void _onArgsChanged() {
    if (_resolvedArgs.isEmpty) return;
    final String args = _jsonArgsController.text.trim();
    try {
      final v =
          validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: args);
      if (mounted) setState(() => _validationErrors = v.errors);
    } catch (e) {
      if (mounted) {
        setState(() => _validationErrors = <String>['Validation error: $e']);
      }
    }
  }

  @override
  void dispose() {
    _canisterController.dispose();
    _canisterFocusNode.dispose();
    _hostController.dispose();
    _methodController.dispose();
    _keypairKeyController.dispose();
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
    if (_canisterController.text.trim().isNotEmpty) {
      scheduleMicrotask(_fetchAndParse);
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await CanisterHistoryService().getHistory();
    if (mounted) {
      setState(() => _callHistory = history);
    }
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _isFetching = false;
    });
  }

  void _clearError() {
    setState(() => _errorMessage = null);
  }

  String _friendlyError(dynamic error) {
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('not found') || errStr.contains('404')) {
      return 'Canister not found. Please check the ID.';
    }
    if (errStr.contains('timeout') || errStr.contains('timed out')) {
      return 'Connection timed out. Please try again.';
    }
    if (errStr.contains('network') || errStr.contains('connection refused')) {
      return 'Network error. Please check your connection.';
    }
    if (errStr.contains('invalid') && errStr.contains('candid')) {
      return 'This canister does not expose a public interface.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _fetchAndParse() async {
    final String cid = _canisterController.text.trim();
    if (cid.isEmpty || _isFetching) return;
    _clearError();
    setState(() {
      _isFetching = true;
    });
    try {
      final String? did = await widget.bridge.fetchCandid(
        canisterId: cid,
        host: _hostController.text.trim().isEmpty
            ? null
            : _hostController.text.trim(),
      );
      if (did == null || did.trim().isEmpty) {
        if (!mounted) return;
        _setError('Could not load canister interface.');
        return;
      }
      final String? parsedJson = widget.bridge.parseCandid(candidText: did);
      if (parsedJson == null) {
        if (!mounted) return;
        _setError('Could not read canister interface.');
        return;
      }
      final Map<String, dynamic> parsed =
          json.decode(parsedJson) as Map<String, dynamic>;
      final List<dynamic> methods =
          (parsed['methods'] as List<dynamic>? ?? <dynamic>[]);
      setState(() {
        _candidRaw = did;
        _methods = methods
            .whereType<Map<String, dynamic>>()
            .map((m) => {
                  'name': m['name'] as String? ?? '',
                  'kind': m['kind'] as String? ?? '',
                  'args': (m['args'] as List<dynamic>? ?? const <dynamic>[])
                      .map((e) => e.toString())
                      .toList(),
                  'rets': (m['rets'] as List<dynamic>? ?? const <dynamic>[])
                      .map((e) => e.toString())
                      .toList(),
                })
            .toList();
        _isFetching = false;
      });
      final String preset = _methodController.text.trim();
      if (preset.isNotEmpty) {
        _selectMethodByName(preset);
      }
    } catch (e) {
      if (!mounted) return;
      _setError(_friendlyError(e));
    } finally {
      if (mounted && _isFetching) setState(() => _isFetching = false);
    }
  }

  void _selectMethodByName(String name) {
    final selected = _methods.cast<Map<String, dynamic>?>().firstWhere(
          (m) => (m?['name'] as String? ?? '') == name,
          orElse: () => null,
        );
    if (selected != null) {
      _selectMethod(selected);
    }
  }

  void _selectMethod(Map<String, dynamic> method) {
    final String kind = (method['kind'] as String).toLowerCase();
    final int kindIndex =
        kind.contains('update') ? 1 : (kind.contains('composite') ? 2 : 0);
    final resolver = CandidTypeResolver(_candidRaw ?? '');
    final args = (method['args'] as List<dynamic>).cast<String>();
    final resolvedArgs = resolver.resolveArgTypes(args);
    setState(() {
      _selectedMethod = method;
      _methodController.text = method['name'] as String;
      _selectedKind = kindIndex;
      _resolvedArgs = resolvedArgs;
      _currentMethodSig = resolvedArgs
          .asMap()
          .entries
          .map((e) => {'name': 'arg${e.key}', 'type': e.value})
          .toList();
      _expectedJsonExample = buildJsonExampleForArgs(_resolvedArgs);
      _jsonArgsController.text = _expectedJsonExample;
      _validationErrors = const <String>[];
      _useAutoForm = true;
      _resultJson = null;
    });
    final v = validateJsonArgs(
        resolvedArgTypes: _resolvedArgs,
        jsonText: _jsonArgsController.text.trim());
    if (v.errors.isNotEmpty) {
      setState(() => _validationErrors = v.errors);
    }
  }

  void _callMethod() async {
    final String cid = _canisterController.text.trim();
    final String method = _methodController.text.trim();
    if (cid.isEmpty || method.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a canister and function')));
      return;
    }
    final String args = _jsonArgsController.text.trim();
    if (_resolvedArgs.isNotEmpty) {
      final v =
          validateJsonArgs(resolvedArgTypes: _resolvedArgs, jsonText: args);
      setState(() => _validationErrors = v.errors);
      if (!v.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please fix the input errors')));
        return;
      }
    }
    if (_resolvedArgs.length == 1 && args.isEmpty) {
      setState(() =>
          _validationErrors = <String>['Please provide a value for the input']);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please provide input')));
      return;
    }
    final String? host = _hostController.text.trim().isEmpty
        ? null
        : _hostController.text.trim();
    final String key = _keypairKeyController.text.trim();
    String? out;
    CallType callType = _selectedKind == 1
        ? CallType.update
        : (_selectedKind == 2 ? CallType.compositeQuery : CallType.query);
    try {
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
      await CanisterHistoryService().addCall(
        canisterId: cid,
        methodName: method,
        arguments: args,
        callType: callType,
        resultSummary: 'success',
      );
    } catch (e) {
      await CanisterHistoryService().addCall(
        canisterId: cid,
        methodName: method,
        arguments: args,
        callType: callType,
        resultSummary: 'error: ${e.toString()}',
      );
      rethrow;
    }
    await _loadHistory();
  }

  void _goToStep(_ClientStep step) {
    setState(() => _currentStep = step);
  }

  bool get _canProceedFromStep1 =>
      _methods.isNotEmpty && _errorMessage == null && !_isFetching;

  bool get _canProceedFromStep2 => _selectedMethod != null;

  String _stepTitle(_ClientStep step) {
    switch (step) {
      case _ClientStep.canister:
        return TechTerm.canister.plainLabel;
      case _ClientStep.function:
        return 'Function';
      case _ClientStep.call:
        return 'Call';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('closeButton'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _ClientStep.values.length; i++) ...[
                _buildStepIndicator(
                  stepNumber: i + 1,
                  stepName: _stepTitle(_ClientStep.values[i]),
                  isActive: _ClientStep.values[i] == _currentStep,
                  isCompleted: _ClientStep.values[i].index < _currentStep.index,
                ),
                if (i < _ClientStep.values.length - 1)
                  Container(
                    width: 24,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: _ClientStep.values[i + 1].index <= _currentStep.index
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                  ),
              ],
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: theme.colorScheme.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildCurrentStepContent(theme),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomNavigation(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator({
    required int stepNumber,
    required String stepName,
    required bool isActive,
    required bool isCompleted,
  }) {
    final theme = Theme.of(context);
    final color = isActive || isCompleted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? theme.colorScheme.primary
                : (isCompleted
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : Colors.transparent),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 14, color: color)
                : Text(
                    '$stepNumber',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? theme.colorScheme.onPrimary : color,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Step $stepNumber: $stepName',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent(ThemeData theme) {
    switch (_currentStep) {
      case _ClientStep.canister:
        return _buildStep1Content(theme);
      case _ClientStep.function:
        return _buildStep2Content(theme);
      case _ClientStep.call:
        return _buildStep3Content(theme);
    }
  }

  Widget _buildStep1Content(ThemeData theme) {
    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select ${TechTerm.canister.plainLabel}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: TechTerm.canister.plainExplanation,
              preferBelow: true,
              showDuration: const Duration(seconds: 5),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          TechTerm.canister.plainExplanation,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Tooltip(
          message:
              'Enter the canister ID (e.g., ryjl3-tyaaa-aaaaa-aaaba-cai) or name.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              return RawAutocomplete<CanisterRegistryEntry>(
                key: const Key('canisterAutocomplete'),
                textEditingController: _canisterController,
                focusNode: _canisterFocusNode,
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<CanisterRegistryEntry>.empty();
                  }
                  return CanisterRegistryEntry.search(textEditingValue.text);
                },
                displayStringForOption: (option) => option.canisterId,
                fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  return TextField(
                    key: const Key('canisterField'),
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: TechTerm.canister.plainLabel,
                      hintText: 'Enter canister ID or name',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isFetching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _methods.isNotEmpty
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : null,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _fetchAndParse(),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                          maxHeight: 280,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              key: Key(
                                  'autocompleteOption_${option.canisterId}'),
                              onTap: () => onSelected(option),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.storage,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            option.name,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme.primaryContainer
                                                .withValues(alpha: 0.5),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            option.category,
                                            style: theme.textTheme.labelSmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      option.canisterId,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontFamily: 'monospace',
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      option.description,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (option) {
                  _canisterController.text = option.canisterId;
                  _fetchAndParse();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildQuickStartSection(theme),
        const SizedBox(height: 24),
        _buildHistorySection(theme),
      ],
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Calls', style: theme.textTheme.titleMedium),
            if (_callHistory.isNotEmpty)
              TextButton.icon(
                key: const Key('clearHistoryButton'),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear'),
                onPressed: () async {
                  await CanisterHistoryService().clearHistory();
                  await _loadHistory();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_callHistory.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.history,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No recent calls. Your call history will appear here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            key: const Key('callHistoryList'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _callHistory.length > 10 ? 10 : _callHistory.length,
            itemBuilder: (context, index) {
              final record = _callHistory[index];
              return _HistoryListItem(
                record: record,
                onTap: () => _replayFromHistory(record),
              );
            },
          ),
      ],
    );
  }

  void _replayFromHistory(CanisterCallRecord record) {
    _canisterController.text = record.canisterId;
    _methodController.text = record.methodName;
    _jsonArgsController.text = record.arguments;
    _fetchAndParse();
  }

  Widget _buildQuickStartSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Start', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Choose a popular canister to get started:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickCanisterChip(
              label: 'NNS Ledger',
              canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
              onTap: () {
                _canisterController.text = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
                _fetchAndParse();
              },
            ),
            _QuickCanisterChip(
              label: 'NNS Governance',
              canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
              onTap: () {
                _canisterController.text = 'rrkah-fqaaa-aaaaa-aaaaq-cai';
                _fetchAndParse();
              },
            ),
            _QuickCanisterChip(
              label: 'Canista',
              canisterId: 'k7gat-daaaa-aaaae-qaahq-cai',
              onTap: () {
                _canisterController.text = 'k7gat-daaaa-aaaae-qaahq-cai';
                _fetchAndParse();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2Content(ThemeData theme) {
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Function',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _canisterController.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Change'),
              onPressed: () => _goToStep(_ClientStep.canister),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_methods.isEmpty)
          const Center(child: Text('No methods available'))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _methods.map((m) {
              final name = m['name'] as String;
              final kind = (m['kind'] as String).toLowerCase();
              final isSelected = _selectedMethod?['name'] == name;
              final isUpdate = kind.contains('update');
              final isComposite = kind.contains('composite');
              return FilterChip(
                key: Key('methodChip_$name'),
                label: Text(name),
                selected: isSelected,
                avatar: Icon(
                  isUpdate
                      ? Icons.sync_alt
                      : (isComposite ? Icons.merge_type : Icons.search),
                  size: 16,
                  color: isSelected
                      ? theme.colorScheme.onSecondaryContainer
                      : (isUpdate
                          ? Colors.orange
                          : (isComposite
                              ? Colors.purple
                              : theme.colorScheme.primary)),
                ),
                onSelected: (_) => _selectMethod(m),
                selectedColor: theme.colorScheme.secondaryContainer,
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStep3Content(ThemeData theme) {
    return Column(
      key: const ValueKey('step3'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call ${_methodController.text}',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _canisterController.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Change'),
              onPressed: () => _goToStep(_ClientStep.function),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInputSection(theme),
        const SizedBox(height: 16),
        _buildAdvancedOptions(theme),
        const SizedBox(height: 16),
        _buildCallInfo(theme),
        if ((_resultJson ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildResultSection(theme),
        ],
      ],
    );
  }

  Widget _buildInputSection(ThemeData theme) {
    if (_resolvedArgs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('No input required', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Input', style: theme.textTheme.titleMedium),
            TextButton.icon(
              icon: Icon(
                _useAutoForm ? Icons.code : Icons.edit_note,
                size: 18,
              ),
              label: Text(_useAutoForm ? 'JSON' : 'Form'),
              onPressed: () => setState(() => _useAutoForm = !_useAutoForm),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ArgsEditor(
          useAuto: _useAutoForm,
          argTypes: _currentMethodSig.map((m) => m['type'] as String).toList(),
          controller: _jsonArgsController,
          onToggle: (v) => setState(() => _useAutoForm = v),
        ),
        if (_validationErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _validationErrors
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: theme.colorScheme.error, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(e,
                                  style: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedOptions(ThemeData theme) {
    return ExpansionTile(
      key: const Key('advancedOptionsTile'),
      title: const Text('Advanced Options'),
      subtitle: const Text('Custom host, authentication, raw Candid'),
      initiallyExpanded: false,
      children: <Widget>[
        const SizedBox(height: 8),
        TextField(
          controller: _hostController,
          decoration: const InputDecoration(
            labelText: 'Custom Host',
            hintText: 'https://ic0.app (default)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keypairKeyController,
          decoration: const InputDecoration(
            labelText: 'Private Key (for authenticated calls)',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        if (_candidRaw != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.code, size: 18),
            label: const Text('View Raw Candid'),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Candid Interface'),
                  content:
                      SingleChildScrollView(child: SelectableText(_candidRaw!)),
                  actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCallInfo(ThemeData theme) {
    final kindLabel = _selectedKind == 1
        ? TechTerm.update.plainLabel
        : (_selectedKind == 2 ? 'Complex Read' : TechTerm.query.plainLabel);
    final kindColor = _selectedKind == 1
        ? Colors.orange
        : (_selectedKind == 2 ? Colors.purple : theme.colorScheme.primary);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kindColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kindColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _selectedKind == 1
                ? Icons.sync_alt
                : (_selectedKind == 2 ? Icons.merge_type : Icons.search),
            color: kindColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      kindLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: kindColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: _selectedKind == 1
                          ? TechTerm.update.fullExplanation
                          : TechTerm.query.fullExplanation,
                      preferBelow: true,
                      showDuration: const Duration(seconds: 5),
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: kindColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                Text(
                  _selectedKind == 1
                      ? 'Will modify service state'
                      : 'Read-only operation',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_border, size: 18),
            label: const Text('Save'),
            onPressed: () async {
              final cid = _canisterController.text.trim();
              if (cid.isEmpty || _selectedMethod == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await BookmarksService.add(
                    canisterId: cid, method: _methodController.text.trim());
                if (mounted) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Saved to bookmarks')));
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Failed to save: $e')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Result', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy result',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _resultJson ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _resultJson ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigation(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep != _ClientStep.canister)
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('backButton'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                onPressed: () {
                  final prevIndex = _currentStep.index - 1;
                  if (prevIndex >= 0) {
                    _goToStep(_ClientStep.values[prevIndex]);
                  }
                },
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          Expanded(
            child: _currentStep == _ClientStep.call
                ? FilledButton.icon(
                    key: const Key('callButton'),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Call ${_methodController.text.trim()}'),
                    onPressed: _callMethod,
                  )
                : ElevatedButton(
                    key: const Key('nextButton'),
                    onPressed: _canProceed
                        ? () {
                            final nextIndex = _currentStep.index + 1;
                            if (nextIndex < _ClientStep.values.length) {
                              _goToStep(_ClientStep.values[nextIndex]);
                            }
                          }
                        : null,
                    child: const Text('Next'),
                  ),
          ),
        ],
      ),
    );
  }

  bool get _canProceed {
    switch (_currentStep) {
      case _ClientStep.canister:
        return _canProceedFromStep1;
      case _ClientStep.function:
        return _canProceedFromStep2;
      case _ClientStep.call:
        return true;
    }
  }
}

class _QuickCanisterChip extends StatelessWidget {
  const _QuickCanisterChip({
    required this.label,
    required this.canisterId,
    required this.onTap,
  });

  final String label;
  final String canisterId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(Icons.storage, size: 16, color: theme.colorScheme.primary),
      label: Text(label),
      onPressed: onTap,
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final model = CandidFormModel(widget.argTypes);

    if (!widget.useAuto ||
        widget.argTypes.isEmpty ||
        !model.isSupportedByForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!widget.useAuto && widget.argTypes.isNotEmpty)
            const SizedBox.shrink()
          else if (!model.isSupportedByForm)
            const Text(
                'Some argument types are not supported by auto form. Use raw JSON below.'),
          if (widget.argTypes.isEmpty)
            const Text('No input required for this method')
          else
            TextField(
              controller: widget.controller,
              decoration: const InputDecoration(
                labelText: 'Args JSON',
                hintText:
                    '[] for multiple args; object/array/scalar for single arg',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 8,
            ),
        ],
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.argTypes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final String t = widget.argTypes[index];
        final String label = 'Arg ${index + 1} ($t)';
        final String lower = t.toLowerCase();
        final TextInputType inputType = (lower.contains('int') ||
                lower.contains('float') ||
                lower.contains('nat'))
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
          },
        );
      },
    );
  }
}

class _HistoryListItem extends StatelessWidget {
  const _HistoryListItem({
    required this.record,
    required this.onTap,
  });

  final CanisterCallRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = record.resultSummary == 'success';
    final isUpdate = record.callType == CallType.update;
    final isComposite = record.callType == CallType.compositeQuery;

    final icon = isUpdate
        ? Icons.sync_alt
        : (isComposite ? Icons.merge_type : Icons.search);
    final iconColor = isUpdate
        ? Colors.orange
        : (isComposite ? Colors.purple : theme.colorScheme.primary);

    final timeAgo = _formatTimeAgo(record.timestamp);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        key: Key('historyItem_${record.canisterId}_${record.methodName}'),
        leading: Icon(icon, color: iconColor, size: 20),
        title: Text(
          record.methodName,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.canisterId.length > 16
                  ? '${record.canisterId.substring(0, 8)}...${record.canisterId.substring(record.canisterId.length - 4)}'
                  : record.canisterId,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  size: 12,
                  color: isSuccess ? Colors.green : theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  isSuccess ? 'Success' : record.resultSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSuccess ? Colors.green : theme.colorScheme.error,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.replay, size: 18),
        onTap: onTap,
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
