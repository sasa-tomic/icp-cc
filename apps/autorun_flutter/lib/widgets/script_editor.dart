import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/lua.dart';
import '../rust/native_bridge.dart';
import '../widgets/integrations_help.dart';

/// Script editor with syntax highlighting, live linting, and improved UX
class ScriptEditor extends StatefulWidget {
  const ScriptEditor({
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
  State<ScriptEditor> createState() => _ScriptEditorState();
}

class _ScriptEditorState extends State<ScriptEditor> {
  late final CodeController _controller;
  String? _lintError;
  Timer? _lintDebouncer;
  int _currentLineCount = 1;
  String _selectedTheme = 'vs2015';

  // Available themes
  static const Map<String, Map<String, TextStyle>> _themes = {
    'vs2015': vs2015Theme,
    'atom-one-dark': atomOneDarkTheme,
    'monokai-sublime': monokaiSublimeTheme,
  };

  @override
  void didUpdateWidget(ScriptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller text when initialCode changes
    if (oldWidget.initialCode != widget.initialCode && 
        _controller.text != widget.initialCode) {
      _controller.text = widget.initialCode;
      _scheduleLint();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.initialCode,
      language: lua,
    );
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
              color: _getBackgroundColorForTheme(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildHighlightedEditor(),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Compact language indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.language.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Compact theme selector
          DropdownButton<String>(
            value: _selectedTheme,
            underline: const SizedBox(),
            isDense: true,
            iconSize: 14,
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: _themes.keys.map((theme) {
              return DropdownMenuItem<String>(
                value: theme,
                child: Text(
                  theme.split('-').map((word) => word[0].toUpperCase()).join(''),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? theme) {
              if (theme != null) {
                setState(() => _selectedTheme = theme);
              }
            },
          ),

          const Spacer(),

          // Compact stats and actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compact stats
              Text(
                'L:$_currentLineCount C:${_controller.text.length}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),

              // Compact action buttons
              if (widget.showIntegrations) ...[
                Tooltip(
                  message: 'Code snippets',
                  child: IconButton(
                    onPressed: _showIntegrationsHelp,
                    icon: Icon(Icons.extension, size: 16),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                  ),
                ),
              ],
              Tooltip(
                message: 'Format code',
                child: IconButton(
                  onPressed: _formatCode,
                  icon: Icon(Icons.format_align_left, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                ),
              ),
              Tooltip(
                message: 'Copy code',
                child: IconButton(
                  onPressed: _copyCode,
                  icon: Icon(Icons.copy, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final hasError = _lintError != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: hasError
            ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          top: BorderSide(
            color: hasError
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Compact status indicator
          Icon(
            hasError ? Icons.error : Icons.check_circle,
            size: 12,
            color: hasError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(width: 8),

          // Status text
          Expanded(
            child: Text(
              hasError ? (_lintError ?? 'Syntax Error') : 'Valid',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: hasError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  void _formatCode() {
    // Basic formatting - could be improved with proper Lua formatter
    final code = _controller.text;
    // For now, just trigger a change
    _controller.text = code;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code formatting coming soon!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _copyCode() {
    // Copy to clipboard functionality
    Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code copied to clipboard!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildHighlightedEditor() {
    return CodeTheme(
      data: CodeThemeData(styles: _themes[_selectedTheme] ?? vs2015Theme),
      child: SingleChildScrollView(
        child: CodeField(
          controller: _controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          readOnly: widget.readOnly,
          gutterStyle: GutterStyle(
            showErrors: true,
            showFoldingHandles: true,
            showLineNumbers: true,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            height: 1.6,
          ),
          padding: const EdgeInsets.all(16),
          expands: false, // Allow scrolling
        ),
      ),
    );
  }

  Color _getBackgroundColorForTheme() {
    // Return appropriate background color based on selected theme
    switch (_selectedTheme) {
      case 'vs2015':
        return const Color(0xFF1E1E1E);
      case 'atom-one-dark':
        return const Color(0xFF282C34);
      case 'monokai-sublime':
        return const Color(0xFF2D2D2D);
      default:
        return Theme.of(context).colorScheme.surface;
    }
  }
}