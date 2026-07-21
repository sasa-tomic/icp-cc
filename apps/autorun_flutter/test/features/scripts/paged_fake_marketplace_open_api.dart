import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

/// Pagination-aware [MarketplaceOpenApi] fake for UX-N2 (scripts load-more).
///
/// The plain [FakeMarketplaceOpenApi] returns every script in one page with
/// `hasMore: false`. This variant honours the real service contract — slices
/// the seeded list by `limit`/`offset` and reports `hasMore` truthfully — so
/// tests can assert that scrolling to the bottom of the unified list triggers
/// a follow-up fetch and that the second page renders.
///
/// Records every `searchScripts` call's offset in [calls] so tests can assert
/// ordering, dedup, and the re-entrancy guard.
class PagedFakeMarketplaceOpenApi implements MarketplaceOpenApi {
  PagedFakeMarketplaceOpenApi({
    required List<MarketplaceScript> scripts,
    this.callDelay = Duration.zero,
  }) : _scripts = scripts {
    for (final s in scripts) {
      _byId[s.id] = s;
    }
  }

  final List<MarketplaceScript> _scripts;
  final Map<String, MarketplaceScript> _byId = {};
  final Duration callDelay;

  /// Offset of every `searchScripts` call, in call order. Lets tests assert
  /// that a scroll-to-bottom triggers exactly one follow-up call and that a
  /// second scroll while in-flight does NOT duplicate it.
  final List<int> calls = [];

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
    calls.add(offset);
    if (callDelay > Duration.zero) {
      await Future<void>.delayed(callDelay);
    }
    final end = (offset + limit).clamp(0, _scripts.length);
    final slice = _scripts.sublist(offset.clamp(0, _scripts.length), end);
    return MarketplaceSearchResult(
      scripts: slice.toList(growable: true),
      total: _scripts.length,
      hasMore: end < _scripts.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  List<String> getCategories() => const ['All'];

  @override
  Future<List<String>> fetchCategories() async => getCategories();

  @override
  Future<String> downloadScript(String scriptId, {String? version}) async {
    final script = _byId[scriptId];
    if (script == null) {
      throw StateError(
          'PagedFakeMarketplaceOpenApi has no script registered for id "$scriptId"');
    }
    return script.bundle;
  }
}
