import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/info_tooltip.dart';
import 'package:icp_autorun/utils/tech_terms.dart';

void main() {
  group('InfoTooltip', () {
    testWidgets('displays term name with info icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltip(term: TechTerm.canister),
        ),
      ));

      expect(find.text('Canister'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('hides icon when showIcon is false', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltip(term: TechTerm.canister, showIcon: false),
        ),
      ));

      expect(find.text('Canister'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });

    testWidgets('uses custom text style', (tester) async {
      const customStyle = TextStyle(fontSize: 20);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltip(
            term: TechTerm.principal,
            textStyle: customStyle,
          ),
        ),
      ));

      final text = tester.widget<Text>(find.text('Principal'));
      expect(text.style?.fontSize, 20);
    });

    testWidgets('shows full explanation in tooltip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltip(term: TechTerm.canister),
        ),
      ));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, TechTerm.canister.fullExplanation);
    });

    testWidgets('shows short explanation when useFullExplanation is false',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltip(
            term: TechTerm.canister,
            useFullExplanation: false,
          ),
        ),
      ));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, TechTerm.canister.shortExplanation);
    });
  });

  group('InfoTooltipText', () {
    testWidgets('displays custom text with tooltip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltipText(
            text: 'My Custom Text',
            term: TechTerm.keypair,
          ),
        ),
      ));

      expect(find.text('My Custom Text'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('tooltip uses term explanation', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InfoTooltipText(
            text: 'Keys',
            term: TechTerm.keypair,
          ),
        ),
      ));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, TechTerm.keypair.fullExplanation);
    });
  });

  group('TermWithTooltip', () {
    testWidgets('displays short explanation with icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TermWithTooltip(term: TechTerm.canister),
        ),
      ));

      expect(find.text(TechTerm.canister.shortExplanation), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('tooltip shows full explanation', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TermWithTooltip(term: TechTerm.query),
        ),
      ));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, TechTerm.query.fullExplanation);
    });
  });

  group('InlineTermTooltip', () {
    testWidgets('displays term name with icon by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineTermTooltip(term: TechTerm.cycles),
        ),
      ));

      expect(find.text('Cycles'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('hides icon when showIcon is false', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineTermTooltip(
            term: TechTerm.cycles,
            showIcon: false,
          ),
        ),
      ));

      expect(find.text('Cycles'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });

    testWidgets('uses custom style', (tester) async {
      const customStyle = TextStyle(fontSize: 10);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineTermTooltip(
            term: TechTerm.replica,
            style: customStyle,
          ),
        ),
      ));

      final text = tester.widget<Text>(find.text('Replica'));
      expect(text.style?.fontSize, 10);
    });
  });
}
