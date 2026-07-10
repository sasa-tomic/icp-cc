import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '_scripts_test_harness.dart';

/// W6-8 (UX finding W6-6): searching for a term that matches nothing must NOT
/// render the "Your Script Library is Empty" state when the library actually
/// has scripts. It must instead show a DISTINCT "no results" message that
/// references the query, plus a Clear-search affordance — so the user
/// understands the search came up empty rather than their whole library.
///
/// The DI seam is `ScriptsScreen(marketplaceService:, controller:)`. The
/// marketplace browse only invokes `searchScripts` + `getCategories`, so a
/// boundary fake is the correct seam (no crypto here).
void main() {
  /// Pumps the full ScriptsScreen at a realistic size (the AppBar + search bar
  /// + FAB stack leaves a short body in the default 800x600 viewport, making
  /// the ModernEmptyState overflow). Seeds one installed local script.
  Future<void> pumpWithInstalledScript(
    WidgetTester tester, {
    String scriptTitle = 'Hello World',
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = MockScriptRepository()
      ..addScript(aLocalScript(title: scriptTitle));
    final controller = ScriptController(repo);

    await pumpScriptsScreen(
      tester,
      controller: controller,
      marketplaceService: FakeMarketplaceOpenApi(),
    );
  }

  group('W6-8: no-match search empty state', () {
    testWidgets(
        'search matching nothing shows a distinct "No scripts match" state, '
        'NOT "Your Script Library is Empty"', (tester) async {
      await pumpWithInstalledScript(tester);

      // Sanity: the installed script is rendered before searching.
      expect(find.text('Hello World'), findsOneWidget);

      // Enter a query that matches no local script and no marketplace script.
      await tester.enterText(find.byType(TextField), 'zzzznomatch');
      await tester.pump(); // flush onChanged → _onSearchChanged
      // Past the 500ms debounce so the marketplace reload settles and the
      // searching flag flips back to false.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // DISTINCT no-results message that references the query. Exact-match the
      // title so it isn't confused with the query text still in the search box.
      expect(find.text("No scripts match 'zzzznomatch'"), findsOneWidget);
      // Clear-search affordance present.
      expect(find.text('Clear search'), findsOneWidget);
      // The misleading "library is empty" copy must NOT show while a search
      // is active and the library genuinely has scripts.
      expect(find.text('Your Script Library is Empty'), findsNothing);
    });

    testWidgets(
        'tapping "Clear search" restores the installed scripts', (tester) async {
      await pumpWithInstalledScript(tester);

      await tester.enterText(find.byType(TextField), 'zzzznomatch');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Clear search'), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The installed script is visible again.
      expect(find.text('Hello World'), findsOneWidget);
      // No-results copy is gone.
      expect(find.textContaining('No scripts match'), findsNothing);
    });

    testWidgets(
        'genuinely empty library with NO search still shows '
        '"Your Script Library is Empty"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // No scripts anywhere and no search query.
      final controller = ScriptController(MockScriptRepository());

      await pumpScriptsScreen(
        tester,
        controller: controller,
        marketplaceService: FakeMarketplaceOpenApi(),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Your Script Library is Empty'), findsOneWidget);
      expect(find.textContaining('No scripts match'), findsNothing);
    });
  });
}
