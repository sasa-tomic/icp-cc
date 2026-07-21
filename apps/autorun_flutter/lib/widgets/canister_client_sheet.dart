import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/account_controller.dart';
import '../models/profile_keypair.dart';
import '../rust/native_bridge.dart';
import '../screens/unified_setup_wizard.dart';
import '../services/bookmarks_service.dart';
import '../services/canister_history_service.dart';
import '../services/canister_registry_service.dart';
import '../services/secure_storage_readiness.dart';
import '../utils/candid_json_example.dart';
import '../utils/candid_json_validate.dart';
import '../utils/candid_type_resolver.dart';
import '../utils/friendly_error.dart';
import '../utils/json_format.dart';
import '../utils/tech_terms.dart';
import 'bookmarks_list.dart';
import 'canister_args_editor.dart';
import 'profile_scope.dart';
import 'well_known_canisters.dart';

enum _ClientFlowState { disconnected, connecting, connected, ready }

/// A canister exposes a "large" method set when it has more than this many
/// functions. Above it, two things switch on (UX-3): the search field
/// auto-focuses (the chip wall is otherwise unscannable) and methods are
/// grouped under call-kind headers (Query / Update / Composite). At or below
/// it the layout stays flat — small canisters don't warrant a keyboard pop or
/// per-kind headers. Single source of truth for both thresholds.
const int _kLargeMethodSetThreshold = 8;

/// Candid call-kind categories used to group the method picker (UX-3).
/// Order matters: cheap reads first, then writes, then composite calls —
/// mirroring the per-chip icon/colour scheme already in [_buildMethodSelector].
enum _MethodKind { query, update, composite }

class CanisterClientSheet extends StatefulWidget {
  const CanisterClientSheet(
      {super.key,
      required this.bridge,
      this.initialCanisterId,
      this.initialMethodName});
  final RustBridgeLoader bridge;
  final String? initialCanisterId;
  final String? initialMethodName;

  @override
  State<CanisterClientSheet> createState() => _CanisterClientSheetState();
}

class _CanisterClientSheetState extends State<CanisterClientSheet> {
  _ClientFlowState _flowState = _ClientFlowState.disconnected;
  final TextEditingController _canisterController = TextEditingController();
  final FocusNode _canisterFocusNode = FocusNode();
  final TextEditingController _methodController = TextEditingController();
  int _selectedMode = 0;
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
  // UX-3: searchable method picker. [_methodQuery] is the live filter (kept in
  // sync with [_methodSearchController] via a listener); empty = show all.
  final TextEditingController _methodSearchController = TextEditingController();
  final FocusNode _methodSearchFocusNode = FocusNode();
  String _methodQuery = '';

  // UX-H12: when true, the next Call dispatches via `callAuthenticated` with
  // the active profile's keypair (instead of `callAnonymous`). The toggle is
  // only enabled when an active keypair exists; turning it on without one
  // surfaces a loud error instead of silently degrading to anonymous.
  bool _signAsActiveProfile = false;

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

  /// Live-filter the method list on every keystroke (UX-3). Guarded so a
  /// programmatic [TextEditingController.clear] (where we set [_methodQuery]
  /// first) does not recurse into a nested setState.
  void _onMethodSearchChanged() {
    final next = _methodSearchController.text;
    if (next == _methodQuery) return;
    if (mounted) setState(() => _methodQuery = next);
  }

