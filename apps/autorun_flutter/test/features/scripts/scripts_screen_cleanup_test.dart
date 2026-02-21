import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/widgets/marketplace_stats_banner.dart';
import 'package:icp_autorun/widgets/getting_started_card.dart';

void main() {
  group('ScriptsScreen UI cleanup', () {
    Future<void> pumpScriptsScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('search bar is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.text('Search scripts...'), findsOneWidget);
    });

    testWidgets('filter button is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('FAB for creating scripts is present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('MarketplaceStatsBanner widget is NOT in the tree',
        (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(MarketplaceStatsBanner), findsNothing);
    });

    testWidgets('share/publish banner text is NOT present', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.text('Share your first script!'), findsNothing);
      expect(
          find.text('Help others by sharing your scripts to the marketplace.'),
          findsNothing);
    });

    testWidgets('GettingStartedCard widget is NOT in the tree', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(GettingStartedCard), findsNothing);
    });

    testWidgets('ScriptsScreen renders without crashing', (tester) async {
      await pumpScriptsScreen(tester);

      expect(find.byType(ScriptsScreen), findsOneWidget);
    });
  });
}
