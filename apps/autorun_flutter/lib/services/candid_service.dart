import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/canister_method.dart';
import '../rust/native_bridge.dart';
import '../rust/web/candid_interface_parser.dart';

/// Overrides the production Candid fetcher. In production the real FFI bridge
/// ([RustBridgeLoader.fetchCandid]) does the certified `read_state`
/// `candid:service` read; tests inject a fake to assert behavior without a
/// native library.
typedef CandidFetcher = Future<String?> Function(String canisterId, String? host);

/// Why a Candid interface could not be loaded for a canister.
///
/// R-3 (fixed 2026-07-23): the old HTTP registry path
/// (`icp-api.io/api/v2/canister/…/candid`) returned 404 for ALL canisters and
/// has been replaced by the certified FFI `read_state` `candid:service` path.
/// The FFI returns `null` for any failure (network, invalid id, no metadata,
/// library unavailable) without distinguishing the cause at the Dart boundary,
/// so there is a single kind.
enum CandidFetchErrorKind {
  /// The certified `read_state` path (via FFI `icp_fetch_candid`) returned no
  /// usable response — network error, canister not found, the bridge library
  /// is unavailable, or the canister doesn't expose `candid:service` metadata.
  fetchFailed,
}

/// Typed failure produced by [CandidService._fetchCandidViaReadState].
///
/// `toString()` renders the user-visible message:
/// `"Couldn't load Candid for <canister> via certified read_state"`.
class CandidFetchException implements Exception {
  CandidFetchException({required this.canisterId, this.cause});

  final String canisterId;
  final CandidFetchErrorKind kind = CandidFetchErrorKind.fetchFailed;
  final Object? cause;

  @override
  String toString() =>
      "Couldn't load Candid for $canisterId via certified read_state"
      "${cause != null ? ': $cause' : ''}";
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
///
/// R-3 (fixed 2026-07-23): the old HTTP registry path (`icp-api.io`) that 404'd
/// for ALL canisters has been replaced by the certified FFI `read_state`
/// `candid:service` path. Two real sources are consulted in order:
///   1. The canister's own `__get_candid_interface_tmp` query hook (fast for
///      canisters that implement it; absence is normal and falls through).
///   2. The certified `read_state` metadata path via FFI `icp_fetch_candid`
///      (`canister_client::fetch_candid`), the robust path that works for ALL
///      canisters including those without the hook (e.g. the ICP Ledger).
class CandidService {
  CandidService({CandidFetcher? fetchCandid}) : _customFetchCandid = fetchCandid;

  final CandidFetcher? _customFetchCandid;
  final RustBridgeLoader _bridge = const RustBridgeLoader();

  /// Fetch methods for a canister by parsing its Candid interface.
  ///
  /// Throws [CandidFetchException] when neither the probe hook nor the certified
  /// read_state path can supply the interface, and [CandidParseException] when
  /// the fetched interface text is malformed — never returns a stale/hardcoded
  /// fallback, never swallows a parse failure into an empty list.
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
  ///   2. The certified `read_state` `candid:service` metadata path via FFI
  ///      (`icp_fetch_candid`), the robust path that works for ALL canisters.
  ///      Failures here surface as [CandidFetchException].
  Future<String> _getCandidInterface(String canisterId, [String? host]) async {
    final direct = await _probeDirectCandid(canisterId, host);
    if (direct != null) {
      return direct;
    }
    final readState = await _fetchCandidViaReadState(canisterId, host);
    if (readState != null && readState.trim().isNotEmpty) {
      return readState;
    }
    throw CandidFetchException(canisterId: canisterId);
  }

  /// Best-effort probe of the canister's temporary Candid hook. Returns `null`
  /// when the canister does not expose the hook (or the FFI bridge is absent);
  /// in either case the certified read_state path is the robust fallback.
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
      // silently swallowed) and let read_state resolve the interface loudly.
      debugPrint('candid: __get_candid_interface_tmp probe miss for '
          '$canisterId: $e');
      return null;
    }
  }

  /// Fetch Candid via the certified `read_state` `candid:service` path. This is
  /// the robust path that works for ALL canisters, including those that don't
  /// implement the `__get_candid_interface_tmp` hook (e.g. the ICP Ledger).
  ///
  /// R-3: replaces the dead HTTP registry (`icp-api.io/api/v2/…`) which 404'd
  /// for every canister. In production this delegates to the FFI bridge
  /// (`icp_fetch_candid` → `canister_client::fetch_candid` →
  /// `read_state_canister_metadata("candid:service")`); tests inject via the
  /// constructor's [CandidFetcher].
  ///
  /// Returns `null` when the FFI bridge is unavailable or the read_state fails
  /// — the caller ([_getCandidInterface]) surfaces this as a typed
  /// [CandidFetchException].
  Future<String?> _fetchCandidViaReadState(String canisterId,
      [String? host]) async {
    try {
      if (_customFetchCandid != null) {
        return await _customFetchCandid(canisterId, host);
      }
      return await _bridge.fetchCandid(canisterId: canisterId, host: host);
    } catch (e) {
      debugPrint('candid: certified read_state fetch failed for '
          '$canisterId: $e');
      return null;
    }
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