  /// Escape clears the search query (only when there is one to clear).
  KeyEventResult _onMethodSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _methodQuery.isNotEmpty) {
      _methodQuery = '';
      _methodSearchController.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Methods matching the current [_methodQuery] (case-insensitive substring on
  /// the method name). Empty query → all methods.
  List<Map<String, dynamic>> _filteredMethods() {
    final q = _methodQuery.toLowerCase();
    if (q.isEmpty) return _methods;
    return _methods
        .where((m) => (m['name'] as String).toLowerCase().contains(q))
        .toList();
  }

  static _MethodKind _classifyKind(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('composite')) return _MethodKind.composite;
    if (k.contains('update')) return _MethodKind.update;
    return _MethodKind.query;
  }

  @override
  void dispose() {
    _canisterController.dispose();
    _canisterFocusNode.dispose();
    _methodController.dispose();
    _jsonArgsController.removeListener(_onArgsChanged);
    _jsonArgsController.dispose();
    _methodSearchController.removeListener(_onMethodSearchChanged);
    _methodSearchController.dispose();
    _methodSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _jsonArgsController.addListener(_onArgsChanged);
    _methodSearchController.addListener(_onMethodSearchChanged);
    // Escape clears the filter while the search field has focus (keyboard clear
    // affordance); all other keys pass through unchanged.
    _methodSearchFocusNode.onKeyEvent = _onMethodSearchKeyEvent;
    if ((widget.initialCanisterId ?? '').isNotEmpty) {
      _canisterController.text = widget.initialCanisterId!.trim();
    }
    if ((widget.initialMethodName ?? '').isNotEmpty) {
      _methodController.text = widget.initialMethodName!.trim();
    }
    if (_canisterController.text.trim().isNotEmpty &&
        _methodController.text.trim().isNotEmpty) {
      scheduleMicrotask(_fetchAndParse);
    } else if (_canisterController.text.trim().isNotEmpty) {
      _flowState = _ClientFlowState.disconnected;
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

  String _friendlyError(Object error) {
    // Classify by exception TYPE, not by grepping the message string (TD-9).
    // A canister-not-found surfaces upstream as a null/empty fetch → the
    // "Could not load canister interface" path; the throws that reach THIS
    // catch are interface-decode failures (FormatException) or async
    // timeouts (TimeoutException). Anything else is genuinely unknown, so we
    // show the honest generic message rather than risk mis-classifying an
    // unrelated error as "canister not found" just because its text happens
    // to contain "404" or "not found".
    if (error is FormatException) {
      return 'Could not read the canister interface.';
    }
    if (error is TimeoutException) {
      return 'Connection timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  /// UX-H12: read the active profile's keypair without throwing. Returns
  /// `null` when there is no [ProfileScope] ancestor (test harness /
  /// off-tree mount) OR when the active profile has no keypair.
  ///
  /// Uses [dependOnInheritedWidgetOfExactType] so the sheet rebuilds when the
  /// active profile changes (creation, switch, deletion) — the toggle's
  /// enabled/disabled + subtitle state stays in sync with the profile source
  /// of truth. The recheck inside [_callMethod] guards against mid-session
  /// profile removal (AGENTS.md: no silent fallback to anonymous).
  ProfileKeypair? _activeKeypairOrNull(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    return scope?.notifier?.activeKeypair;
  }

  /// UX-H12: deep-link the keyless user into [UnifiedSetupWizard] so they can
  /// create a profile in one tap and sign calls. Mirrors the re-open-wizard
  /// path in `dapp_runner_screen.dart` without introducing a circular import
  /// on the app entry point. Only invoked from a tree where [ProfileScope] is
  /// an ancestor (production mount inside `BookmarksScreen`).
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
          secureStorageReadiness: SecureStorageReadiness(),
        ),
      ),
    );
  }

  Future<void> _fetchAndParse() async {
    final String cid = _canisterController.text.trim();
    if (cid.isEmpty || _isFetching) return;
    _clearError();
    setState(() {
      _isFetching = true;
      _flowState = _ClientFlowState.connecting;
    });
    try {
      final String? did = await widget.bridge.fetchCandid(
        canisterId: cid,
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
        // Reset any stale filter so methods from the new canister aren't hidden.
        _methodQuery = '';
        _methodSearchController.clear();
        _flowState = _ClientFlowState.connected;
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
    final int modeIndex =
        kind.contains('update') ? 1 : (kind.contains('composite') ? 2 : 0);
    final resolver = CandidTypeResolver(_candidRaw ?? '');
    final args = (method['args'] as List<dynamic>).cast<String>();
    final resolvedArgs = resolver.resolveArgTypes(args);
    setState(() {
      _selectedMethod = method;
      _methodController.text = method['name'] as String;
      _selectedMode = modeIndex;
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
      _flowState = _ClientFlowState.ready;
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
    CallType callType = _selectedMode == 1
        ? CallType.update
        : (_selectedMode == 2 ? CallType.compositeQuery : CallType.query);

    // UX-H12: recheck the active keypair on call entry. The toggle may have
    // been enabled when the user opened the sheet, then the profile was
    // deleted mid-session — never silently degrade to anonymous.
    final bool signAsProfile = _signAsActiveProfile;
    final ProfileKeypair? activeKeypair = _activeKeypairOrNull(context);
    if (signAsProfile && activeKeypair == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(
            StateError('No active profile keypair'),
            context: 'Cannot sign call',
          )),
        ),
      );
      return;
    }

    try {
      final String? out;
      if (signAsProfile) {
        out = await widget.bridge.callAuthenticated(
          canisterId: cid,
          method: method,
          mode: _selectedMode,
          privateKeyB64: activeKeypair!.privateKey,
          args: args,
        );
      } else {
        out = await widget.bridge.callAnonymous(
          canisterId: cid,
          method: method,
          mode: _selectedMode,
          args: args,
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
        resultSummary: signAsProfile ? 'success (signed)' : 'success',
      );
    } catch (e) {
      await CanisterHistoryService().addCall(
        canisterId: cid,
        methodName: method,
        arguments: args,
        callType: callType,
        resultSummary: signAsProfile
            ? 'error (signed): ${e.toString()}'
            : 'error: ${e.toString()}',
      );
      rethrow;
    }
  }

  void _resetToDisconnected() {
    setState(() {
      _flowState = _ClientFlowState.disconnected;
      _methods = const <Map<String, dynamic>>[];
      _selectedMethod = null;
      _candidRaw = null;
      _resultJson = null;
      _validationErrors = const <String>[];
      _resolvedArgs = const <String>[];
      _currentMethodSig = const <Map<String, dynamic>>[];
      _methodController.clear();
      _jsonArgsController.clear();
      _methodQuery = '';
      _methodSearchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final safeAreaPadding = MediaQuery.of(context).padding;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: viewInsets.bottom + safeAreaPadding.bottom,
        left: isCompactScreen ? 8 : 16,
        right: isCompactScreen ? 8 : 16,
        top: isCompactScreen ? 8 : 16,
      ),
      child: ListView(
        padding: EdgeInsets.all(isCompactScreen ? 12 : 16),
        shrinkWrap: true,
        children: <Widget>[
          Row(
            children: [
              Expanded(
                child: Text('Canister Client',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: isCompactScreen ? 20 : 24,
                    )),
              ),
              if (_flowState != _ClientFlowState.disconnected)
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                  onPressed: _resetToDisconnected,
                ),
            ],
          ),
          SizedBox(height: isCompactScreen ? 8 : 12),
          _buildCanisterInput(theme, isCompactScreen),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
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
                      style:
                          TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_flowState == _ClientFlowState.connected ||
              _flowState == _ClientFlowState.ready) ...[
            const SizedBox(height: 16),
            _buildMethodSelector(theme, isCompactScreen),
          ],
          if (_flowState == _ClientFlowState.ready) ...[
            const SizedBox(height: 16),
            _buildInputSection(theme, isCompactScreen),
            const SizedBox(height: 16),
            _buildCallButton(theme, isCompactScreen),
          ],
          if ((_resultJson ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildResultSection(theme, isCompactScreen),
          ],
          if (_flowState == _ClientFlowState.disconnected) ...[
            const SizedBox(height: 16),
            _buildQuickStartSection(theme, isCompactScreen),
          ],
        ],
      ),
    );
  }

  Widget _buildCanisterInput(ThemeData theme, bool isCompact) {
    return Tooltip(
      message:
          'A canister is a smart contract running on the Internet Computer.\n'
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
                  labelText: 'Canister',
                  hintText: 'Enter canister ID or name',
                  border: const OutlineInputBorder(),
                  suffixIcon: _isFetching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_flowState == _ClientFlowState.connected ||
                              _flowState == _ClientFlowState.ready)
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary)
                          : null,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 12 : 16,
                    vertical: isCompact ? 12 : 16,
                  ),
                ),
                style: TextStyle(fontSize: isCompact ? 14 : 16),
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
                      maxHeight: 200,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return InkWell(
                          key: Key('autocompleteOption_${option.canisterId}'),
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
                                        borderRadius: BorderRadius.circular(4),
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
    );
  }

  Widget _buildMethodSelector(ThemeData theme, bool isCompact) {
    final filtered = _filteredMethods();
    final total = _methods.length;
    final isFiltering = _methodQuery.isNotEmpty;
    // Group by call-kind only for genuinely large sets — below the threshold a
    // flat wrap reads better and stays compact (YAGNI).
    final useGrouping = total > _kLargeMethodSetThreshold;

    final List<Widget> methodWidgets;
    if (filtered.isEmpty) {
      methodWidgets = <Widget>[_buildNoMethodMatches(theme)];
    } else if (useGrouping) {
      final byKind = <_MethodKind, List<Map<String, dynamic>>>{
        for (final k in _MethodKind.values) k: <Map<String, dynamic>>[],
      };
      for (final m in filtered) {
        byKind[_classifyKind(m['kind'] as String)]!.add(m);
      }
      methodWidgets = <Widget>[];
      for (final kind in _MethodKind.values) {
        final methods = byKind[kind]!;
        if (methods.isEmpty) continue;
        if (methodWidgets.isNotEmpty) {
          methodWidgets.add(const SizedBox(height: 12));
        }
        methodWidgets.add(_buildMethodKindGroup(theme, kind, methods));
      }
    } else {
      methodWidgets = <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filtered.map((m) => _buildMethodChip(theme, m)).toList(),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message:
              'Choose a function to call.\n${TechTerm.query.plainLabel} = read data (fast), ${TechTerm.update.plainLabel} = change data (slower).',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Function', style: theme.textTheme.titleMedium),
              Text(
                isFiltering ? '${filtered.length} of $total' : '$total functions',
                key: const Key('methodCount'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildMethodSearchField(theme, isCompact, total),
        const SizedBox(height: 12),
        ...methodWidgets,
      ],
    );
  }

  Widget _buildMethodSearchField(
      ThemeData theme, bool isCompact, int total) {
    return TextField(
      key: const Key('methodSearchField'),
      controller: _methodSearchController,
      focusNode: _methodSearchFocusNode,
      // Only auto-grab focus when the chip wall is genuinely large; small
      // canisters don't warrant popping the keyboard on entry.
      autofocus: total > _kLargeMethodSetThreshold,
      decoration: InputDecoration(
        hintText: 'Search $total functions…',
        isDense: true,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _methodQuery.isNotEmpty
            ? IconButton(
                key: const Key('methodSearchClear'),
                icon: const Icon(Icons.clear, size: 20),
                tooltip: 'Clear search',
                onPressed: () {
                  _methodSearchController.clear();
                  _methodSearchFocusNode.requestFocus();
                },
              )
            : null,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 10 : 12,
        ),
      ),
      style: TextStyle(fontSize: isCompact ? 14 : 16),
      textInputAction: TextInputAction.search,
      // Enter selects the first match — keyboard-only path to a Call.
      onSubmitted: (_) {
        final matches = _filteredMethods();
        if (matches.isNotEmpty) _selectMethod(matches.first);
      },
    );
  }

  Widget _buildMethodKindGroup(
      ThemeData theme, _MethodKind kind, List<Map<String, dynamic>> methods) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(_kindIcon(kind), size: 14, color: _kindColor(theme, kind)),
              const SizedBox(width: 6),
              Text(
                '${_kindLabel(kind)} · ${methods.length}',
                key: Key('methodGroup_${kind.name}'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.map((m) => _buildMethodChip(theme, m)).toList(),
        ),
      ],
    );
  }

  Widget _buildMethodChip(ThemeData theme, Map<String, dynamic> m) {
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
        // call-type category colour (query/update/composite), not a
        // status semantic — intentionally off-token (composite has no
        // status token either, so the 3-way scheme stays coherent).
        color: isSelected
            ? theme.colorScheme.onSecondaryContainer
            : (isUpdate
                ? Colors.orange
                : (isComposite ? Colors.purple : theme.colorScheme.primary)),
      ),
      onSelected: (_) => _selectMethod(m),
      selectedColor: theme.colorScheme.secondaryContainer,
    );
  }

  /// Inline empty-state shown when the search filter matches nothing.
  /// (ModernEmptyState is a full-screen animated widget — wrong for a sheet row.)
  Widget _buildNoMethodMatches(ThemeData theme) {
    return Padding(
      key: const Key('methodSearchEmpty'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.search_off,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "No methods match '$_methodQuery'.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(_MethodKind kind) {
    switch (kind) {
      case _MethodKind.query:
        return '${TechTerm.query.plainLabel} (fast)';
      case _MethodKind.update:
        return '${TechTerm.update.plainLabel} (slower)';
      case _MethodKind.composite:
        return 'Composite';
    }
  }

  static IconData _kindIcon(_MethodKind kind) {
    switch (kind) {
      case _MethodKind.query:
        return Icons.search;
      case _MethodKind.update:
        return Icons.sync_alt;
      case _MethodKind.composite:
        return Icons.merge_type;
    }
  }

  static Color _kindColor(ThemeData theme, _MethodKind kind) {
    switch (kind) {
      case _MethodKind.query:
        return theme.colorScheme.primary;
      case _MethodKind.update:
        return Colors.orange;
      case _MethodKind.composite:
        return Colors.purple;
    }
  }

  Widget _buildInputSection(ThemeData theme, bool isCompact) {
    if (_resolvedArgs.isEmpty) {
      return Tooltip(
        message: 'This function does not require any input.',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
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
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Provide the input data for this function.\n'
              'The format is automatically generated based on the function signature.',
          child: Row(
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
        ),
        const SizedBox(height: 8),
        ArgsEditor(
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

  Widget _buildCallButton(ThemeData theme, bool isCompact) {
    final modeLabel = _selectedMode == 1
        ? TechTerm.update.plainLabel
        : (_selectedMode == 2 ? 'Complex Read' : TechTerm.query.plainLabel);
    // call-type category colour (query/update/composite), not a status — see above.
    final modeColor = _selectedMode == 1
        ? Colors.orange
        : (_selectedMode == 2 ? Colors.purple : theme.colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedMode == 1
                        ? Icons.sync_alt
                        : (_selectedMode == 2
                            ? Icons.merge_type
                            : Icons.search),
                    size: 14,
                    color: modeColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    modeLabel,
                    style: TextStyle(
                      color: modeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _selectedMode == 1
                        ? TechTerm.update.plainExplanation
                        : TechTerm.query.plainExplanation,
                    preferBelow: true,
                    showDuration: const Duration(seconds: 4),
                    child: Icon(
                      Icons.info_outline,
                      size: 12,
                      color: modeColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_selectedMethod != null)
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
                      messenger.showSnackBar(SnackBar(
                          content: Text(friendlyErrorMessage(e,
                              context: 'Failed to save'))));
                    }
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSignAsProfileToggle(theme),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('callButton'),
          icon: const Icon(Icons.play_arrow),
          label: Text('Call ${_methodController.text.trim()}'),
          onPressed: _callMethod,
        ),
      ],
    );
  }

  /// UX-H12: the "Sign as active profile" toggle. When an active keypair
  /// exists the user can opt in to authenticated calls (the bridge dispatches
  /// `callAuthenticated` with that keypair's private key). When no keypair is
  /// available the toggle is disabled and the subtitle becomes a tappable
  /// CTA that opens [UnifiedSetupWizard] — never a silent fallback to
  /// anonymous on a signed intent.
  ///
  /// NEVER renders the private key. The subtitle shows the public principal
  /// (or a placeholder when the keypair has no principal yet).
  Widget _buildSignAsProfileToggle(ThemeData theme) {
    final ProfileKeypair? keypair = _activeKeypairOrNull(context);
    final bool canSign = keypair != null;
    final String principal = keypair?.principal ?? '';
    return SwitchListTile.adaptive(
      key: const Key('signAsActiveProfileSwitch'),
      value: canSign ? _signAsActiveProfile : false,
      onChanged: canSign
          ? (v) => setState(() => _signAsActiveProfile = v)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      dense: true,
      secondary: Icon(
        canSign ? Icons.verified_user_outlined : Icons.shield_outlined,
        color: canSign ? theme.colorScheme.primary : theme.disabledColor,
      ),
      title: const Text('Sign as active profile'),
      subtitle: canSign
          ? Text(
              principal.isEmpty
                  ? 'Active keypair will sign this call'
                  : 'Principal: $principal',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : GestureDetector(
              key: const Key('signAsActiveProfileCreateCta'),
              onTap: _openCreateProfileWizard,
              child: Text(
                'Create a profile to sign calls as your identity.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
    );
  }

  Widget _buildResultSection(ThemeData theme, bool isCompact) {
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

  Widget _buildQuickStartSection(ThemeData theme, bool isCompact) {
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
        WellKnownList(
          onSelect: (cid, method) {
            _canisterController.text = cid;
            if ((method ?? '').isNotEmpty) {
              _methodController.text = method!;
            }
            _fetchAndParse();
          },
        ),
        const SizedBox(height: 16),
        Text('Your Bookmarks', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        BookmarksList(
          bridge: widget.bridge,
          onTapEntry: (cid, method) {
            _canisterController.text = cid;
            _methodController.text = method;
            _fetchAndParse();
          },
        ),
      ],
    );
  }
}
