import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/canister_method.dart';
import '../rust/native_bridge.dart';
import '../rust/web/candid_interface_parser.dart';
import '../theme/app_design_system.dart';

/// The canonical Candid registry host — the authoritative source `dfx` uses
/// (`icp-api.io/api/v2/canister/…/candid`). Single source of truth for this
/// host so the literal cannot drift inline. (A-W6-11: was an inline magic
/// string at the call site.)
const String kCandidRegistryHost = 'https://icp-api.io';

/// Why a Candid interface could not be loaded for a canister.
///
/// Surfaced loudly to the caller (the canister-call builder UI) so the user
/// sees *why* the fetch failed instead of a silent null that feeds stale
/// signatures. Replaces the previous swallowed catch + hardcoded inline-Candid
/// fallback (TD-3).
enum CandidFetchErrorKind {
  /// Socket / DNS / timeout — the registry could not be reached at all.
  network,

  /// The registry answered with a non-success status code.
  non200,

  /// 200 OK but the body was empty.
  emptyBody,
}

/// Typed failure produced by [CandidService._fetchCandidFromRegistry].
///
/// `toString()` renders the user-visible message:
/// `"Couldn't load Candid for <canister>: <body> (<code>)"`.
class CandidFetchException implements Exception {
  CandidFetchException({
    required this.canisterId,
    required this.kind,
    this.statusCode,
    this.body,
    this.cause,
  });

  final String canisterId;
  final CandidFetchErrorKind kind;
  final int? statusCode;
  final String? body;
  final Object? cause;

  String get _reason {
    switch (kind) {
      case CandidFetchErrorKind.network:
        return 'network error (${cause ?? "unreachable"})';
      case CandidFetchErrorKind.non200:
        return '${body ?? "<empty body>"} ($statusCode)';
      case CandidFetchErrorKind.emptyBody:
        return 'empty response body ($statusCode)';
    }
  }

  @override
  String toString() => "Couldn't load Candid for $canisterId: $_reason";
}

/// Why a fetched Candid interface could not be parsed into methods.
///
/// The robust parser (`parseCandidInterface`) returns `null` on any parse
/// failure — parity with the native FFI's `null_c_string` on `Err`. Rather than
/// swallow that into a silent empty list (the forbidden F-2 pattern), it is
/// surfaced as this typed error so the caller (the canister-call builder UI)
/// shows *why* parsing failed instead of an empty method dropdown.
enum CandidParseErrorKind {
  /// The Candid text is malformed / not a valid `.did` interface (syntax error,
  /// no service actor, empty, garbage).
  malformed,
}

/// Typed failure produced by [CandidService._parseCandidMethods].
///
/// `toString()` renders the user-visible message:
/// `"Couldn't parse Candid interface: malformed (<cause>)"`.
class CandidParseException implements Exception {
  CandidParseException({required this.kind, this.cause});

  final CandidParseErrorKind kind;
  final Object? cause;

  @override
  String toString() =>
      "Couldn't parse Candid interface: ${kind.name} ($cause)";
}

/// Service for fetching and parsing Candid interfaces.
class CandidService {
  CandidService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final RustBridgeLoader _bridge = RustBridgeLoader();

  /// Fetch methods for a canister by parsing its Candid interface.
  ///
  /// Throws [CandidFetchException] when the Candid registry cannot supply the
  /// interface, and [CandidParseException] when the fetched interface text is
  /// malformed — never returns a stale/hardcoded fallback, never swallows a
  /// parse failure into an empty list.
  Future<List<CanisterMethod>> fetchCanisterMethods(
      String canisterId, [String? host]) async {
    final candidString = await _getCandidInterface(canisterId, host);
    if (candidString.isEmpty) {
      return [];
    }
    return _parseCandidMethods(candidString);
  }

  /// Get the Candid interface for a canister.
  ///
  /// Two real sources are consulted in order; neither is a hardcoded fallback:
  ///   1. The canister's own `__get_candid_interface_tmp` query hook (not all
  ///      canisters implement it — absence is normal and falls through).
  ///   2. The Candid registry (`icp-api.io/api/v2/canister/…/candid`), the
  ///      authoritative source `dfx` uses. Failures here surface as
  ///      [CandidFetchException].
  Future<String> _getCandidInterface(String canisterId, [String? host]) async {
    final direct = await _probeDirectCandid(canisterId, host);
    if (direct != null) {
      return direct;
    }
    return _fetchCandidFromRegistry(canisterId, host);
  }

