// ignore_for_file: lines_longer_than_80_chars

/// In-memory HTTP substrate for the Web e2e harness.
///
/// Routes every outbound `package:http` call from the REAL app into an
/// in-memory dispatcher that returns canned marketplace scripts, account
/// registrations, vault endpoints, etc. — mirroring the dev backend's
/// `/api/v1/*` contract byte-for-byte (envelopes are `{success, data}` shaped,
/// matching `MarketplaceOpenApiService._decodeSuccessResponse`).
///
/// Mechanism: the app's HTTP-using singletons (`MarketplaceOpenApiService`,
/// `PasskeyService`) each expose `overrideHttpClient(http.Client)`. We install
/// the same `MockClient` (built from a [SubstrateMockServer]) into BOTH
/// singletons in [installSubstrateHttp]. This is the cleanest Web-compatible
/// seam: `HttpOverrides.global` (the dart:io classic) is unavailable in the
/// browser, but `MockClient` from `package:http/testing.dart` is pure Dart.
///
/// Usage:
/// ```dart
/// final server = SubstrateMockServer()
///   ..envelope('GET', RegExp(r'/api/v1/health'), data: {'message': 'ok'})
///   ..envelope('POST', RegExp(r'/api/v1/scripts/search'),
///       data: () => {'scripts': [...], 'total': 3, 'hasMore': false});
/// installSubstrateHttp(server);
/// ```
///
/// **LOUD failure policy**: any un-routed call throws (rethrown by `MockClient`
/// as a transport error). The app surfaces the error — we never silently
/// return a default.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/passkey_service.dart';

/// Handler signature. Receives the inbound request; returns the canned
/// response. Throw to surface a transport error.
typedef SubstrateHandler = http.Response Function(http.Request request);

/// A canned marketplace script (mirrors the dev backend's seeded data).
///
/// Kept simple (Map) so test files can compose / override fields without a
/// model import. Fields match `MarketplaceScript.fromJson`.
class CannedScript {
  CannedScript({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.tags,
    required this.price,
    required this.authorName,
    required this.authorPrincipal,
    required this.authorPublicKey,
    required this.bundle,
    this.compatibility = 'All ICP Canisters',
    this.version = '1.0.0',
    this.uploadsSignature = 'test-signature',
    this.iconUrl = 'https://picsum.photos/seed/x/100/100.jpg',
    this.canisterIds = const ['rrkah-fqaaa-aaaaa-aaaaq-cai'],
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final List<String> tags;
  final double price;
  final String authorName;
  final String authorPrincipal;
  final String authorPublicKey;
  final String bundle;
  final String compatibility;
  final String version;
  final String uploadsSignature;
  final String iconUrl;
  final List<String> canisterIds;

  /// JSON shape byte-identical to the dev backend's `GET /scripts/:id` and
  /// `POST /scripts/search` item.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'slug': id,
        'title': title,
        'description': description,
        'category': category,
        'tags': jsonEncode(tags),
        'price': price,
        'currency': 'ICP',
        'downloads': 42,
        'rating': 4.5,
        'review_count': 3,
        'verified_review_count': 0,
        'author_name': authorName,
        'author_principal': authorPrincipal,
        'author_public_key': authorPublicKey,
        'upload_signature': uploadsSignature,
        'bundle': bundle,
        'compatibility': compatibility,
        'version': version,
        'icon_url': iconUrl,
        'screenshots': '[]',
        'canister_ids': jsonEncode(canisterIds),
        'is_public': true,
        'language': 'typescript',
        'owner_account_id': 'account-$id',
        'created_at': '2026-07-03 06:27:07',
        'updated_at': '2026-07-03 06:27:07',
        'deleted_at': null,
        'purchased': price == 0.0,
      };
}

/// The three seeded marketplace scripts the dev backend serves.
///
/// These mirror `curl http://127.0.0.1:35735/api/v1/scripts/search` exactly
/// (titles, ids, prices, categories). Tests that assert on tile labels
/// (`Interactive Counter`, etc.) get the same strings the real app shows on
/// the real desktop e2e suite — DRY contract across surfaces.
final List<CannedScript> defaultCannedScripts = <CannedScript>[
  CannedScript(
    id: 'interactive-counter',
    title: 'Interactive Counter',
    description:
        'A stateful counter with increment and reset. The simplest end-to-end '
        'demonstration of the init/view/update contract.',
    category: 'utility',
    tags: const ['counter', 'state', 'interactive', 'demo'],
    price: 4.99,
    authorName: 'GameDev Pro',
    authorPrincipal: '4w5t6-yae',
    authorPublicKey: 'test-public-key-gamedev',
    bundle: '// paid bundle placeholder — Interactive Counter',
  ),
  CannedScript(
    id: 'icp-balance-reader',
    title: 'ICP Balance Reader',
    description:
        'Query the ICP ledger canister and display a formatted balance.',
    category: 'data-processing',
    tags: const ['icp', 'ledger', 'balance', 'canister'],
    price: 1.99,
    authorName: 'Bob Coder',
    authorPrincipal: '3v5f3-hae',
    authorPublicKey: 'test-public-key-bob',
    bundle: '// paid bundle placeholder — ICP Balance Reader',
  ),
  CannedScript(
    id: 'hello-ic-starter',
    title: 'Hello IC Starter',
    description:
        'A minimal starter: greeting, counter, and text field. The canonical '
        'first ICP script.',
    category: 'utility',
    tags: const ['hello', 'starter', 'beginner', 'counter'],
    price: 0.0,
    authorName: 'Alice Developer',
    authorPrincipal: '2vxsx-fae',
    authorPublicKey: 'test-public-key-alice',
    bundle: '// Minimal TypeScript/QuickJS bundle: a greeting + counter.\n'
        '"use strict";\n'
        '(() => {\n'
        '  function init() { return { state: { count: 0, name: "" }, effects: [] }; }\n'
        '  function view(state) { return { type: "column", children: [] }; }\n'
        '  function update(msg, state) { return { state: state, effects: [] }; }\n'
        '  globalThis.init = init;\n'
        '  globalThis.view = view;\n'
        '  globalThis.update = update;\n'
        '})();',
  ),
];

/// A single `(METHOD, pathPattern, handler)` triple. Insertion-ordered so a
/// more-specific pattern (e.g. `/scripts/search`) can shadow a less-specific
/// one (e.g. `/scripts/:id`) by being registered first.
class _Route {
  const _Route(this.method, this.pathPattern, this.handler);
  final String method;
  final Pattern pathPattern;
  final SubstrateHandler handler;
}

/// In-memory HTTP dispatcher. Routes by `(METHOD, pathPattern)` and emits
/// marketplace-envelope responses (`{success:true, data:...}`).
class SubstrateMockServer {
  final List<_Route> _routes = <_Route>[];

