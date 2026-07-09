import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/canister_method.dart';
import '../rust/native_bridge.dart';
import '../theme/app_design_system.dart';

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

/// Service for fetching and parsing Candid interfaces.
class CandidService {
  CandidService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final RustBridgeLoader _bridge = RustBridgeLoader();

  /// Fetch methods for a canister by parsing its Candid interface.
  ///
  /// Throws [CandidFetchException] when the Candid registry cannot supply the
  /// interface — never returns a stale/hardcoded fallback.
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
    final baseUrl = host ?? 'https://icp-api.io';
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

  /// Parse Candid interface to extract method information
  List<CanisterMethod> _parseCandidMethods(String candidString) {
    final methods = <CanisterMethod>[];

    try {
      // Simple Candid parser - this is a basic implementation
      // In a production system, you'd want a more robust parser
      final lines = candidString.split('\n');

      for (final line in lines) {
        final trimmedLine = line.trim();

        // Skip comments, empty lines, and service declarations
        if (trimmedLine.isEmpty ||
            trimmedLine.startsWith('//') ||
            trimmedLine.startsWith('type ') ||
            trimmedLine.startsWith('service ')) {
          continue;
        }

        // Parse method definitions like:
        // method_name : (arg1: type1, arg2: type2) -> (return_type);
        final methodMatch = RegExp(
                r'^\s*(\w+)\s*:\s*\(([^)]*)\)\s*(?:->\s*\(([^)]*)\))?;?')
            .firstMatch(trimmedLine);

        if (methodMatch != null) {
          final methodName = methodMatch.group(1)!;
          final argsString = methodMatch.group(2) ?? '';
          final returnString = methodMatch.group(3);

          final args = _parseArgsString(argsString);
          final mode = _inferMethodMode(methodName, returnString);

          methods.add(CanisterMethod(
            name: methodName,
            mode: mode,
            args: args,
            returnType: returnString?.trim(),
          ));
        }
      }
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }

    return methods;
  }

  /// Parse argument string from Candid method signature
  List<CanisterArg> _parseArgsString(String argsString) {
    if (argsString.trim().isEmpty) return [];

    final args = <CanisterArg>[];
    final parts = argsString.split(',');

    for (final part in parts) {
      final trimmedPart = part.trim();
      if (trimmedPart.isEmpty) continue;

      // Parse arg name and type like "name : type"
      final argMatch = RegExp(r'^(\w+)\s*:\s*([^)]+)$').firstMatch(trimmedPart);
      if (argMatch != null) {
        final argName = argMatch.group(1)!;
        final argType = argMatch.group(2)!.trim();

        args.add(CanisterArg(
          name: argName,
          type: argType,
        ));
      }
    }

    return args;
  }

  /// Infer method mode (0=query, 1=update) based on name and return type
  int _inferMethodMode(String methodName, String? returnType) {
    // Query methods are typically read-only and don't modify state
    final queryPatterns = [
      'get_', 'query_', 'list_', 'fetch_', 'read_', 'find_',
      'account_balance', 'canister_status', 'tip_of_chain',
      'raw_rand', 'http_request'
    ];

    for (final pattern in queryPatterns) {
      if (methodName.startsWith(pattern)) {
        return 0; // query
      }
    }

    // Default to update for safety
    return 1; // update
  }
}
