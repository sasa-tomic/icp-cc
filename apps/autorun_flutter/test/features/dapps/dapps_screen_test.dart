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

    // The always-working mainnet examples advertise that they work now. Count
    // derived from the registry so the assertion stays correct as the catalog
    // grows.
    final mainnetCount =
        exampleDapps.where((d) => d.isMainnet).length;
    expect(find.text('Works now · Mainnet'), findsNWidgets(mainnetCount),
        reason: 'Every mainnet example must be marked as working now');
    // The developer example(s) are honestly flagged as needing a local replica.
    final localCount =
        exampleDapps.where((d) => d.isLocalReplica).length;
    expect(find.text('Local replica'), findsNWidgets(localCount),
        reason: 'Local-replica examples must not masquerade as working');
  });

  testWidgets(
      'every shipped example advertises the Backend-direct path; poll + NNS '
      'also advertise Frontend-in-browser', (tester) async {
    await _pumpDapps(tester);

    // Every example supports Backend direct → one badge per card.
    expect(find.text('Backend direct'), findsNWidgets(exampleDapps.length));
    // The count of frontend-browser badges matches the registry (currently
    // the poll dapp + NNS proposals; both expose a real public frontend).
    final frontendBrowserCount =
        exampleDapps.where((d) => d.hasFrontendBrowser).length;
    expect(find.text('Frontend in browser'),
        findsNWidgets(frontendBrowserCount));
  });
}

Future<void> _pumpDapps(WidgetTester tester) async {
  // The catalog is a scrolling ListView; with 4+ entries the default
  // 800x600 viewport clips the off-screen cards. Give ourselves a tall
  // canvas so every card lays out (the assertions check the full catalog).
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
