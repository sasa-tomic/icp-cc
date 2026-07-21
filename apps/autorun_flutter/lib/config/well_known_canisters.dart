import 'package:flutter/material.dart';

/// A single well-known Internet Computer canister exposed across every
/// "pick a canister" surface in icp-cc.
///
/// This is the **single source of truth** for the well-known catalog
/// (UX-H11). Surfaces that consume it:
///
///  * The Canisters tab quick-pick grid ([`WellKnownList`] widget).
///  * The Call Builder dialog's well-known dropdown
///    ([`CanisterCallBuilderDialog`]).
///  * The Canister Client sheet's canister-id autocomplete
///    (`RawAutocomplete<WellKnownCanister>` in [`CanisterClientSheet`]).
///
/// Adding or editing a canister happens here exactly once; every surface
/// picks it up automatically. Do NOT fork this list per surface — that was
/// the bug UX-H11 fixed (three divergent catalogs: the widget's, the
/// dialog's hard-coded `Map<String,String>` list, and the now-removed
/// `CanisterRegistryEntry` service).
///
/// Fields:
///  * [label] — display name shown in cards / dropdowns / autocomplete.
///  * [canisterId] — the textual canister id (e.g. `ryjl3-…`).
///  * [description] — one-line summary, shown under the label.
///  * [icon] — icon for the quick-pick card + autocomplete option row.
///  * [category] — short badge text for grouping in the autocomplete
///     (`Tokens`, `Governance`, …).
///  * [method] — optional default method name; the quick-pick grid shows it
///     as a badge and the inline client pre-fills it when present.
class WellKnownCanister {
  const WellKnownCanister({
    required this.label,
    required this.canisterId,
    required this.description,
    required this.icon,
    required this.category,
    this.method,
  });

  final String label;
  final String canisterId;
  final String description;
  final IconData icon;
  final String category;
  final String? method;

  /// The canonical catalog. **Add new entries here.**
  ///
  /// Order is curated: system primitives first (registry / governance /
  /// ledger / cycles / management), then identity, then the SNS-1 DAO, then
  /// the community catalogs + explorers + search + monitoring surface that
  /// the issue (UX-H11) specifically called out as missing from the Call
  /// Builder (ICLighthouse, Cyql, Kinic, Canistergeek).
  static const List<WellKnownCanister> all = <WellKnownCanister>[
    WellKnownCanister(
      label: 'NNS Registry',
      canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
      method: 'get_value',
      description: 'Authoritative lookup for subnet + node records',
      icon: Icons.dns_rounded,
      category: 'Infrastructure',
    ),
    WellKnownCanister(
      label: 'NNS Governance',
      canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
      method: 'get_neuron_ids',
      description: 'Manage neurons and follow governance proposals',
      icon: Icons.how_to_vote_rounded,
      category: 'Governance',
    ),
    WellKnownCanister(
      label: 'NNS Ledger',
      canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
      method: 'account_balance_dfx',
      description: 'Check ICP balances directly on the ledger',
      icon: Icons.account_balance_wallet_rounded,
      category: 'Tokens',
    ),
    WellKnownCanister(
      label: 'Cycles Minting',
      canisterId: 'rkp4c-7iaaa-aaaaa-aaaca-cai',
      description: 'Convert ICP to cycles for canister topping up',
      icon: Icons.bolt_rounded,
      category: 'Infrastructure',
    ),
    WellKnownCanister(
      label: 'Management Canister',
      canisterId: 'aaaaa-aa',
      description: 'Pseudo-canister for canister lifecycle + status calls',
      icon: Icons.settings_rounded,
      category: 'Infrastructure',
    ),
    WellKnownCanister(
      label: 'Internet Identity',
      canisterId: 'rdmx6-jaaaa-aaaaa-aaadq-cai',
      description: 'Authentication and identity management',
      icon: Icons.fingerprint_rounded,
      category: 'Identity',
    ),
    WellKnownCanister(
      label: 'SNS-1 Governance',
      canisterId: 'qoctq-giaaa-aaaaa-aaadia-qai',
      description: 'SNS-1 DAO governance and token operations',
      icon: Icons.groups_rounded,
      category: 'Governance',
    ),
    WellKnownCanister(
      label: 'SNS-1 Ledger',
      canisterId: 'qaa6y-5yaaa-aaaaa-aaafa-cai',
      description: 'SNS-1 token transactions and balance queries',
      icon: Icons.account_balance_wallet_outlined,
      category: 'Tokens',
    ),
    WellKnownCanister(
      label: 'Canlista Registry',
      canisterId: 'k7gat-daaaa-aaaae-qaahq-cai',
      method: 'http_request',
      description: 'Community-maintained catalog of IC canisters',
      icon: Icons.list_alt_rounded,
      category: 'Catalog',
    ),
    WellKnownCanister(
      label: 'Cyql Projects',
      canisterId: 'n7ib3-4qaaa-aaaai-qagnq-cai',
      method: 'http_request',
      description: 'Curated feed of active Internet Computer dapps',
      icon: Icons.explore_rounded,
      category: 'Catalog',
    ),
    WellKnownCanister(
      label: 'ICLighthouse',
      canisterId: '637g5-siaaa-aaaaj-aasja-cai',
      method: 'http_request',
      description: 'Realtime explorer with subnet level insights',
      icon: Icons.lightbulb_rounded,
      category: 'Explorer',
    ),
    WellKnownCanister(
      label: 'Kinic Search',
      canisterId: '74iy7-xqaaa-aaaaf-qagra-cai',
      method: 'http_request',
      description: 'Native IC search engine for dapps and content',
      icon: Icons.search_rounded,
      category: 'Search',
    ),
    WellKnownCanister(
      label: 'Canistergeek',
      canisterId: 'cusyh-iyaaa-aaaah-qcpba-cai',
      method: 'http_request',
      description: 'Monitor cycles, memory and performance at a glance',
      icon: Icons.analytics_rounded,
      category: 'Monitoring',
    ),
  ];

  /// Case-insensitive search over [canisterId] prefix AND [label] substring,
  /// returning at most [limit] matches. Empty query → first [limit] entries
  /// (used by the autocomplete to seed the dropdown when the field is
  /// non-empty but untyped).
  ///
  /// The autocomplete in `CanisterClientSheet` calls this on every keystroke.
  static List<WellKnownCanister> search(String query, {int limit = 10}) {
    if (query.isEmpty) {
      return all.take(limit).toList();
    }
    final lowerQuery = query.toLowerCase();
    return all
        .where((c) =>
            c.canisterId.toLowerCase().startsWith(lowerQuery) ||
            c.label.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
  }
}