  /// Best-effort probe of the canister's temporary Candid hook. Returns `null`
  /// when the canister does not expose the hook (or the FFI bridge is absent);
  /// in either case the registry is the authoritative fallback source.
  Future<String?> _probeDirectCandid(String canisterId, [String? host]) async {
    try {
      final response = await _bridge.callAnonymous(
        canisterId: canisterId,
        method: '__get_candid_interface_tmp',
        mode: 0, // query
        args: '()',
        host: host,
      );

      if (response == null || response.trim().isEmpty) {
        return null;
      }

      final parsed = json.decode(response);
      if (parsed is Map<String, dynamic> && parsed['candid'] is String) {
        return parsed['candid'] as String;
      }
      if (parsed is String) {
        return parsed;
      }
      return null;
    } catch (e) {
      // The hook is optional. Surface the probe miss in debug logs (not
      // silently swallowed) and let the registry resolve the interface loudly.
      debugPrint('candid: __get_candid_interface_tmp probe miss for '
          '$canisterId: $e');
      return null;
    }
  }

  /// Fetch Candid from the registry. Throws [CandidFetchException] loudly on
  /// any failure — no swallow, no null, no hardcoded fallback.
  Future<String> _fetchCandidFromRegistry(String canisterId,
      [String? host]) async {
    final baseUrl = host ?? kCandidRegistryHost;
    final url = Uri.parse('$baseUrl/api/v2/canister/$canisterId/candid');

    final http.Response response;
    try {
      response = await _httpClient
          .get(url, headers: {'User-Agent': AppConfig.userAgent})
          .timeout(AppDurations.networkRequest);
    } catch (e) {
      throw CandidFetchException(
        canisterId: canisterId,
        kind: CandidFetchErrorKind.network,
        cause: e,
      );
    }

    if (response.statusCode != 200) {
      throw CandidFetchException(
        canisterId: canisterId,
        kind: CandidFetchErrorKind.non200,
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    if (response.body.isEmpty) {
      throw CandidFetchException(
        canisterId: canisterId,
        kind: CandidFetchErrorKind.emptyBody,
        statusCode: response.statusCode,
      );
    }

    return response.body;
  }

  /// Parse a Candid interface into [CanisterMethod]s using the robust
  /// pure-Dart parser (`parseCandidInterface`) — the single source of truth.
  ///
  /// The query/update mode comes from the ACTUAL Candid annotation
  /// (`query`/`composite_query`/`oneway`/none), never from a name-prefix
  /// heuristic (the old `_inferMethodMode` was deleted: it mis-classified ICRC
  /// read methods like `symbol`/`decimals`/`balance_of` as updates — F-1).
  ///
  /// Throws [CandidParseException] loudly on malformed/empty/garbage input —
  /// never swallows the failure into an empty list (the forbidden F-2 pattern).
  List<CanisterMethod> _parseCandidMethods(String candidString) {
    // `parseCandidInterface` returns null on ANY parse error (parity with the
    // native FFI's null_c_string on Err) — surface it as a typed error.
    final json = parseCandidInterface(candidString);
    if (json == null) {
      throw CandidParseException(
        kind: CandidParseErrorKind.malformed,
        cause: 'unparseable Candid interface',
      );
    }

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final rawMethods =
        (decoded['methods'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rawMethods.map(_methodFromCandid).toList(growable: false);
  }

  /// Map one robust-parser method record to a [CanisterMethod].
  ///
  /// `kind` is the serde enum name (`"Query"`/`"Update"`/`"CompositeQuery"`)
  /// derived from the Candid annotation; it becomes the integer `mode` the
  /// canister-call builder consumes (0=query, 1=update, 2=composite).
  CanisterMethod _methodFromCandid(Map<String, dynamic> m) {
    final kind = m['kind'] as String? ?? 'Update';
    final argTypes = (m['args'] as List<dynamic>).cast<String>();
    final rets = (m['rets'] as List<dynamic>).cast<String>();
    // Candid args are positional on the wire; arg names are non-canonical and
    // intentionally dropped by the parser. Render them as positional labels
    // (`arg0`, `arg1`, …) for the builder UI, preserving the real type.
    final args = <CanisterArg>[
      for (var i = 0; i < argTypes.length; i++)
        CanisterArg(name: 'arg$i', type: argTypes[i]),
    ];
    return CanisterMethod(
      name: m['name'] as String? ?? '',
      mode: _modeFromKind(kind),
      args: args,
      returnType: rets.isEmpty ? null : rets.join(', '),
    );
  }

  /// Candid annotation → integer mode the builder uses.
  /// `query` → 0 (query); `composite_query` → 2 (composite); else → 1 (update).
  int _modeFromKind(String kind) {
    switch (kind) {
      case 'Query':
        return 0;
      case 'CompositeQuery':
        return 2;
      default: // "Update" (no mode / oneway)
        return 1;
    }
  }
}