  /// All routes registered so far (for diagnostics + assertions in tests).
  List<String> describeRoutes() => _routes
      .map((_Route r) => '${r.method} ${r.pathPattern}')
      .toList(growable: false);

  /// Register a raw handler. The handler receives the inbound [http.Request]
  /// and returns the canned [http.Response]. Throw to surface a transport
  /// error.
  void route(String method, Pattern pathPattern, SubstrateHandler handler) {
    _routes.add(_Route(method.toUpperCase(), pathPattern, handler));
  }

  /// Convenience: register a route that returns a `{success:true, data:...}`
  /// envelope. [data] may be a literal `Map`/`List` or a
  /// `Map<String, dynamic>/List Function()` for lazy/conditional bodies
  /// (the function form is evaluated on every dispatch, so it sees the latest
  /// server state).
  void envelope(
    String method,
    Pattern pathPattern, {
    Object? data,
    int status = 200,
  }) {
    route(method, pathPattern, (request) {
      final dynamic resolved = data is Function ? (data as Function)() : data;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          if (resolved != null) 'data': resolved,
        }),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
  }

  /// Convenience: register a route that returns a non-2xx envelope with a
  /// typed `error` field.
  void error(
    String method,
    Pattern pathPattern, {
    required String error,
    required int status,
    Object? data,
  }) {
    route(method, pathPattern, (request) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': false,
          'error': error,
          if (data != null) 'data': data,
        }),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
  }

  /// Build a `MockClient` that dispatches via this server.
  ///
  /// Un-routed calls fail LOUDLY: the handler throws an [UnsupportedError]
  /// describing the unmatched request (so the app's HTTP layer surfaces it
  /// instead of silently returning a default — AGENTS.md "no silent
  /// fallbacks").
  http.Client toClient() {
    return MockClient((http.Request request) async {
      final path = request.url.path;
      for (final _Route r in _routes) {
        if (r.method != request.method.toUpperCase()) continue;
        if (r.pathPattern.matchAsPrefix(path) != null) {
          return r.handler(request);
        }
      }
      throw UnsupportedError(
        'SubstrateMockServer: no route for ${request.method} $path. '
        'Registered routes:\n${describeRoutes().join("\n")}',
      );
    });
  }
}

