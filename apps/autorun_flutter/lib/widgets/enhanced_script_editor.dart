import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/native_bridge.dart';
import '../widgets/integrations_help.dart';

/// Enhanced script editor with syntax highlighting, live linting, and improved UX
class EnhancedScriptEditor extends StatefulWidget {
  const EnhancedScriptEditor({
    super.key,
    required this.initialCode,
    required this.onCodeChanged,
    required this.language,
    this.showIntegrations = true,
    this.readOnly = false,
    this.minLines = 20,
    this.maxLines,
  });

  final String initialCode;
  final ValueChanged<String> onCodeChanged;
  final String language;
  final bool showIntegrations;
  final bool readOnly;
  final int minLines;
  final int? maxLines;

  @override
  State<EnhancedScriptEditor> createState() => _EnhancedScriptEditorState();
}

class _EnhancedScriptEditorState extends State<EnhancedScriptEditor> {
  late final TextEditingController _controller;
  String? _lintError;
  Timer? _lintDebouncer;
  int _currentLineCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode);
    _controller.addListener(_onTextChanged);
    _updateLineCount();
    _scheduleLint();
  }

  @override
  void dispose() {
    _lintDebouncer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final code = _controller.text;
    widget.onCodeChanged(code);
    _updateLineCount();
    _scheduleLint();
  }

  void _updateLineCount() {
    _currentLineCount = _controller.text.split('\n').length;
    if (mounted) setState(() {});
  }

  void _scheduleLint() {
    _lintDebouncer?.cancel();
    _lintDebouncer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _performLint();
    });
  }

  void _performLint() async {
    final code = _controller.text;

    // Fail-fast: empty script check
    if (code.trim().isEmpty) {
      if (mounted) setState(() => _lintError = 'Script is empty');
      return;
    }

    try {
      final String? out = (const RustBridgeLoader())
          .luaLint(script: code);

      if (out == null || out.trim().isEmpty) {
        if (mounted) setState(() => _lintError = 'Linter unavailable');
        return;
      }

      final Map<String, dynamic> obj = json.decode(out) as Map<String, dynamic>;
      final bool ok = (obj['ok'] as bool?) ?? false;

      if (mounted) {
        if (ok) {
          setState(() => _lintError = null);
        } else {
          final List<dynamic> errs = (obj['errors'] as List<dynamic>? ?? const <dynamic>[]);
          final String msg = errs.isNotEmpty
              ? ((errs.first as Map<String, dynamic>)['message'] as String? ?? 'Invalid script')
              : 'Invalid script';
          setState(() => _lintError = msg);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _lintError = 'Invalid linter output');
    }
  }

  void _showIntegrationsHelp() async {
    final String? snippet = await showDialog<String?>(
      context: context,
      builder: (_) => const IntegrationsHelpDialog(),
    );

    if (snippet == null || snippet.isEmpty) return;
    _insertSnippet(snippet);
  }

  void _insertSnippet(String snippet) {
    final text = _controller.text;
    final selection = _controller.selection;
    final baseOffset = selection.baseOffset;
    final extentOffset = selection.extentOffset;
    final hasSelection = baseOffset >= 0 && extentOffset >= 0 && baseOffset != extentOffset;

    final before = hasSelection
        ? text.replaceRange(baseOffset, extentOffset, '')
        : text;

    final insertPos = hasSelection
        ? baseOffset
        : (selection.baseOffset >= 0 ? selection.baseOffset : before.length);

    final updated = before.substring(0, insertPos) + snippet + before.substring(insertPos);
    _controller.text = updated;
    _controller.selection = TextSelection.collapsed(offset: insertPos + snippet.length);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        _buildToolbar(),

        // Editor
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TextField(
                controller: _controller,
                readOnly: widget.readOnly,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: '// Enter your Lua code here...',
                ),
                keyboardType: TextInputType.multiline,
              ),
            ),
          ),
        ),

        // Status bar with lint error
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Language indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.language.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Line count
          Text(
            'Lines: $_currentLineCount',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const Spacer(),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showIntegrations) ...[
                Tooltip(
                  message: 'Code snippets & integrations',
                  child: IconButton(
                    onPressed: _showIntegrationsHelp,
                    icon: const Icon(Icons.extension, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
              ],

              Tooltip(
                message: 'Format code',
                child: IconButton(
                  onPressed: _formatCode,
                  icon: const Icon(Icons.format_align_left, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ),

              Tooltip(
                message: 'Copy code',
                child: IconButton(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _lintError != null
            ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          top: BorderSide(
            color: _lintError != null
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Icon(
            _lintError != null ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: _lintError != null
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(width: 8),

          // Status text
          Expanded(
            child: Text(
              _lintError ?? 'Code is valid',
              style: TextStyle(
                fontSize: 12,
                color: _lintError != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                fontWeight: _lintError != null ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),

          // Word count
          Text(
            'Chars: ${_controller.text.length}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _formatCode() {
    // Basic formatting - could be enhanced with proper Lua formatter
    final code = _controller.text;
    // For now, just trigger a change
    _controller.text = code;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code formatting coming soon!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _copyCode() {
    // Copy to clipboard functionality
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard!'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}