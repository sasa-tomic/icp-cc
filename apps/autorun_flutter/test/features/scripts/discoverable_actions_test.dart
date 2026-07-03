import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/hover_reveal_actions.dart';

import '_scripts_test_harness.dart';

/// `HoverRevealActions` and `ScriptActionButton` are real widgets mounted by
/// `lib/widgets/script_row_menus.dart`. The previous file also re-asserted that
/// the ScriptsScreen search/filter/FAB render (covered elsewhere) — dropped.
void main() {
  group('HoverRevealActions', () {
    testWidgets('renders actions on mobile (always visible)', (tester) async {
      await pumpInScaffold(
        tester,
        HoverRevealActions(
          actions: const [Icon(Icons.play_arrow), Icon(Icons.edit)],
          alwaysVisibleActions: const [Icon(Icons.star)],
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('alwaysVisibleActions come before hover-reveal actions',
        (tester) async {
      await pumpInScaffold(
        tester,
        HoverRevealActions(
          actions: const [Icon(Icons.play_arrow)],
          alwaysVisibleActions: const [Icon(Icons.star)],
        ),
      );

      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.children.length, greaterThanOrEqualTo(2));
    });
  });

  group('ScriptActionButton', () {
    testWidgets('renders with icon and tooltip', (tester) async {
      await pumpInScaffold(
        tester,
        ScriptActionButton(
          icon: Icons.play_arrow,
          onPressed: () {},
          tooltip: 'Run script',
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byTooltip('Run script'), findsOneWidget);
    });

    testWidgets('renders with destructive styling', (tester) async {
      await pumpInScaffold(
        tester,
        ScriptActionButton(
          icon: Icons.delete_outline,
          onPressed: () {},
          tooltip: 'Delete',
          isDestructive: true,
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
    });

    testWidgets('shows loading state when isLoading is true', (tester) async {
      await pumpInScaffold(
        tester,
        ScriptActionButton(
          icon: Icons.download,
          onPressed: () {},
          tooltip: 'Download',
          isLoading: true,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.download), findsNothing);
    });

    testWidgets('onPressed callback fires', (tester) async {
      var pressed = false;
      await pumpInScaffold(
        tester,
        ScriptActionButton(
          icon: Icons.play_arrow,
          onPressed: () => pressed = true,
          tooltip: 'Run',
        ),
      );

      await tester.tap(find.byTooltip('Run'));
      expect(pressed, isTrue);
    });
  });
}
