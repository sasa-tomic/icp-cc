import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Description + platform-independent key token for a single keyboard shortcut.
class ShortcutSpec {
  const ShortcutSpec(this.description, this.token);

  /// User-facing description shown in the help overlay.
  final String description;

  /// Key token where `mod` is the platform modifier (⌘ on macOS, Ctrl
  /// elsewhere). Examples: `mod+N`, `R`, `?`.
  final String token;
}

/// Single source of truth for desktop keyboard shortcuts. Consumed by both
/// [DesktopShortcuts.getShortcutLabel] and `ShortcutsHelpSheet`, so a
/// shortcut's label and key are defined in exactly one place.
const Map<String, ShortcutSpec> kShortcutSpecs = <String, ShortcutSpec>{
  'new': ShortcutSpec('Create a new script', 'mod+N'),
  'search': ShortcutSpec('Focus the search bar', 'mod+F'),
  'refresh': ShortcutSpec('Refresh scripts', 'R'),
  'tab1': ShortcutSpec('Go to Scripts', 'mod+1'),
  'tab2': ShortcutSpec('Go to Canisters', 'mod+2'),
  'help': ShortcutSpec('Show keyboard shortcuts', '?'),
};

bool _editableTextFocused() {
  final primary = FocusManager.instance.primaryFocus;
  final context = primary?.context;
  if (context == null) return false;
  var editable = false;
  context.visitAncestorElements((element) {
    if (element.widget is EditableText) {
      editable = true;
      return false;
    }
    return true;
  });
  return editable;
}

class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({
    super.key,
    required this.child,
    required this.onCreateScript,
    required this.onFocusSearch,
    required this.onRefresh,
    required this.onNavigateToTab,
    required this.onShowShortcuts,
  });

  final Widget child;
  final VoidCallback onCreateScript;
  final VoidCallback onFocusSearch;
  final VoidCallback onRefresh;
  final void Function(int index) onNavigateToTab;
  final VoidCallback onShowShortcuts;

  static bool get isDesktop {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  static String getShortcutLabel(String action) {
    final spec = kShortcutSpecs[action];
    return spec == null ? '' : formatShortcutToken(spec.token);
  }

  static String formatShortcutToken(String token) {
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    return token.replaceAll('mod', isMac ? '⌘' : 'Ctrl');
  }

  KeyEventResult _handleHelpKey(FocusNode node, KeyEvent event) {
    // `?` is Shift+'/' on US layouts; [KeyEvent.character] is the layout-
    // independent produced glyph. Skip when a text field is focused so users
    // can type '?' into search without summoning the overlay.
    if (event is KeyDownEvent &&
        event.character == '?' &&
        !_editableTextFocused()) {
      onShowShortcuts();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return child;
    }

    return Focus(
      onKeyEvent: _handleHelpKey,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(
                  PlatformShortcutModifier.modifier, LogicalKeyboardKey.keyN):
              const _CreateScriptIntent(),
          LogicalKeySet(
                  PlatformShortcutModifier.modifier, LogicalKeyboardKey.keyF):
              const _FocusSearchIntent(),
          LogicalKeySet(LogicalKeyboardKey.keyR): const _RefreshIntent(),
          LogicalKeySet(
                  PlatformShortcutModifier.modifier, LogicalKeyboardKey.digit1):
              const _NavigateTabIntent(0),
          LogicalKeySet(
                  PlatformShortcutModifier.modifier, LogicalKeyboardKey.digit2):
              const _NavigateTabIntent(1),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CreateScriptIntent: _CreateScriptAction(onCreateScript),
            _FocusSearchIntent: _FocusSearchAction(onFocusSearch),
            _RefreshIntent: _RefreshAction(onRefresh),
            _NavigateTabIntent: _NavigateTabAction(onNavigateToTab),
          },
          child: child,
        ),
      ),
    );
  }
}

class EscapeHandler extends StatefulWidget {
  const EscapeHandler({
    super.key,
    required this.child,
    this.onEscape,
  });

  final Widget child;
  final VoidCallback? onEscape;

  @override
  State<EscapeHandler> createState() => _EscapeHandlerState();
}

class _EscapeHandlerState extends State<EscapeHandler> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopShortcuts.isDesktop) {
      return widget.child;
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onEscape?.call();
        }
      },
      child: widget.child,
    );
  }
}

class _CreateScriptIntent extends Intent {
  const _CreateScriptIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _NavigateTabIntent extends Intent {
  final int index;
  const _NavigateTabIntent(this.index);
}

class _CreateScriptAction extends Action<_CreateScriptIntent> {
  _CreateScriptAction(this.onCreateScript);

  final VoidCallback onCreateScript;

  @override
  Object? invoke(_CreateScriptIntent intent) {
    onCreateScript();
    return null;
  }
}

class _FocusSearchAction extends Action<_FocusSearchIntent> {
  _FocusSearchAction(this.onFocusSearch);

  final VoidCallback onFocusSearch;

  @override
  Object? invoke(_FocusSearchIntent intent) {
    onFocusSearch();
    return null;
  }
}

class _RefreshAction extends Action<_RefreshIntent> {
  _RefreshAction(this.onRefresh);

  final VoidCallback onRefresh;

  @override
  Object? invoke(_RefreshIntent intent) {
    onRefresh();
    return null;
  }
}

class _NavigateTabAction extends Action<_NavigateTabIntent> {
  _NavigateTabAction(this.onNavigateToTab);

  final void Function(int index) onNavigateToTab;

  @override
  Object? invoke(_NavigateTabIntent intent) {
    onNavigateToTab(intent.index);
    return null;
  }
}

class PlatformShortcutModifier {
  static LogicalKeyboardKey get modifier {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return LogicalKeyboardKey.meta;
    }
    return LogicalKeyboardKey.control;
  }
}

class ShortcutTooltip extends StatelessWidget {
  const ShortcutTooltip({
    super.key,
    required this.label,
    required this.shortcut,
    required this.child,
  });

  final String label;
  final String shortcut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopShortcuts.isDesktop) {
      return Tooltip(message: label, child: child);
    }
    return Tooltip(message: '$label ($shortcut)', child: child);
  }
}
