// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/screens/dapps_screen.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

/// Widget coverage for the Dapps catalog tab:
///   (a) every shipped example renders as a card,
///   (b) tapping a card pushes [DappRunnerScreen],
///   (c) the catalog is HONEST about which examples work out of the box
///       (mainnet) vs need a local replica (developer) — UXR-6: never ship a
///       silently-dead tab.
///
/// ProfileScope is wrapped ABOVE MaterialApp (as in production main.dart) so
/// the pushed runner route can resolve the active profile.
void main() {
  testWidgets('renders a card for every shipped example', (tester) async {
    await _pumpDapps(tester);

    for (final d in exampleDapps) {
      expect(find.text(d.title), findsOneWidget,
          reason: '${d.title} card should be visible');
      expect(find.text(d.emoji), findsWidgets);
    }
  });

  testWidgets('tapping a dapp card pushes the runner screen', (tester) async {
    await _pumpDapps(tester);

    expect(find.byType(DappRunnerScreen), findsNothing);

    // Tap the ICP Ledger card (its title text is unique).
    await tester.tap(find.text('ICP Ledger'));
    // One frame is enough for the route to land; avoid pumpAndSettle so the
    // test never blocks on the runner's async bundle/network work.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DappRunnerScreen), findsOneWidget,
        reason: 'Tapping the card should push DappRunnerScreen');
  });

  testWidgets('catalog is HONEST: mainnet vs local-replica badges (UXR-6)',
      (tester) async {
    await _pumpDapps(tester);

    // The always-working mainnet example advertises that it works now.
    expect(find.text('Works now · Mainnet'), findsOneWidget,
        reason: 'The mainnet example must be clearly marked as working now');
    // The developer example is honestly flagged as needing a local replica.
    expect(find.text('Local replica'), findsOneWidget,
        reason: 'The local-replica example must not masquerade as working');
  });

  testWidgets(
      'every shipped example advertises the Backend-direct path; the poll '
      'dapp also advertises Frontend-in-browser', (tester) async {
    await _pumpDapps(tester);

    // Every example supports Backend direct → one badge per card.
    expect(find.text('Backend direct'), findsNWidgets(exampleDapps.length));
    // Only the poll dapp exposes the frontend-browser path.
    expect(find.text('Frontend in browser'), findsOneWidget);
  });
}

Future<void> _pumpDapps(WidgetTester tester) async {
  // A real ProfileController with no profiles: activeKeypair is null. It never
  // loads from storage during this test (no ensureLoaded call), so there is no
  // secure-storage dependency.
  final profileController = ProfileController(
    marketplaceService: MarketplaceOpenApiService(),
  );
  await tester.pumpWidget(
    ProfileScope(
      controller: profileController,
      child: MaterialApp(
        home: const DappsScreen(),
      ),
    ),
  );
  await tester.pump();
}
