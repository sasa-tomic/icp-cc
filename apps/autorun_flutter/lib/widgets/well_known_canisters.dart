import 'dart:async';

import 'package:flutter/material.dart';

class WellKnownCanister {
  const WellKnownCanister({
    required this.label,
    required this.canisterId,
    required this.description,
    required this.icon,
    this.method,
  });

  final String label;
  final String canisterId;
  final String description;
  final IconData icon;
  final String? method;
}

class WellKnownList extends StatelessWidget {
  const WellKnownList({super.key, required this.onSelect, this.onBookmark});
  final void Function(String canisterId, String? method) onSelect;
  final Future<void> Function(WellKnownCanister entry)? onBookmark;

  static const List<WellKnownCanister> _items = <WellKnownCanister>[
    WellKnownCanister(
      label: 'NNS Registry',
      canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
      method: 'get_value',
      description: 'Authoritative lookup for subnet + node records',
      icon: Icons.dns_rounded,
    ),
    WellKnownCanister(
      label: 'NNS Governance',
      canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
      method: 'get_neuron_ids',
      description: 'Manage neurons and follow governance proposals',
      icon: Icons.how_to_vote_rounded,
    ),
    WellKnownCanister(
      label: 'NNS Ledger',
      canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
      method: 'account_balance_dfx',
      description: 'Check ICP balances directly on the ledger',
      icon: Icons.account_balance_wallet_rounded,
    ),
    WellKnownCanister(
      label: 'Canlista Registry',
      canisterId: 'k7gat-daaaa-aaaae-qaahq-cai',
      method: 'http_request',
      description: 'Community-maintained catalog of IC canisters',
      icon: Icons.list_alt_rounded,
    ),
    WellKnownCanister(
      label: 'Cyql Projects',
      canisterId: 'n7ib3-4qaaa-aaaai-qagnq-cai',
      method: 'http_request',
      description: 'Curated feed of active Internet Computer dapps',
      icon: Icons.explore_rounded,
    ),
    WellKnownCanister(
      label: 'ICLighthouse',
      canisterId: '637g5-siaaa-aaaaj-aasja-cai',
      method: 'http_request',
      description: 'Realtime explorer with subnet level insights',
      icon: Icons.lightbulb_rounded,
    ),
    WellKnownCanister(
      label: 'Kinic Search',
      canisterId: '74iy7-xqaaa-aaaaf-qagra-cai',
      method: 'http_request',
      description: 'Native IC search engine for dapps and content',
      icon: Icons.search_rounded,
    ),
    WellKnownCanister(
      label: 'Canistergeek',
      canisterId: 'cusyh-iyaaa-aaaah-qcpba-cai',
      method: 'http_request',
      description: 'Monitor cycles, memory and performance at a glance',
      icon: Icons.analytics_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width > 880 ? 3 : 2);
    final childAspectRatio = width > 880 ? 3.5 : (width < 420 ? 3.0 : 2.6);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (BuildContext context, int index) {
        final entry = _items[index];
        return _WellKnownCard(
          entry: entry,
          onTap: () => onSelect(entry.canisterId, entry.method),
          onBookmark:
              onBookmark == null ? null : () => unawaited(onBookmark!(entry)),
        );
      },
    );
  }
}

class _WellKnownCard extends StatelessWidget {
  const _WellKnownCard(
      {required this.entry, required this.onTap, this.onBookmark});

  final WellKnownCanister entry;
  final VoidCallback onTap;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.icon,
                        color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onBookmark != null)
                    IconButton(
                      tooltip: 'Bookmark',
                      icon: Icon(Icons.bookmark_add_outlined,
                          color: theme.colorScheme.primary),
                      onPressed: onBookmark,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if ((entry.method ?? '').isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.method!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
