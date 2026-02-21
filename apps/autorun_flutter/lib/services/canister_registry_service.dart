class CanisterRegistryEntry {
  const CanisterRegistryEntry({
    required this.canisterId,
    required this.name,
    required this.description,
    required this.category,
  });

  final String canisterId;
  final String name;
  final String description;
  final String category;

  static List<CanisterRegistryEntry> get all => _wellKnownCanisters;

  static List<CanisterRegistryEntry> search(String query, {int limit = 10}) {
    if (query.isEmpty) {
      return _wellKnownCanisters.take(limit).toList();
    }
    final lowerQuery = query.toLowerCase();
    return _wellKnownCanisters
        .where((c) =>
            c.canisterId.toLowerCase().startsWith(lowerQuery) ||
            c.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
  }
}

const _wellKnownCanisters = [
  CanisterRegistryEntry(
    canisterId: 'ryjl3-tyaaa-aaaaa-aaaba-cai',
    name: 'NNS Ledger',
    description: 'ICP token transactions and balance queries',
    category: 'Tokens',
  ),
  CanisterRegistryEntry(
    canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
    name: 'NNS Governance',
    description: 'Neuron management and voting on proposals',
    category: 'Governance',
  ),
  CanisterRegistryEntry(
    canisterId: 'rdmx6-jaaaa-aaaaa-aaadq-cai',
    name: 'Internet Identity',
    description: 'Authentication and identity management',
    category: 'Identity',
  ),
  CanisterRegistryEntry(
    canisterId: 'rkp4c-7iaaa-aaaaa-aaaca-cai',
    name: 'Cycles Minting',
    description: 'Convert ICP to cycles for canister topping up',
    category: 'Infrastructure',
  ),
  CanisterRegistryEntry(
    canisterId: 'rwlct-iiaaa-aaaaa-aaaoa-cai',
    name: 'Registry',
    description: 'Network-wide registry for system configurations',
    category: 'Infrastructure',
  ),
  CanisterRegistryEntry(
    canisterId: 'qoctq-giaaa-aaaaa-aaadia-qai',
    name: 'SNS-1 Governance',
    description: 'SNS-1 DAO governance and token operations',
    category: 'Governance',
  ),
  CanisterRegistryEntry(
    canisterId: 'qaa6y-5yaaa-aaaaa-aaafa-cai',
    name: 'SNS-1 Ledger',
    description: 'SNS-1 token transactions and balance queries',
    category: 'Tokens',
  ),
  CanisterRegistryEntry(
    canisterId: 'k7gat-daaaa-aaaae-qaahq-cai',
    name: 'Canista',
    description: 'Social platform on Internet Computer',
    category: 'Social',
  ),
];
