// Unit 2 of the SNS voting spec (docs/specs/2026-07-21-sns-voting-scripts.md).
//
// ScriptAppHost theme support: a bundle may include a top-level `theme` prop on
// the root UI node returned by `view()`, of the shape:
//
//   { type: 'column', theme: { background, card_background, accent,
//                              text, text_muted }, children: [...] }
//
// Each field is a hex string ('#RRGGBB', 'RRGGBB', '#RGB', or '#AARRGGBB').
// The host applies:
//   - background        → ColoredBox wrapping the scroll view (page bg).
//   - card_background   → Theme.colorScheme.surface + cardColor (sections).
//   - accent            → Theme.colorScheme.primary (filled buttons, highlights).
//   - text              → Theme.textTheme bodyColor/displayColor.
//   - text_muted        → Theme.hintColor + colorScheme.onSurfaceVariant.
//
// Missing/invalid fields are skipped silently — a bundle can ship only the
// fields it cares about. When the root node carries no `theme`, the host
// renders exactly as before (no ColoredBox, no Theme override).
//
// These tests drive [ScriptAppHost] with a runtime that returns a fixed view
// (no FFI, no network) and assert both branches of the gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

/// A runtime that returns a fixed UI tree on view(), so we can pump arbitrary
/// root nodes through [ScriptAppHost] without touching the FFI sandbox.
class _FixedUiRuntime implements IScriptAppRuntime {
  _FixedUiRuntime(this.ui);
  final Map<String, dynamic> ui;

  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': <dynamic>[],
    };
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'ui': ui};
  }

  @override
  Future<Map<String, dynamic>> update({
    required String script,
    required Map<String, dynamic> msg,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{'ok': true, 'state': state};
  }
}

const Map<String, dynamic> _kSnsTheme = <String, dynamic>{
  'background': '#0F1117',
  'card_background': '#1A1D29',
  'accent': '#7C5CFF',
  'text': '#E8E9F3',
  'text_muted': '#8E909A',
};

void main() {
  testWidgets(
      'root node with a `theme` prop wraps the renderer in a ColoredBox '
      '(background) and Theme override (surface/accent/text)', (tester) async {
    const Color expectedBackground = Color(0xFF0F1117);
    const Color expectedCard = Color(0xFF1A1D29);
    const Color expectedAccent = Color(0xFF7C5CFF);
    const Color expectedText = Color(0xFFE8E9F3);
    const Color expectedTextMuted = Color(0xFF8E909A);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: _FixedUiRuntime(const <String, dynamic>{
            'type': 'column',
            'theme': _kSnsTheme,
            'children': <dynamic>[
              <String, dynamic>{
                'type': 'section',
                'props': <String, dynamic>{'title': 'DAO'},
                'children': <dynamic>[
                  <String, dynamic>{
                    'type': 'text',
                    'props': <String, dynamic>{'text': 'hello'},
                  },
                ],
              },
            ],
          }),
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // 1. Background ColoredBox wraps the scrollable, painted with the theme
    //    background hex (the outermost ColoredBox in the host subtree).
    final Finder coloredBoxes = find.byType(ColoredBox);
    expect(coloredBoxes, findsWidgets,
        reason: 'a themed host must wrap the scroll view in a ColoredBox');
    final Iterable<ColoredBox> boxes = tester
        .widgetList<ColoredBox>(coloredBoxes)
        .where((b) => b.color == expectedBackground);
    expect(boxes, isNotEmpty,
        reason: 'background hex from theme must be applied to a ColoredBox');

    // 2. A Theme override sits between the host and the renderer; its
    //    colorScheme.surface / primary / onSurfaceVariant match the theme.
    final Finder themeAncestor = find.ancestor(
      of: find.byType(UiV1Renderer),
      matching: find.byType(Theme),
    );
    expect(themeAncestor, findsWidgets,
        reason: 'a themed host must inject a Theme override above the renderer');
    final ThemeData themeData =
        tester.widget<Theme>(themeAncestor.first).data;
    expect(themeData.colorScheme.surface, expectedCard,
        reason: 'card_background must override colorScheme.surface (Card)');
    expect(themeData.colorScheme.primary, expectedAccent,
        reason: 'accent must override colorScheme.primary (FilledButton)');
    expect(themeData.colorScheme.onSurfaceVariant, expectedTextMuted,
        reason: 'text_muted must override onSurfaceVariant');
    expect(themeData.cardColor, expectedCard,
        reason: 'card_background must also override legacy cardColor');
    // textTheme.bodyColor carries the body text color override.
    expect(themeData.textTheme.bodyLarge?.color, expectedText);
    expect(themeData.textTheme.bodyMedium?.color, expectedText);
    expect(themeData.textTheme.bodySmall?.color, expectedText);
    expect(themeData.hintColor, expectedTextMuted);
  });

  testWidgets(
      'root node WITHOUT a `theme` prop renders with no ColoredBox wrapper '
      'and no Theme override (default styling is preserved)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: _FixedUiRuntime(const <String, dynamic>{
            'type': 'column',
            'children': <dynamic>[
              <String, dynamic>{
                'type': 'text',
                'props': <String, dynamic>{'text': 'plain'},
              },
            ],
          }),
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // No injected Theme between Scaffold body and renderer (i.e. the Theme
    // found above UiV1Renderer is the MaterialApp's root theme, NOT a host
    // override). We assert this by checking there's NO Theme ancestor between
    // the SingleChildScrollView and the renderer.
    final Finder scroll = find.byType(SingleChildScrollView);
    final Finder themeBetween = find.descendant(
      of: scroll,
      matching: find.byType(Theme),
    );
    expect(themeBetween, findsNothing,
        reason: 'no theme prop → no Theme override below the scroll view');
    final Finder coloredBoxBetween = find.descendant(
      of: scroll,
      matching: find.byType(ColoredBox),
    );
    expect(coloredBoxBetween, findsNothing,
        reason: 'no theme prop → no ColoredBox below the scroll view');
  });

  testWidgets(
      'partial / malformed theme fields are skipped silently — only the '
      'valid ones apply (graceful degradation, no exceptions)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(
          runtime: _FixedUiRuntime(const <String, dynamic>{
            'type': 'column',
            'theme': <String, dynamic>{
              // Valid background only — everything else malformed or missing.
              'background': '#101418',
              'card_background': 'not-a-hex',
              'accent': <String, dynamic>{} /* wrong type */,
              // 'text' / 'text_muted' absent entirely.
            },
            'children': <dynamic>[],
          }),
          script: '/* bundle */',
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // Valid background applied.
    final Iterable<ColoredBox> bgBoxes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => b.color == const Color(0xFF101418));
    expect(bgBoxes, isNotEmpty,
        reason: 'valid background field must still apply');

    // Malformed accent must NOT poison the tree: no Theme override is injected
    // because no valid color-scheme field survived (accent is the only scheme
    // candidate and it was malformed). The host must not throw, must not apply
    // a half-formed override.
    final Finder scroll = find.byType(SingleChildScrollView);
    expect(
      find.descendant(of: scroll, matching: find.byType(Theme)),
      findsNothing,
      reason:
          'no valid card/accent/text field → no Theme override; background '
          'still applies as a ColoredBox',
    );
  });
}
