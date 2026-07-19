import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/trust_badges.dart';

/// UX-H1: the product promise is *signed + sandboxed* scripts. These chips
/// make that promise visible at the moment of decision (browse tile, details
/// dialog header, run panel). Tests assert each badge variant renders the
/// expected text + icon and gates the verified marker on `MarketplaceAuthor.
/// isVerifiedDeveloper`.
void main() {
  group('UX-H1 trust badges', () {
    testWidgets('SandboxedChip renders "Sandboxed" text and a shield icon',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SandboxedChip()),
      ));

      expect(find.textContaining('Sandboxed'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('SignedByChip with verified author shows "Signed by" + name '
        'plus the verified badge', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SignedByChip(author: 'alice', verified: true),
        ),
      ));

      expect(find.textContaining('Signed by'), findsOneWidget);
      expect(find.textContaining('alice'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget,
          reason: 'verified author must surface the verified badge');
    });

    testWidgets('SignedByChip with unverified author shows "Signed by" + name '
        'but NO verified badge', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SignedByChip(author: 'alice', verified: false),
        ),
      ));

      expect(find.textContaining('Signed by'), findsOneWidget);
      expect(find.textContaining('alice'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsNothing,
          reason: 'unverified author must NOT show the verified badge');
    });

    testWidgets('SignatureVerifiedChip renders "Signature verified" with a '
        'check icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SignatureVerifiedChip()),
      ));

      expect(find.textContaining('Signature verified'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.verified ||
                  w.icon == Icons.verified_outlined ||
                  w.icon == Icons.verified_user_outlined ||
                  w.icon == Icons.check_circle ||
                  w.icon == Icons.check_circle_outline ||
                  w.icon == Icons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('badges render without exception in dark theme', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
          body: Column(
            children: [
              SandboxedChip(),
              SignedByChip(author: 'alice', verified: true),
              SignatureVerifiedChip(),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
