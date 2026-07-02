import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/javascript.dart';
import '../rust/native_bridge.dart';
import '../widgets/integrations_help.dart';
import '../widgets/ui_component_palette.dart';

/// Normalizes [input] to well-formed UTF-16 by replacing any lone (unpaired)
/// surrogate code unit with U+FFFD (REPLACEMENT CHARACTER).
///
/// `flutter_code_editor`'s highlighter builds a `TextSpan` from the source and
/// hands it to the engine's `ParagraphBuilder.addText`, which throws
/// `ArgumentError: string is not well-formed UTF-16` if the string contains a
/// lone surrogate (NEW-3 in `docs/specs/UX_REVIEW_ROUND2.md`). Script and
/// marketplace content loaded over the network can carry such sequences, so
/// sanitize before feeding the `CodeController`. Well-formed input is returned
/// untouched; the highlighter and lint pipeline are unaffected.
String _sanitizeToWellFormedUtf16(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  final len = input.length;
  for (var i = 0; i < len; i++) {
    final unit = input.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // High surrogate — valid only when paired with a following low one.
      final next = i + 1 < len ? input.codeUnitAt(i + 1) : -1;
      if (next >= 0xDC00 && next <= 0xDFFF) {
        out
          ..writeCharCode(unit)
          ..writeCharCode(next);
        i++;
      } else {
        out.writeCharCode(0xFFFD);
      }
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // Lone low surrogate.
      out.writeCharCode(0xFFFD);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Script editor with syntax highlighting, live linting, and improved UX
class ScriptEditor extends StatefulWidget {
  const ScriptEditor({
    super.key,
    required this.initialCode,
    required this.onCodeChanged,
    this.showIntegrations = true,
    this.readOnly = false,
    this.minLines = 20,
    this.maxLines,
  });

  final String initialCode;
  final ValueChanged<String> onCodeChanged;
  final bool showIntegrations;
  final bool readOnly;
  final int minLines;
  final int? maxLines;

  @override
  State<ScriptEditor> createState() => ScriptEditorState();
}

/// Public state class for ScriptEditor to enable external access to dirty state
class ScriptEditorState extends State<ScriptEditor> {
  late final CodeController _controller;
  String? _lintError;
  Timer? _lintDebouncer;
  int _currentLineCount = 1;
  String _selectedTheme = 'vs2015';
  bool _showLineNumbers = false;

  /// The initial code that was passed to the widget
  late String _initialCode;

  /// Returns true if the current code differs from the initial code
  bool get isDirty => _controller.text != _initialCode;

  /// Updates the code programmatically (used for testing and external control)
  void updateCode(String code) {
    _controller.text = code;
  }

  // Available themes
  static const Map<String, Map<String, TextStyle>> _themes = {
    'vs2015': vs2015Theme,
    'atom-one-dark': atomOneDarkTheme,
    'monokai-sublime': monokaiSublimeTheme,
  };

  String _getDisplayName(String themeKey) {
    switch (themeKey) {
      case 'vs2015':
        return 'Vs2015';
      case 'atom-one-dark':
        return 'Atom One Dark';
      case 'monokai-sublime':
        return 'Monokai Sublime';
      default:
        return themeKey;
    }
  }

  @override
  void didUpdateWidget(ScriptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller text when initialCode changes. Sanitize to well-formed
    // UTF-16 first — see `_sanitizeToWellFormedUtf16`.
    if (oldWidget.initialCode != widget.initialCode) {
      final sanitized = _sanitizeToWellFormedUtf16(widget.initialCode);
      if (_controller.text != sanitized) {
        _controller.text = sanitized;
        _scheduleLint();
      }
      _initialCode = sanitized;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialCode = _sanitizeToWellFormedUtf16(widget.initialCode);
    _controller = CodeController(
      text: _initialCode,
      language: javascript,
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
      final String? out = (const RustBridgeLoader()).jsLint(script: code);

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
          final List<dynamic> errs =
              (obj['errors'] as List<dynamic>? ?? const <dynamic>[]);
          final String msg = errs.isNotEmpty
              ? ((errs.first as Map<String, dynamic>)['message'] as String? ??
                  'Invalid script')
              : 'Invalid script';
          setState(() => _lintError = msg);
        }
      }
    } catch (e, st) {
      debugPrint('script_editor: failed to parse linter output: $e\n$st');
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

  void _showUiComponentPalette() async {
    final String? template = await showUiComponentPalette(context: context);
    if (template == null || template.isEmpty) return;
    _insertSnippet(template);
  }

  void _insertSnippet(String snippet) {
    final text = _controller.text;
    final selection = _controller.selection;
    final baseOffset = selection.baseOffset;
    final extentOffset = selection.extentOffset;
    final hasSelection =
        baseOffset >= 0 && extentOffset >= 0 && baseOffset != extentOffset;

    final before =
        hasSelection ? text.replaceRange(baseOffset, extentOffset, '') : text;

    final insertPos = hasSelection
        ? baseOffset
        : (selection.baseOffset >= 0 ? selection.baseOffset : before.length);

    final updated =
        before.substring(0, insertPos) + snippet + before.substring(insertPos);
    _controller.text = updated;
    _controller.selection =
        TextSelection.collapsed(offset: insertPos + snippet.length);
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
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'TYPESCRIPT',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: _selectedTheme,
            underline: const SizedBox(),
            isDense: true,
            iconSize: 16,
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: _themes.keys.map((theme) {
              return DropdownMenuItem<String>(
                value: theme,
                child: Text(
                  _getDisplayName(theme),
                  style: TextStyle(
                    fontSize: 11,
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
          PopupMenuButton<void>(
            key: const Key('toolbarOverflowButton'),
            icon: const Icon(Icons.more_vert),
            iconSize: 20,
            onSelected: (_) {},
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lines: $_currentLineCount',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Chars: ${_controller.text.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('lineNumberToggle'),
                child: StatefulBuilder(
                  builder: (context, setState) => Row(
                    children: [
                      const Text('Line numbers'),
                      const Spacer(),
                      Switch.adaptive(
                        value: _showLineNumbers,
                        onChanged: (value) {
                          this.setState(() => _showLineNumbers = value);
                          setState(() {});
                          Navigator.pop(context);
                        },
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showIntegrations) ...[
                const PopupMenuDivider(),
                PopupMenuItem<void>(
                  key: const Key('uiPaletteButton'),
                  child: const Row(
                    children: [
                      Icon(Icons.widgets_rounded, size: 18),
                      SizedBox(width: 12),
                      Text('UI Components'),
                    ],
                  ),
                  onTap: () => Future.microtask(_showUiComponentPalette),
                ),
                PopupMenuItem<void>(
                  key: const Key('snippetsButton'),
                  child: const Row(
                    children: [
                      Icon(Icons.extension_rounded, size: 18),
                      SizedBox(width: 12),
                      Text('Code snippets'),
                    ],
                  ),
                  onTap: () => Future.microtask(_showIntegrationsHelp),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('copyCodeButton'),
                onTap: _copyCode,
                child: const Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Copy code'),
                  ],
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
            ? Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.3)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
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
            hasError ? Icons.error_rounded : Icons.check_circle_rounded,
            size: 12,
            color: hasError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(width: 8),

          // Status text
          Expanded(
            child: Text(
              hasError ? (_lintError ?? 'Syntax Error') : 'Code Valid',
              style: TextStyle(
                fontSize: 11,
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
            showErrors:
                _showLineNumbers, // Only show errors when line numbers are shown
            showFoldingHandles:
                _showLineNumbers, // Only show folding handles when line numbers are shown
            showLineNumbers: _showLineNumbers,
            width: _showLineNumbers
                ? 40
                : 0, // Eliminate gutter width when line numbers are hidden
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

/// Dialog shown when user attempts to close editor with unsaved changes
class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({
    super.key,
    required this.onDiscard,
    required this.onKeepEditing,
  });

  final VoidCallback onDiscard;
  final VoidCallback onKeepEditing;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsaved Changes'),
      content: const Text(
        'You have unsaved changes. Are you sure you want to discard them?',
      ),
      actions: [
        TextButton(
          onPressed: onKeepEditing,
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: onDiscard,
          child: const Text('Discard'),
        ),
      ],
    );
  }
}

/// Shows an unsaved changes confirmation dialog and returns true if user confirms discard
Future<bool> showUnsavedChangesDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => UnsavedChangesDialog(
      onDiscard: () => Navigator.of(context).pop(true),
      onKeepEditing: () => Navigator.of(context).pop(false),
    ),
  );
  return result ?? false;
}
