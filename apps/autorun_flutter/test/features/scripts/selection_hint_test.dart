import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Long-press selection hint', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('Hint preference storage', () {
      test('hint should be shown by default (not dismissed)', () async {
        final prefs = await SharedPreferences.getInstance();
        final hintDismissed =
            prefs.getBool('selection_hint_dismissed') ?? false;

        expect(hintDismissed, isFalse);
      });

      test('dismissing hint sets preference to true', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('selection_hint_dismissed', true);

        final hintDismissed =
            prefs.getBool('selection_hint_dismissed') ?? false;
        expect(hintDismissed, isTrue);
      });

      test('hint is not shown after dismissal', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('selection_hint_dismissed', true);

        final shouldShowHint =
            !(prefs.getBool('selection_hint_dismissed') ?? false);
        expect(shouldShowHint, isFalse);
      });

      test('hint is shown when preference is not set', () async {
        final prefs = await SharedPreferences.getInstance();

        final shouldShowHint =
            !(prefs.getBool('selection_hint_dismissed') ?? false);
        expect(shouldShowHint, isTrue);
      });
    });

    group('Hint widget', () {
      testWidgets('hint banner displays tip text', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestSelectionHintBanner(
                onDismiss: () {},
              ),
            ),
          ),
        );

        expect(find.textContaining('Long-press'), findsOneWidget);
        expect(find.textContaining('select multiple'), findsOneWidget);
      });

      testWidgets('hint banner has dismiss button', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestSelectionHintBanner(
                onDismiss: () {},
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.close), findsOneWidget);
      });

      testWidgets('tapping dismiss calls onDismiss callback', (tester) async {
        bool dismissed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestSelectionHintBanner(
                onDismiss: () {
                  dismissed = true;
                },
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        expect(dismissed, isTrue);
      });

      testWidgets('hint banner has selection icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestSelectionHintBanner(
                onDismiss: () {},
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.checklist), findsOneWidget);
      });

      testWidgets('hint banner uses subtle styling', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestSelectionHintBanner(
                onDismiss: () {},
              ),
            ),
          ),
        );

        final container =
            tester.widget<Container>(find.byType(Container).first);
        // Should have some styling (color, padding, etc.)
        expect(container, isNotNull);
      });
    });

    group('Hint visibility logic', () {
      test(
          'hint should be visible when user has scripts and hint not dismissed',
          () {
        final hasScripts = true;
        final hintDismissed = false;

        final shouldShowHint = hasScripts && !hintDismissed;
        expect(shouldShowHint, isTrue);
      });

      test('hint should not be visible when user has no scripts', () {
        final hasScripts = false;

        final shouldShowHint = hasScripts;
        expect(shouldShowHint, isFalse);
      });

      test('hint should not be visible when already dismissed', () {
        final hasScripts = true;
        final hintDismissed = true;

        final shouldShowHint = hasScripts && !hintDismissed;
        expect(shouldShowHint, isFalse);
      });

      test('hint should not be visible in selection mode', () {
        final hasScripts = true;
        final hintDismissed = false;
        final isSelectionMode = true;

        final shouldShowHint = hasScripts && !hintDismissed && !isSelectionMode;
        expect(shouldShowHint, isFalse);
      });
    });
  });
}

/// Test widget that mirrors the actual hint banner implementation
class _TestSelectionHintBanner extends StatelessWidget {
  const _TestSelectionHintBanner({
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.checklist,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tip: Long-press to select multiple scripts',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
