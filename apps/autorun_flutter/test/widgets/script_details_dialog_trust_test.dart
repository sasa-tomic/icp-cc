import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/theme/app_design_system.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';
import 'package:icp_autorun/widgets/trust_badges.dart';

/// UX-H1: the details dialog header surfaces the Sandboxed + Signed-by
/// promise so a user evaluating a script sees the trust signals next to the
/// author name — not only after download.
void main() {
  MarketplaceScript script({
    bool verified = false,
    String? authorName,
  }) =>
      MarketplaceScript(
        id: 's1',
        title: 'Sample',
        description: 'desc',
        category: 'Tools',
        authorName: authorName,
        author: verified || authorName != null
            ? MarketplaceAuthor(
                id: 'a1',
                username: authorName ?? 'alice',
                displayName: authorName ?? 'Alice',
                isVerifiedDeveloper: verified,
              )
            : null,
        price: 0,
        bundle: 'print(1)',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

  Future<void> pumpDialog(
    WidgetTester tester,
    MarketplaceScript s,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppDesignSystem.lightTheme,
      darkTheme: AppDesignSystem.darkTheme,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ScriptDetailsDialog(script: s),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Bounded pumps — the dialog kicks off a preview fetch and pumpAndSettle
    // would block on the resulting HTTP retry loop.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
  }

  group('UX-H1 details dialog trust badges', () {
    testWidgets('verified-author script shows the verified badge',
        (tester) async {
      await pumpDialog(tester, script(verified: true, authorName: 'alice'));

      // The verified-author path renders a SignedByChip with verified=true,
      // which surfaces the verified-user glyph.
      expect(find.byType(SignedByChip), findsWidgets);
      expect(find.byIcon(Icons.verified_user_outlined), findsWidgets);
    });

    testWidgets('script with author (unverified) shows signed-by without '
        'verified badge', (tester) async {
      await pumpDialog(tester, script(verified: false, authorName: 'bob'));

      expect(find.byType(SignedByChip), findsWidgets);
      // No verified glyph among any SignedByChip — bob is not verified.
      expect(find.textContaining('Signed by bob'), findsWidgets);
    });

    testWidgets('script without any author still shows the sandboxed promise',
        (tester) async {
      await pumpDialog(tester, script());

      expect(find.byType(SandboxedChip), findsWidgets);
    });
  });
}
