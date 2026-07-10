import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '_scripts_test_harness.dart';

/// IH-2 (UXR-5 / AUD-1): marketplace browse-load failures must surface as an
/// inline "Couldn't load the marketplace — Retry" panel, distinct from a
/// genuine empty result. Previously the catch only `debugPrint`ed and the UI
/// rendered the misleading "Your library is empty — create a script" state.
///
/// The DI seam is `ScriptsScreen.marketplaceService` (the abstract
/// `MarketplaceOpenApi`); the initial browse load only invokes `searchScripts`
/// + `getCategories`, so a boundary fake is the correct seam (no crypto here).

/// Controllable `MarketplaceOpenApi` whose `searchScripts` throws while
/// [searchError] is non-null and otherwise returns [scripts]. Lets a single
/// test drive the failure → retry → recovery transition deterministically.
class _ControllableMarketplaceApi implements MarketplaceOpenApi {
  _ControllableMarketplaceApi({
    List<MarketplaceScript> scripts = const [],
    this.searchError,
  }) : _scripts = scripts;

  final List<MarketplaceScript> _scripts;

  /// Non-null ⇒ the next `searchScripts` throws this. Null ⇒ succeeds.
  Object? searchError;
  int searchCalls = 0;

  @override
  Future<MarketplaceSearchResult> searchScripts({
    String? query,
    String? category,
    String? canisterId,
    double? minRating,
    double? maxPrice,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
    int limit = 20,
    int offset = 0,
  }) async {
    searchCalls++;
    final err = searchError;
    if (err != null) throw err;
    // `.toList()` (growable): ScriptsScreen clears the returned list on the
    // next search; a fixed-length list would throw on `.clear()`.
    return MarketplaceSearchResult(
      scripts: _scripts.toList(),
      total: _scripts.length,
      hasMore: false,
      offset: offset,
      limit: limit,
    );
  }

  @override
  List<String> getCategories() => const ['All'];

  @override
  Future<String> downloadScript(String scriptId, {String? version}) async => '';
}

MarketplaceScript _aScript() => aMarketplaceScript(
      id: 'mp-retry-1',
      title: 'Retryable Script',
    );

void main() {
  // The full ScriptsScreen (AppBar + OfflineBanner + search bar + FAB stack)
  // leaves a short body in the default 800x600 test viewport, which makes the
  // genuine-empty ModernEmptyState overflow. A tall surface (the established
  // convention in this dir — see downloaded_filter_test.dart) keeps the layout
  // representative of a real window.
  Future<void> pumpAtRealSize(
    WidgetTester tester, {
    required _ControllableMarketplaceApi api,
    Duration settle = const Duration(seconds: 1),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScriptsScreen(
      tester,
      controller: ScriptController(MockScriptRepository()),
      marketplaceService: api,
      settle: settle,
    );
    // Drain ModernEmptyState's entrance-animation timers (Future.delayed +
    // AnimationControllers) so no Timer is left pending at disposal. The
    // error-panel path has no such timers and returns after one frame.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  group('IH-2: marketplace load failure surfaces error + Retry', () {
    testWidgets(
        'FAILED load renders the error panel (not the misleading empty state) '
        'and a Retry button', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _ControllableMarketplaceApi(
        scripts: [_aScript()],
        searchError: Exception('backend down (ECONNREFUSED)'),
      );

      await pumpAtRealSize(tester, api: api);

      expect(api.searchCalls, 1);
      // Error panel (NOT the genuine-empty "Your library is empty" state).
      expect(find.text("Couldn't load the marketplace"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The short reason is rendered + honest (no silent masking).
      expect(find.text('backend down (ECONNREFUSED)'), findsOneWidget);
      // The misleading empty-state copy must NOT show on a load failure.
      expect(find.text('Your Script Library is Empty'), findsNothing);
    });

    testWidgets('tapping Retry re-invokes the load and recovers', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _ControllableMarketplaceApi(
        scripts: [_aScript()],
        searchError: Exception('backend down'),
      );

      await pumpAtRealSize(tester, api: api);
      expect(find.text("Couldn't load the marketplace"), findsOneWidget);
      expect(api.searchCalls, 1);

      // Clear the failure mode so the retry succeeds with the seeded script.
      api.searchError = null;

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Retry re-ran the load exactly once more.
      expect(api.searchCalls, 2);
      // Error panel is gone, the list now renders the recovered script.
      expect(find.text("Couldn't load the marketplace"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Retryable Script'), findsOneWidget);
    });

    testWidgets(
        'GENUINE empty result (service returns []) does NOT show the error '
        'panel — the normal empty state shows', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // No searchError, no scripts: a successful load that legitimately found
      // nothing. This must NOT be treated as a failure.
      final api = _ControllableMarketplaceApi(scripts: const []);

      await pumpAtRealSize(tester, api: api);

      expect(api.searchCalls, 1);
      // Error panel is absent on a genuine empty result.
      expect(find.text("Couldn't load the marketplace"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      // The normal, useful empty state shows instead.
      expect(find.text('Your Script Library is Empty'), findsOneWidget);
    });
  });
}
