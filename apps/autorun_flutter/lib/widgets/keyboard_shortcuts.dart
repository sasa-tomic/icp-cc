import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Description + platform-independent key token(s) for a single keyboard
/// shortcut.
class ShortcutSpec {
  const ShortcutSpec(this.description, this.token, [this.altToken]);

  /// User-facing description shown in the help overlay.
  final String description;

  /// Primary key token where `mod` is the platform modifier (⌘ on macOS, Ctrl
  /// elsewhere). Examples: `Alt+1`, `/`, `N`, `?`.
  final String token;

  /// Optional secondary binding shown alongside the primary token, e.g. the
  /// search shortcut responds to `/` *and* `mod+F`. `null` when there is only
  /// one binding.
  final String? altToken;
}

/// Single source of truth for desktop keyboard shortcuts. Consumed by both
/// [DesktopShortcuts.getShortcutLabel] and `ShortcutsHelpSheet`, so a
/// shortcut's keys and description are defined in exactly one place and the
/// help overlay can never drift from the live bindings.
const Map<String, ShortcutSpec> kShortcutSpecs = <String, ShortcutSpec>{
  'new': ShortcutSpec('Create a new script', 'N'),
  // `/` is the GitHub/YouTube "focus search" convention; Ctrl/Cmd+F is the
  // universal browser one — both are wired and listed together.
  'search': ShortcutSpec('Focus the search bar', '/', 'mod+F'),
  'refresh': ShortcutSpec('Refresh scripts', 'R'),
  'tab1': ShortcutSpec('Go to Scripts', 'Alt+1'),
  'tab2': ShortcutSpec('Go to Canisters', 'Alt+2'),
  'tab3': ShortcutSpec('Go to Dapps', 'Alt+3'),
  'help': ShortcutSpec('Show keyboard shortcuts', '?'),
};

/// True when the user is currently editing text somewhere. Every guarded
/// shortcut action consults this so it stays inert while the user types —
/// letting them type a literal `?`, `/`, `N`, etc. into any text field.
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

/// Builds a [SingleActivator] using the platform "modify" key (⌘ on macOS,
/// Ctrl elsewhere) combined with [key].
SingleActivator _platformModifier(LogicalKeyboardKey key) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return SingleActivator(key, meta: true);
  }
  return SingleActivator(key, control: true);
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

  /// Desktop platforms (macOS/Linux/Windows) own the keyboard-shortcut layer.
  /// On mobile/web the widget is a transparent pass-through.
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
    // `?` is Shift+'/' on US layouts; [KeyEvent.character] is the
    // layout-independent produced glyph. Plain `/` (no Shift) is bound in the
    // Shortcuts map below and intercepted before reaching here because
    // SingleActivator(slash) requires shift=false. Shift+/ therefore falls
    // through to this handler. Skip when a text field is focused so users can
    // type '?' into search without summoning the overlay.
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
        shortcuts: <ShortcutActivator, Intent>{
          // Alt+digit → switch tab. Alt is the universal browser "go to tab N"
          // modifier and never clobbers digit entry in text fields.
          const SingleActivator(LogicalKeyboardKey.digit1, alt: true):
              const _NavigateTabIntent(0),
          const SingleActivator(LogicalKeyboardKey.digit2, alt: true):
              const _NavigateTabIntent(1),
          const SingleActivator(LogicalKeyboardKey.digit3, alt: true):
              const _NavigateTabIntent(2),
          // `/` (GitHub/YouTube) and Ctrl/Cmd+F (browser) both focus search.
          // Both are guard-disabled while typing (see _GuardedAction) so the
          // user can still type a literal `/` into any text field.
          const SingleActivator(LogicalKeyboardKey.slash):
              const _FocusSearchIntent(),
          _platformModifier(LogicalKeyboardKey.keyF):
              const _FocusSearchIntent(),
          // Plain letters also reach the Shortcuts layer while an EditableText
          // has focus (EditableText ignores printable keys), so the guard is
          // load-bearing here, not decorative.
          const SingleActivator(LogicalKeyboardKey.keyN):
              const _CreateScriptIntent(),
          const SingleActivator(LogicalKeyboardKey.keyR):
              const _RefreshIntent(),
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

/// Action base that refuses to run while a text field is being edited, so no
/// global shortcut (new script, refresh, switch tab, focus search) ever
/// interrupts typing. Plain-letter and slash shortcuts reach the Shortcuts
/// layer even with an EditableText focused — EditableText ignores printable
/// keys — so this guard is essential, not decorative.
abstract class _GuardedAction<T extends Intent> extends Action<T> {
  @override
  bool isEnabled(T intent) => !_editableTextFocused();
}

class _CreateScriptAction extends _GuardedAction<_CreateScriptIntent> {
  _CreateScriptAction(this.onCreateScript);

  final VoidCallback onCreateScript;

  @override
  Object? invoke(_CreateScriptIntent intent) {
    onCreateScript();
    return null;
  }
}

class _FocusSearchAction extends _GuardedAction<_FocusSearchIntent> {
  _FocusSearchAction(this.onFocusSearch);

  final VoidCallback onFocusSearch;

  @override
  Object? invoke(_FocusSearchIntent intent) {
    onFocusSearch();
    return null;
  }
}

class _RefreshAction extends _GuardedAction<_RefreshIntent> {
  _RefreshAction(this.onRefresh);

  final VoidCallback onRefresh;

  @override
  Object? invoke(_RefreshIntent intent) {
    onRefresh();
    return null;
  }
}

class _NavigateTabAction extends _GuardedAction<_NavigateTabIntent> {
  _NavigateTabAction(this.onNavigateToTab);

  final void Function(int index) onNavigateToTab;

  @override
  Object? invoke(_NavigateTabIntent intent) {
    onNavigateToTab(intent.index);
    return null;
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
