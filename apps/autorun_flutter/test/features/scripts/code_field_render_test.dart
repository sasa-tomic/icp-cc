import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/script_editor.dart';

import '_scripts_test_harness.dart';

/// WU-S3 — `CodeField` (from `flutter_code_editor`) was throwing
/// `ArgumentError: string is not well-formed UTF-16 … while building a
/// TextSpan` whenever the Scripts screen rendered content (NEW-3 in
/// `docs/specs/UX_REVIEW_ROUND2.md`). Flutter catches + reports it as a
/// silent frame error — which still fails widget tests and destabilises the
/// frame in production.
///
/// These tests render `ScriptEditor` (the only place the app mounts
/// `CodeField`) with (a) empty, (b) multi-line, and (c) special-character
/// content and assert NO exception is collected. They fail before the
/// defensive fix and pass after.
void main() {
  testWidgets('CodeField renders empty content without throwing', (tester) async {
    await pumpInScaffold(
      tester,
      SizedBox(
        height: 400,
        child: ScriptEditor(
          initialCode: '',
          minLines: 4,
          maxLines: 12,
          showIntegrations: false,
          onCodeChanged: (_) {},
        ),
      ),
    );
    // pumpAndSettle forces a full layout/paint pass so any TextSpan build
    // error surfaces via tester.exceptions.
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'CodeField must not throw while building TextSpans for empty content');
    expect(find.byType(CodeField), findsOneWidget);
  });

  testWidgets('CodeField renders multi-line JS content without throwing', (tester) async {
    const code = '''"use strict";
(() => {
  function init() {
    return { state: { count: 0, name: "" }, effects: [] };
  }

  function view(state) {
    const count = state.count || 0;
    const greeting = name.length > 0 ? "Hello, " + name + "!" : "Hello, world!";
    return {
      type: "column",
      children: [
        { type: "text", props: { text: greeting } },
      ],
    };
  }

  function update(msg, state) {
    const t = (msg && msg.type) || "";
    if (t === "inc") return { state: { ...state, count: state.count + 1 }, effects: [] };
    return { state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''';
    await pumpInScaffold(
      tester,
      SizedBox(
        height: 400,
        child: ScriptEditor(
          initialCode: code,
          minLines: 4,
          maxLines: 12,
          showIntegrations: false,
          onCodeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'CodeField must not throw while building TextSpans for multi-line JS');
    expect(find.byType(CodeField), findsOneWidget);
  });

  testWidgets('CodeField renders content with special characters without throwing',
      (tester) async {
    // Strings that historically trip up highlighters / TextSpan: emoji, CJK,
    // RTL marks, NBSP, fullwidth punctuation, regex meta — and, critically,
    // a genuine LONE (unpaired) high surrogate. A lone surrogate is malformed
    // UTF-16; the Flutter engine throws
    // `ArgumentError: string is not well-formed UTF-16` from
    // `ParagraphBuilder.addText` while building the highlight TextSpan. This is
    // the NEW-3 root cause and the case that FAILS without the sanitize step in
    // `ScriptEditor` (marketplace/script content loaded over the network can
    // carry such sequences).
    const bulk = r'''
const greeting = "Hello, 世界! 👋 \u00A0 € — … ";
const regex = /^[\w\u00C0-\u017F]+$/gi;
const path = "C:\\Users\\Jon Dough";
const emoji = "🌟🎉✨";
const arrows = "←↑→↓↔↕";
const math = "≠≈≤≥±×÷∑∏∫√∞";
console.log(`${greeting} | ${regex} | ${emoji}`);
''';
    // `\uD800` is a lone high surrogate (no following low surrogate) = the
    // exact malformed-UTF-16 sequence the engine rejects.
    final code = '$bulk\n// lone surrogate: \uD800\n';
    await pumpInScaffold(
      tester,
      SizedBox(
        height: 400,
        child: ScriptEditor(
          initialCode: code,
          minLines: 4,
          maxLines: 12,
          showIntegrations: false,
          onCodeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'CodeField must not throw while building TextSpans for '
            'special chars incl. malformed UTF-16 (lone surrogate)');
    expect(find.byType(CodeField), findsOneWidget);
  });
}
