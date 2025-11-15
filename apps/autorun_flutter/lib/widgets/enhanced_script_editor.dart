import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
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
  String _selectedTheme = 'vs2015';

  // Available themes
  static const Map<String, Map<String, TextStyle>> _themes = {
    'vs2015': vs2015Theme,
    'atom-one-dark': atomOneDarkTheme,
    'monokai-sublime': monokaiSublimeTheme,
  };

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.topRight,
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
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
          // Language indicator with modern design
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.language.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // Theme selector with enhanced design
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: DropdownButton<String>(
              value: _selectedTheme,
              underline: const SizedBox(),
              isDense: true,
              icon: Icon(
                Icons.palette_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              items: _themes.keys.map((theme) {
                return DropdownMenuItem<String>(
                  value: theme,
                  child: Text(
                    theme.replaceAll('-', ' ').split(' ').map((word) =>
                      word[0].toUpperCase() + word.substring(1)
                    ).join(' '),
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
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTheme = theme);
                }
              },
            ),
          ),

          const Spacer(),

          // Stats section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Lines: $_currentLineCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Chars: ${_controller.text.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 20),

          // Actions with enhanced design
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showIntegrations) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Tooltip(
                    message: 'Code snippets & integrations',
                    child: IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showIntegrationsHelp();
                      },
                      icon: Icon(
                        Icons.extension_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Tooltip(
                  message: 'Format code',
                  child: IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _formatCode();
                    },
                    icon: Icon(
                      Icons.format_align_left_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Tooltip(
                  message: 'Copy code',
                  child: IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _copyCode();
                    },
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: hasError
            ? LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.8),
                  Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                ],
              )
            : LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                ],
              ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
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
          // Status indicator with animation
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: hasError
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (hasError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              hasError ? Icons.error_rounded : Icons.check_circle_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 12),

          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasError ? 'Syntax Error' : 'Code Valid',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                if (hasError) ...[
                  const SizedBox(height: 2),
                  Text(
                    _lintError ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Additional stats
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${_controller.text.length} chars',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
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
    // For now, use a simple monospace TextField with theme support
    // Full syntax highlighting would require a more complex implementation
    final TextStyle textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.6,
      color: _getTextColorForTheme(),
    );

    return TextField(
      controller: _controller,
      readOnly: widget.readOnly,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      expands: false,
      style: textStyle,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.all(16),
        border: InputBorder.none,
        hintText: '// Enter your Lua code here...',
      ),
      keyboardType: TextInputType.multiline,
    );
  }

  Color _getTextColorForTheme() {
    // Return appropriate text color based on selected theme
    switch (_selectedTheme) {
      case 'vs2015':
      case 'atom-one-dark':
      case 'monokai-sublime':
        return Colors.white;
      default:
        return Colors.black;
    }
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