/// Pre-seeded dispatcher with the routes the Tier-A flow set needs.
///
/// Matches the dev backend's contract (captured 2026-07-19); adding a route
/// here is the only change needed to support a new flow.
SubstrateMockServer defaultServer({
  List<CannedScript>? scripts,
}) {
  final list = scripts ?? defaultCannedScripts;
  final server = SubstrateMockServer();

  // Health + categories + stats.
  server.envelope('GET', RegExp(r'/api/v1/health$'),
      data: {'message': 'ICP Marketplace API is running'});
  server.envelope('GET', RegExp(r'/api/v1/scripts/categories$'), data: () {
    final cats = <String>{
      for (final CannedScript s in list) s.category,
    }.toList();
    return {'categories': cats};
  });
  server.envelope('GET', RegExp(r'/api/v1/marketplace-stats$'), data: () => {
        'totalScripts': list.length,
        'totalDownloads': list.fold(0, (int a, CannedScript s) => a + 42),
        'averageRating': 4.5,
      });

  // Search: POST /scripts/search → { scripts, total, hasMore, limit, offset }.
  // Search-by-query is approximated as "title or tag contains query" so the
  // scripts.search + scripts.search_no_results flows work on Web without the
  // real backend's full-text index.
  server.route('POST', RegExp(r'/api/v1/scripts/search$'), (request) {
    String? query;
    String? category;
    try {
      final dynamic decoded = jsonDecode(request.body);
      if (decoded is Map) {
        final q = decoded['query'];
        if (q is String && q.isNotEmpty) query = q.toLowerCase();
        final c = decoded['category'];
        if (c is String && c.isNotEmpty) category = c;
      }
    } on FormatException {
      // Body is empty or non-JSON; return the unfiltered list.
    }
    var filtered = list;
    if (category != null) {
      filtered =
          filtered.where((CannedScript s) => s.category == category).toList();
    }
    final q = query;
    if (q != null) {
      filtered = filtered.where((CannedScript s) {
        final title = s.title.toLowerCase();
        final tags = s.tags.map((t) => t.toLowerCase()).toList();
        return title.contains(q) ||
            tags.any((String t) => t.contains(q));
      }).toList();
    }
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'scripts': filtered.map((CannedScript s) => s.toJson()).toList(),
          'total': filtered.length,
          'hasMore': false,
          'limit': 20,
          'offset': 0,
        },
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  // Script details: GET /scripts/:id → { ...script }. Returns 404 envelope
  // for an unknown id (matches the real backend's error contract).
  server.route('GET', RegExp(r'/api/v1/scripts/[^/]+$'), (request) {
    final id = request.url.pathSegments.last;
    final match = list.where((CannedScript s) => s.id == id).toList();
    if (match.isEmpty) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'Script not found',
        }),
        404,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'data': match.first.toJson(),
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  // Script preview: GET /scripts/:id/preview → capped source excerpt.
  server.route('GET', RegExp(r'/api/v1/scripts/[^/]+/preview$'), (request) {
    final id = request.url.pathSegments[request.url.pathSegments.length - 2];
    final match = list.where((CannedScript s) => s.id == id).toList();
    if (match.isEmpty) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'Script not found',
        }),
        404,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'id': id,
          'title': match.first.title,
          'sourceExcerpt': match.first.bundle,
          'compatibility': match.first.compatibility,
          'version': match.first.version,
          'tags': match.first.tags,
        },
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  // Script reviews: GET /scripts/:id/reviews → { reviews: [], total, hasMore }.
  server.route('GET', RegExp(r'/api/v1/scripts/[^/]+/reviews$'), (request) {
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'reviews': <dynamic>[],
          'total': 0,
          'hasMore': false,
        },
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  // Account routes — registration returns a freshly-minted Account envelope;
  // lookup-by-username returns 404 (no accounts pre-registered).
  server.route('POST', RegExp(r'/api/v1/accounts$'), (request) {
    final dynamic decoded = jsonDecode(request.body);
    final username = (decoded is Map ? decoded['username'] : null) as String?;
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'id': 'account-${username ?? 'anon'}',
          'username': username ?? 'anon',
          'display_name': username ?? 'Anonymous',
          'public_keys': <dynamic>[],
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });
  server.route('GET', RegExp(r'/api/v1/accounts/[^/]+$'), (request) {
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': false,
        'error': 'Account not found',
      }),
      404,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });
  server.route(
      'GET', RegExp(r'/api/v1/accounts/by-public-key/[^/]+$'), (request) {
    return http.Response(
      jsonEncode(<String, dynamic>{
        'success': false,
        'error': 'Account not found',
      }),
      404,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  // Vault routes — accept the blob, persist in-memory, return it on get.
  // (No real crypto — the substrate boundary is the literal HTTP call, not
  // the client-side crypto path, which runs for real against the Web
  // pure-Dart impl.)
  final vaults = <String, Map<String, dynamic>>{};
  server.route('POST', RegExp(r'/api/v1/vault$'), (request) {
    final dynamic decoded = jsonDecode(request.body);
    final key = (decoded is Map ? decoded['author_public_key'] : null) as String?;
    vaults[key ?? 'default'] =
        (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{})
          ..remove('signature')
          ..remove('author_public_key')
          ..remove('author_principal')
          ..remove('timestamp')
          ..remove('nonce');
    return http.Response(
      jsonEncode(<String, dynamic>{'success': true, 'data': <String, dynamic>{}}),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });
  server.route('POST', RegExp(r'/api/v1/vault/get$'), (request) {
    final dynamic decoded = jsonDecode(request.body);
    final key = (decoded is Map ? decoded['author_public_key'] : null) as String?;
    final blob = vaults[key ?? 'default'];
    if (blob == null) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'Vault not found',
        }),
        404,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode(<String, dynamic>{'success': true, 'data': blob}),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  });

  return server;
}

/// Install a [SubstrateMockServer] into both HTTP-using singletons
/// (`MarketplaceOpenApiService`, `PasskeyService`).
///
/// Idempotent: re-installing replaces the prior client. The singletons are
/// process-wide so the substrate persists for the whole suite.
void installSubstrateHttp(SubstrateMockServer server) {
  final client = server.toClient();
  MarketplaceOpenApiService().overrideHttpClient(client);
  PasskeyService().overrideHttpClient(client);
}
