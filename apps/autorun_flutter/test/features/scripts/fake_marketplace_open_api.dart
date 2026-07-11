import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

class FakeMarketplaceOpenApi implements MarketplaceOpenApi {
  FakeMarketplaceOpenApi({List<MarketplaceScript>? scripts}) {
    if (scripts != null) {
      for (final s in scripts) {
        _scripts[s.id] = s;
      }
    }
  }

  final Map<String, MarketplaceScript> _scripts = {};

  int searchCalls = 0;
  int downloadCalls = 0;

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
    // `toList()` (growable): ScriptsScreen reuses the returned list and calls
    // `.clear()` on the next search — a fixed-length list (toList(growable:
    // false)) would throw `UnsupportedError: Cannot clear a fixed-length list`.
    // The real MarketplaceOpenApiService returns growable lists.
    final all = _scripts.values.toList();
    return MarketplaceSearchResult(
      scripts: all,
      total: all.length,
      hasMore: false,
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
    downloadCalls++;
    final script = _scripts[scriptId];
    if (script == null) {
      throw StateError(
          'FakeMarketplaceOpenApi has no script registered for id "$scriptId"');
    }
    return script.bundle;
  }
}
