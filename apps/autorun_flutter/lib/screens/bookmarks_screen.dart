import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rust/native_bridge.dart';
import '../services/bookmarks_service.dart';
import '../utils/json_format.dart';
import '../utils/candid_form_model.dart';
import '../utils/candid_type_resolver.dart';
import '../utils/candid_json_example.dart';
import '../utils/candid_json_validate.dart';
import '../widgets/modern_empty_state.dart';
import '../widgets/bookmark_composer.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen(
      {super.key, required this.bridge, required this.onOpenClient});

  final RustBridgeLoader bridge;
  final Future<void> Function(
      {String? initialCanisterId, String? initialMethodName}) onOpenClient;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _popularCanistersKey = GlobalKey();

  void _scrollToPopularCanisters() {
    final context = _popularCanistersKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _refreshContent() async {
    BookmarksService.invalidateCache();
    await BookmarksService.list();
    BookmarksEvents.notifyChanged();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Explore'),
            SizedBox(height: 2),
            Text(
              'Interact with Internet Computer canisters',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.05),
              ],
            ),
          ),
          child: RefreshIndicator(
            onRefresh: _refreshContent,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _QuickActionsList(
                    onOpenClient: widget.onOpenClient,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    key: _popularCanistersKey,
                    child: _buildSectionHeader(
                      context,
                      title: 'Popular Canisters',
                      subtitle: 'Quick access to essential ICP services',
                      icon: Icons.star_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _WellKnownList(
                      onSelect: (cid, method) {
                        HapticFeedback.lightImpact();
                        widget.onOpenClient(
                          initialCanisterId: cid,
                          initialMethodName:
                              method?.isNotEmpty == true ? method : null,
                        );
                      },
                      onBookmark: (entry) =>
                          _bookmarkWellKnown(context, entry)),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    context,
                    title: 'Your Bookmarks',
                    subtitle: 'Your saved canister methods for quick access',
                    icon: Icons.bookmark_rounded,
                  ),
                  const SizedBox(height: 16),
                  BookmarkComposer(
                    onSave: BookmarksService.add,
                    onSaved: (cid, method, label) {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(
                        SnackBar(
                          content:
                              Text('Saved ${label ?? method} to bookmarks'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _BookmarksList(
                    bridge: widget.bridge,
                    onTapEntry: (cid, method) {
                      HapticFeedback.lightImpact();
                      widget.onOpenClient(
                          initialCanisterId: cid, initialMethodName: method);
                    },
                    onExplorePopular: _scrollToPopularCanisters,
                  ),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    context,
                    title: 'Advanced',
                    subtitle: 'Direct canister access and raw queries',
                    icon: Icons.build_rounded,
                  ),
                  const SizedBox(height: 16),
                  _AdvancedSection(onOpenClient: widget.onOpenClient),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactScreen = screenWidth < 380;

    return Container(
      padding: EdgeInsets.all(isCompactScreen ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isCompactScreen ? 12 : 16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isCompactScreen ? 10 : 12),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: isCompactScreen ? 20 : 24,
            ),
          ),
          SizedBox(width: isCompactScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: isCompactScreen ? 18 : 20,
                        letterSpacing: -0.5,
                      ),
                ),
                SizedBox(height: isCompactScreen ? 2 : 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: isCompactScreen ? 12 : 14,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bookmarkWellKnown(
      BuildContext context, WellKnownCanister entry) {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return BookmarksService.add(
      canisterId: entry.canisterId,
      method: entry.method ?? 'http_request',
      label: entry.label,
    ).then((_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Bookmarked ${entry.label}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }).catchError((Object e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to bookmark ${entry.label}: $e'),
          backgroundColor: colorScheme.error,
        ),
      );
    });
  }
}

enum _ClientFlowState { disconnected, connecting, connected, ready }

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
      _flowState = _ClientFlowState.connecting;
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

  void _callMethod() {
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
            _buildAdvancedOptions(theme, isCompactScreen),
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
      child: TextField(
        key: const Key('canisterField'),
        controller: _canisterController,
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
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : null,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 16,
            vertical: isCompact ? 12 : 16,
          ),
        ),
        style: TextStyle(fontSize: isCompact ? 14 : 16),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _fetchAndParse(),
      ),
    );
  }

  Widget _buildMethodSelector(ThemeData theme, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Choose a function to call on this canister.\n'
              'Query = fast read, Update = state change.',
          child: Text('Select Function', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
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

  Widget _buildAdvancedOptions(ThemeData theme, bool isCompact) {
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

  Widget _buildCallButton(ThemeData theme, bool isCompact) {
    final kindLabel = _selectedKind == 1
        ? 'Update'
        : (_selectedKind == 2 ? 'Composite Query' : 'Query');
    final kindColor = _selectedKind == 1
        ? Colors.orange
        : (_selectedKind == 2 ? Colors.purple : theme.colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kindColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedKind == 1
                        ? Icons.sync_alt
                        : (_selectedKind == 2
                            ? Icons.merge_type
                            : Icons.search),
                    size: 14,
                    color: kindColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    kindLabel,
                    style: TextStyle(
                      color: kindColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
                      messenger.showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')));
                    }
                  }
                },
              ),
          ],
        ),
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
        _WellKnownList(
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
        _BookmarksList(
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

    if (!widget.useAuto ||
        widget.argTypes.isEmpty ||
        !model.isSupportedByForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          const SizedBox(height: 8),
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
                // Best-effort live validation comparing built JSON vs expected types
                try {
                  final model = CandidFormModel(widget.argTypes);
                  final List<dynamic> values =
                      _controllers.map((c) => c.text.trim()).toList();
                  final jsonStr = model.buildJson(values);
                  validateJsonArgs(
                      resolvedArgTypes: widget.argTypes, jsonText: jsonStr);
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

/// Quick Action types for one-tap operations
enum QuickActionType { openCanister, externalLink }

/// Represents a quick action card that can perform common tasks
class QuickAction {
  const QuickAction({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.type,
    this.canisterId,
    this.method,
    this.url,
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;
  final QuickActionType type;
  final String? canisterId;
  final String? method;
  final String? url;
}

/// Quick Actions list at the top of Services screen
class _QuickActionsList extends StatelessWidget {
  const _QuickActionsList({required this.onOpenClient});

  final Future<void> Function(
      {String? initialCanisterId, String? initialMethodName}) onOpenClient;

  static const List<QuickAction> _actions = <QuickAction>[
    QuickAction(
      key: 'checkBalance',
      label: 'Check ICP Balance',
      description: 'Query your ICP balance on the ledger',
      icon: Icons.account_balance_wallet_rounded,
      type: QuickActionType.openCanister,
      canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
      method: 'account_balance_dfx',
    ),
    QuickAction(
      key: 'viewNeurons',
      label: 'View Neurons',
      description: 'See your neurons in NNS Governance',
      icon: Icons.how_to_vote_rounded,
      type: QuickActionType.openCanister,
      canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
      method: 'list_neurons',
    ),
    QuickAction(
      key: 'searchDapps',
      label: 'Search Dapps',
      description: 'Find IC dapps on Kinic search engine',
      icon: Icons.search_rounded,
      type: QuickActionType.externalLink,
      url: 'https://kinic.io',
    ),
  ];

  Future<void> _handleAction(BuildContext context, QuickAction action) async {
    HapticFeedback.lightImpact();

    switch (action.type) {
      case QuickActionType.openCanister:
        await onOpenClient(
          initialCanisterId: action.canisterId,
          initialMethodName: action.method,
        );
      case QuickActionType.externalLink:
        if (action.url != null) {
          final uri = Uri.parse(action.url!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, webOnlyWindowName: '_blank');
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.secondary.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.flash_on_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'One-tap access to common tasks',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('quickActions_seeAll'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('More actions coming soon'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                'See All',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: _actions.map((action) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: action == _actions.last ? 0 : 12,
                ),
                child: _QuickActionCard(
                  action: action,
                  onTap: () => _handleAction(context, action),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Quick action card widget
class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({
    required this.action,
    required this.onTap,
  });

  final QuickAction action;
  final VoidCallback onTap;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExternal = widget.action.type == QuickActionType.externalLink;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedOpacity(
          opacity: _isHovered ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            key: Key('quickAction_${widget.action.key}'),
            elevation: _isHovered ? 4 : 2,
            borderRadius: BorderRadius.circular(16),
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.05),
                      theme.colorScheme.primary.withValues(alpha: 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.action.icon,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const Spacer(),
                        if (isExternal)
                          Icon(
                            Icons.open_in_new,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 16,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.action.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.action.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Advanced section for direct canister access
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.onOpenClient});

  final Future<void> Function(
      {String? initialCanisterId, String? initialMethodName}) onOpenClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onOpenClient();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Canister Client',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Query any canister with custom methods',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WellKnownCanister {
  const WellKnownCanister({
    required this.label,
    required this.canisterId,
    required this.description,
    required this.icon,
    this.method,
  });

  final String label;
  final String canisterId;
  final String description;
  final IconData icon;
  final String? method;
}

class _WellKnownList extends StatelessWidget {
  const _WellKnownList({required this.onSelect, this.onBookmark});
  final void Function(String canisterId, String? method) onSelect;
  final Future<void> Function(WellKnownCanister entry)? onBookmark;

  static const List<WellKnownCanister> _items = <WellKnownCanister>[
    WellKnownCanister(
      label: 'NNS Registry',
      canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
      method: 'get_value',
      description: 'Authoritative lookup for subnet + node records',
      icon: Icons.dns_rounded,
    ),
    WellKnownCanister(
      label: 'NNS Governance',
      canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
      method: 'get_neuron_ids',
      description: 'Manage neurons and follow governance proposals',
      icon: Icons.how_to_vote_rounded,
    ),
    WellKnownCanister(
      label: 'NNS Ledger',
      canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
      method: 'account_balance_dfx',
      description: 'Check ICP balances directly on the ledger',
      icon: Icons.account_balance_wallet_rounded,
    ),
    WellKnownCanister(
      label: 'Canlista Registry',
      canisterId: 'k7gat-daaaa-aaaae-qaahq-cai',
      method: 'http_request',
      description: 'Community-maintained catalog of IC canisters',
      icon: Icons.list_alt_rounded,
    ),
    WellKnownCanister(
      label: 'Cyql Projects',
      canisterId: 'n7ib3-4qaaa-aaaai-qagnq-cai',
      method: 'http_request',
      description: 'Curated feed of active Internet Computer dapps',
      icon: Icons.explore_rounded,
    ),
    WellKnownCanister(
      label: 'ICLighthouse',
      canisterId: '637g5-siaaa-aaaaj-aasja-cai',
      method: 'http_request',
      description: 'Realtime explorer with subnet level insights',
      icon: Icons.lightbulb_rounded,
    ),
    WellKnownCanister(
      label: 'Kinic Search',
      canisterId: '74iy7-xqaaa-aaaaf-qagra-cai',
      method: 'http_request',
      description: 'Native IC search engine for dapps and content',
      icon: Icons.search_rounded,
    ),
    WellKnownCanister(
      label: 'Canistergeek',
      canisterId: 'cusyh-iyaaa-aaaah-qcpba-cai',
      method: 'http_request',
      description: 'Monitor cycles, memory and performance at a glance',
      icon: Icons.analytics_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width > 880 ? 3 : 2);
    final childAspectRatio = width > 880 ? 3.5 : (width < 420 ? 3.0 : 2.6);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (BuildContext context, int index) {
        final entry = _items[index];
        return _WellKnownCard(
          entry: entry,
          onTap: () => onSelect(entry.canisterId, entry.method),
          onBookmark:
              onBookmark == null ? null : () => unawaited(onBookmark!(entry)),
        );
      },
    );
  }
}

class _WellKnownCard extends StatelessWidget {
  const _WellKnownCard(
      {required this.entry, required this.onTap, this.onBookmark});

  final WellKnownCanister entry;
  final VoidCallback onTap;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.icon,
                        color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onBookmark != null)
                    IconButton(
                      tooltip: 'Bookmark',
                      icon: Icon(Icons.bookmark_add_outlined,
                          color: theme.colorScheme.primary),
                      onPressed: onBookmark,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if ((entry.method ?? '').isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.method!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarksList extends StatefulWidget {
  const _BookmarksList({
    required this.bridge,
    required this.onTapEntry,
    this.onExplorePopular,
  });
  final RustBridgeLoader bridge;
  final void Function(String canisterId, String method) onTapEntry;
  final VoidCallback? onExplorePopular;

  @override
  State<_BookmarksList> createState() => _BookmarksListState();
}

class _BookmarksListState extends State<_BookmarksList> {
  List<BookmarkEntry> _entries = const <BookmarkEntry>[];
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _reload();
    _listener = _reload;
    BookmarksEvents.listenable.addListener(_listener);
  }

  @override
  void dispose() {
    BookmarksEvents.listenable.removeListener(_listener);
    super.dispose();
  }

  void _reload() async {
    try {
      final entries = await BookmarksService.list();
      if (mounted) {
        setState(() {
          _entries = entries;
        });
      }
    } catch (e) {
      // If loading fails, show empty list
      if (mounted) {
        setState(() {
          _entries = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return ModernEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'No Bookmarks Yet',
        subtitle: 'Save your favorite canister methods for quick access',
        action: widget.onExplorePopular,
        actionLabel: 'Explore Popular Canisters',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final entry = _entries[index];
        final cid = entry.canisterId;
        final method = entry.method;
        final label = entry.label ?? '';

        return Card(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () => widget.onTapEntry(cid, method),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withValues(alpha: 0.2),
                          Colors.indigo.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.isNotEmpty ? label : method,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cid,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            method,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red.shade400,
                          size: 20,
                        ),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await BookmarksService.remove(
                                canisterId: cid, method: method);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: const Text('Bookmark removed'),
                                  backgroundColor: Colors.blue.shade500,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Failed to remove bookmark: $e')),
                              );
                            }
                          }
                        },
                        tooltip: 'Remove bookmark',
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
