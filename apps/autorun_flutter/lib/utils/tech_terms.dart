enum TechTerm {
  canister(
    term: 'Canister',
    shortExplanation: 'Smart contract on ICP',
    fullExplanation:
        'A canister is a smart contract on the Internet Computer - like a serverless app that runs on-chain. It contains both code (WebAssembly) and state (data).',
  ),
  principal(
    term: 'Principal',
    shortExplanation: 'Your unique account ID',
    fullExplanation:
        'A principal is your unique account identifier on the Internet Computer. It\'s derived from your public key and looks like: 2vxsx-fae. Principals identify who is making a call.',
  ),
  candid(
    term: 'Candid',
    shortExplanation: 'Type system for canister communication',
    fullExplanation:
        'Candid is a type system that describes how to communicate with canisters. It\'s like a schema that defines what methods a canister has and what data types they accept/return.',
  ),
  keypair(
    term: 'Keypair',
    shortExplanation: 'Public/private key pair for signing',
    fullExplanation:
        'A keypair is a public/private key pair used to sign transactions and authenticate. Your private key signs messages, while your public key verifies them. Never share your private key.',
  ),
  query(
    term: 'Query',
    shortExplanation: 'Read-only call (fast, free)',
    fullExplanation:
        'A query is a read-only operation that doesn\'t modify state. It\'s fast (milliseconds) and free because it only reads from a single node, not the entire network.',
  ),
  update(
    term: 'Update',
    shortExplanation: 'State-modifying call (slower, costs cycles)',
    fullExplanation:
        'An update is an operation that modifies state on the canister. It\'s slower (seconds) because it requires consensus across the network and costs cycles.',
  ),
  cycles(
    term: 'Cycles',
    shortExplanation: 'Computational resources (like gas)',
    fullExplanation:
        'Cycles are computational resources on the Internet Computer, similar to "gas" on other blockchains. They pay for computation, storage, and network calls. Canisters burn cycles to operate.',
  ),
  replica(
    term: 'Replica',
    shortExplanation: 'Node in the ICP network',
    fullExplanation:
        'A replica is a node in the Internet Computer network that executes canisters and participates in consensus. Multiple replicas ensure decentralization and security.',
  ),
  signingKey(
    term: 'Signing Key',
    shortExplanation: 'The keypair used for transactions',
    fullExplanation:
        'The signing key is the keypair currently being used to sign transactions and authenticate. You can have multiple keypairs but only one active signing key at a time.',
  ),
  icPrincipal(
    term: 'IC Principal',
    shortExplanation: 'Principal derived from a key',
    fullExplanation:
        'An IC Principal is the identifier derived from a public key on the Internet Computer. Each keypair has a corresponding principal that identifies it on the network.',
  );

  const TechTerm({
    required this.term,
    required this.shortExplanation,
    required this.fullExplanation,
  });

  final String term;
  final String shortExplanation;
  final String fullExplanation;

  static TechTerm? findByTerm(String term) {
    for (final t in values) {
      if (t.term.toLowerCase() == term.toLowerCase()) {
        return t;
      }
    }
    return null;
  }
}
