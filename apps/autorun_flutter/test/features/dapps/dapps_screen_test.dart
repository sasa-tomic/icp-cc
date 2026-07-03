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
///   (a) the shipped poll dapp renders as a card,
///   (b) tapping the card pushes [DappRunnerScreen].
///
/// ProfileScope is wrapped ABOVE MaterialApp (as in production main.dart) so
/// the pushed runner route can resolve the active profile.
void main() {
  testWidgets('renders the on-chain poll card', (tester) async {
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

    // Tap the poll card (its title text is unique).
    await tester.tap(find.text('On-chain Polls'));
    // One frame is enough for the route to land; avoid pumpAndSettle so the
    // test never blocks on the runner's async bundle/network work.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DappRunnerScreen), findsOneWidget,
        reason: 'Tapping the card should push DappRunnerScreen');
  });

  testWidgets('poll card advertises both access-path badges', (tester) async {
    await _pumpDapps(tester);
    expect(find.text('Backend direct'), findsOneWidget);
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
