import 'package:flutter/material.dart';

import '../theme/app_design_system.dart';

typedef BookmarkSaveCallback = Future<void> Function({
  required String canisterId,
  required String method,
  String? label,
});

/// Single source of truth for the inline Add-Bookmark copy (UX-4).
const String _kAddBookmarkLabel = 'Add Bookmark';
const String _kAddBookmarkHint =
    'Save a canister + method for quick access';

/// Small inline form that lets users save bookmarks directly from the
/// Canisters tab.
///
/// UX-4: the form is **collapsed by default** behind a compact
/// [_kAddBookmarkLabel] button so the bookmarks list stays uncluttered. Tapping
/// the button expands the inline form (no sheet, no extra screen — the add
/// stays inline). The form is keyboard-first: type the canister id, Enter to
/// move to the method, Enter again to save. Escaping/Cancel collapses it back.
class BookmarkComposer extends StatefulWidget {
  const BookmarkComposer({
    super.key,
    required this.onSave,
    this.onSaved,
  });

  final BookmarkSaveCallback onSave;
  final void Function(String canisterId, String method, String? label)? onSaved;

  @override
  State<BookmarkComposer> createState() => _BookmarkComposerState();
}

class _BookmarkComposerState extends State<BookmarkComposer> {
  // UX-4: collapsed by default so the always-on form no longer clutters the
  // explore screen. Expanded on demand via the "+ Add Bookmark" button.
  bool _expanded = false;

  final TextEditingController _canisterController = TextEditingController();
  final TextEditingController _methodController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  final FocusNode _canisterFocusNode = FocusNode();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _canisterController.addListener(_onFieldChanged);
    _methodController.addListener(_onFieldChanged);
    _labelController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _canisterController.removeListener(_onFieldChanged);
    _methodController.removeListener(_onFieldChanged);
    _labelController.removeListener(_onFieldChanged);
    _canisterController.dispose();
    _methodController.dispose();
    _labelController.dispose();
    _canisterFocusNode.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
    });
  }

  bool get _isInputValid {
    final canisterId = _canisterController.text.trim().toLowerCase();
    final method = _methodController.text.trim();
    return _isValidCanisterId(canisterId) && method.isNotEmpty;
  }

  bool _isValidCanisterId(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    final regExp = RegExp(r'^[a-z0-9-]{5,64}$');
    return regExp.hasMatch(trimmed);
  }

  void _expand() {
    setState(() {
      _expanded = true;
      _errorMessage = null;
    });
    // Focus the first field once the form has mounted, so a keyboard user can
    // type immediately without an extra tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _canisterFocusNode.requestFocus();
    });
  }

  void _collapse() {
    setState(() {
      _expanded = false;
      _errorMessage = null;
    });
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    final canisterId = _canisterController.text.trim();
    final method = _methodController.text.trim();
    final label = _labelController.text.trim().isEmpty ? null : _labelController.text.trim();

    if (!_isValidCanisterId(canisterId)) {
      setState(() => _errorMessage = 'Enter a valid canister ID.');
      return;
    }

    if (method.isEmpty) {
      setState(() => _errorMessage = 'Method name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    try {
      await widget.onSave(canisterId: canisterId, method: method, label: label);
      if (!mounted) return;
      _canisterController.clear();
      _methodController.clear();
      _labelController.clear();
      widget.onSaved?.call(canisterId, method, label);
      // Collapse back to the compact button on success — the list refreshes
      // below and the parent's snackbar confirms the save, so the inline form
      // no longer needs to hold screen space (UX-4 de-clutter).
      _collapse();
    } catch (e) {
      if (!mounted) return;
      final message = 'Failed to save bookmark: $e';
      setState(() => _errorMessage = message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: colorScheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return _buildCollapsed(context);
    }
    return _buildExpanded(context);
  }

  Widget _buildCollapsed(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('bookmarkComposerToggleButton'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radius12),
          ),
        ),
        onPressed: _expand,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(_kAddBookmarkLabel),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final theme = Theme.of(context);
    final isValid = _isInputValid;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kAddBookmarkLabel,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _kAddBookmarkHint,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('bookmarkComposerCollapseButton'),
                  tooltip: 'Collapse',
                  icon: const Icon(Icons.expand_less_rounded),
                  onPressed: _isSaving ? null : _collapse,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('bookmarkComposerCanisterField'),
              controller: _canisterController,
              focusNode: _canisterFocusNode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Canister ID',
                hintText: 'aaaaa-aa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bookmarkComposerMethodField'),
              controller: _methodController,
              // Enter submits — the common path skips the optional label:
              // type canister → Enter → type method → Enter → saved.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSubmit(),
              decoration: const InputDecoration(
                labelText: 'Method name',
                hintText: 'icrc1_balance_of',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bookmarkComposerLabelField'),
              controller: _labelController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSubmit(),
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'ckBTC Ledger',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('bookmarkComposerError'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('bookmarkComposerSubmitButton'),
                onPressed: _isSaving || !isValid ? null : _handleSubmit,
                icon: _isSaving
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Add Bookmark'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
