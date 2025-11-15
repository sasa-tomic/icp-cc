import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/canister_method.dart';
import '../rust/native_bridge.dart';

/// Service for fetching and parsing Candid interfaces
class CandidService {
  final RustBridgeLoader _bridge = RustBridgeLoader();

  /// Fetch methods for a canister by parsing its Candid interface
  Future<List<CanisterMethod>> fetchCanisterMethods(String canisterId, [String? host]) async {
    try {
      // Get the Candid interface from the canister
      final candidString = await _getCandidInterface(canisterId, host);
      if (candidString == null || candidString.isEmpty) {
        return [];
      }

      // Parse the Candid interface to extract method information
      return _parseCandidMethods(candidString);
    } catch (e) {
      throw Exception('Failed to fetch canister methods: $e');
    }
  }

  /// Get the Candid interface for a canister
  Future<String?> _getCandidInterface(String canisterId, [String? host]) async {
    try {
      // Try to get Candid from the canister's __get_candid_interface_tmp method
      final response = _bridge.callAnonymous(
        canisterId: canisterId,
        method: '__get_candid_interface_tmp',
        kind: 0, // query
        args: '()',
        host: host,
      );

      if (response != null && response.trim().isNotEmpty) {
        // Parse the response to extract the Candid string
        final parsed = json.decode(response);
        if (parsed is Map<String, dynamic> && parsed['candid'] is String) {
          return parsed['candid'] as String;
        }
        if (parsed is String) {
          return parsed;
        }
      }

      // Fallback: try to fetch from icp-api.io if available
      return await _fetchCandidFromRegistry(canisterId, host);
    } catch (e) {
      // As a last resort, return some common methods for well-known canisters
      return _getFallbackCandid(canisterId);
    }
  }

  /// Try to fetch Candid from a registry or known source
  Future<String?> _fetchCandidFromRegistry(String canisterId, [String? host]) async {
    try {
      final baseUrl = host ?? 'https://icp-api.io';
      final url = Uri.parse('$baseUrl/api/v2/canister/$canisterId/candid');

      final response = await http.get(
        url,
        headers: {'User-Agent': 'ICP-Autorun-Flutter/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return response.body;
      }
    } catch (e) {
      // Ignore errors and return null
    }
    return null;
  }

  /// Get fallback Candid definitions for well-known canisters
  String? _getFallbackCandid(String canisterId) {
    switch (canisterId) {
      case 'rrkah-fqaaa-aaaaa-aaaaq-cai': // NNS Governance
        return '''
service : {
  get_pending_proposals : () -> (vec proposal_info);
  get_proposal_info : (int) -> (opt proposal_info);
  list_proposals : (vec record { int; int }) -> (vec proposal_info);
  get_neuron_ids : () -> (vec record { int64 });
  get_neuron_info : (int64) -> (opt neuron_info);
  submit_proposal : (proposal) -> (int64);
}
''';
      case 'ryjl3-tyaaa-aaaaa-aaaba-cai': // ICP Ledger
        return '''
service : {
  account_balance : (account_balance_args) -> (ICP);
  transfer : (transfer_args) -> (transfer_result);
  query_blocks : (query_blocks_args) -> (query_blocks_response);
  get_blocks : (get_blocks_args) -> (get_blocks_response);
  tip_of_chain : () -> (tip_of_chain_response);
}
''';
      case 'aaaaa-aa': // Management canister
        return '''
service : {
  provision_creatable_canisters : (record { canister_id_ranges: vec record { start: principal; end: principal } }) -> (record {});
  create_canister : (record { settings: opt canister_settings; sender_canister_version: opt nat64 }) -> (record { canister_id: principal });
  update_settings : (record { canister_id: principal; settings: canister_settings; sender_canister_version: opt nat64 }) -> (record {});
  install_code : (record { mode: variant { install; reinstall; upgrade }; canister_id: principal; wasm_module: blob; arg: blob; compute_allocation: opt nat; memory_allocation: opt nat; controller: opt principal }) -> (record {});
  uninstall_code : (record { canister_id: principal; }) -> (record {});
  start_canister : (record { canister_id: principal; }) -> (record {});
  stop_canister : (record { canister_id: principal; }) -> (record {});
  canister_status : (record { canister_id: principal; }) -> (record { status: variant { stopped; stopping; running }; settings: canister_settings; module_hash: opt blob; controller: principal; memory_size: nat; cycles: nat; idle_cycles_burned_per_day: nat });
  delete_canister : (record { canister_id: principal; }) -> (record {});
  deposit_cycles : (record { canister_id: principal; }) -> (record {});
  raw_rand : () -> (vec nat8);
  httpRequest : (record { url: text; method: variant { get; post; head }; body: opt blob; max_response_bytes: opt nat64; transform: opt record { function: principal; context: vec nat8 }; headers: vec record { name: text; value: text } }) -> (record { status: nat; body: vec nat8; headers: vec record { name: text; value: text } });
}
''';
      default:
        return null;
    }
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
        final methodMatch = RegExp(r'^\s*(\w+)\s*:\s*\(([^)]*)\)\s*(?:->\s*\(([^)]*)\))?;?').firstMatch(trimmedLine);

        if (methodMatch != null) {
          final methodName = methodMatch.group(1)!;
          final argsString = methodMatch.group(2) ?? '';
          final returnString = methodMatch.group(3);

          final args = _parseArgsString(argsString);
          final kind = _inferMethodKind(methodName, returnString);

          methods.add(CanisterMethod(
            name: methodName,
            kind: kind,
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

  /// Infer method kind (query/update) based on name and return type
  int _inferMethodKind(String methodName, String? returnType) {
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