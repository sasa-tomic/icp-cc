enum TechTerm {
  canister(
    term: 'Canister',
    plainLabel: 'Service',
    shortExplanation: 'Smart contract on ICP',
    plainExplanation: 'An on-chain app that runs code and stores data.',
    fullExplanation:
        'A canister is a smart contract on the Internet Computer - like a serverless app that runs on-chain. It contains both code (WebAssembly) and state (data).',
  ),
  principal(
    term: 'Principal',
    plainLabel: 'Account ID',
    shortExplanation: 'Your unique account ID',
    plainExplanation: 'Your unique identifier on the network.',
    fullExplanation:
        'A principal is your unique account identifier on the Internet Computer. It\'s derived from your public key and looks like: 2vxsx-fae. Principals identify who is making a call.',
  ),
  candid(
    term: 'Candid',
    plainLabel: 'Interface',
    shortExplanation: 'Type system for canister communication',
    plainExplanation: 'Defines what functions a service has.',
    fullExplanation:
        'Candid is a type system that describes how to communicate with canisters. It\'s like a schema that defines what methods a canister has and what data types they accept/return.',
  ),
  keypair(
    term: 'Keypair',
    plainLabel: 'Keys',
    shortExplanation: 'Public/private key pair for signing',
    plainExplanation: 'Your cryptographic key pair for authentication.',
    fullExplanation:
        'A keypair is a public/private key pair used to sign transactions and authenticate. Your private key signs messages, while your public key verifies them. Never share your private key.',
  ),
  query(
    term: 'Query',
    plainLabel: 'Read',
    shortExplanation: 'Read-only call (fast, free)',
    plainExplanation: 'Reads data without making changes (fast and free).',
    fullExplanation:
        'A query is a read-only operation that doesn\'t modify state. It\'s fast (milliseconds) and free because it only reads from a single node, not the entire network.',
  ),
  update(
    term: 'Update',
    plainLabel: 'Write',
    shortExplanation: 'State-modifying call (slower, costs cycles)',
    plainExplanation: 'Writes or changes data (takes a few seconds).',
    fullExplanation:
        'An update is an operation that modifies state on the canister. It\'s slower (seconds) because it requires consensus across the network and costs cycles.',
  ),
  cycles(
    term: 'Cycles',
    plainLabel: 'Credits',
    shortExplanation: 'Computational resources (like gas)',
    plainExplanation: 'Credits that pay for operations (like gas).',
    fullExplanation:
        'Cycles are computational resources on the Internet Computer, similar to "gas" on other blockchains. They pay for computation, storage, and network calls. Canisters burn cycles to operate.',
  ),
  replica(
    term: 'Replica',
    plainLabel: 'Node',
    shortExplanation: 'Node in the ICP network',
    plainExplanation: 'A computer running the network.',
    fullExplanation:
        'A replica is a node in the Internet Computer network that executes canisters and participates in consensus. Multiple replicas ensure decentralization and security.',
  ),
  signingKey(
    term: 'Signing Key',
    plainLabel: 'Active Key',
    shortExplanation: 'The keypair used for transactions',
    plainExplanation: 'The key currently used for signing.',
    fullExplanation:
        'The signing key is the keypair currently being used to sign transactions and authenticate. You can have multiple keypairs but only one active signing key at a time.',
  ),
  icPrincipal(
    term: 'IC Principal',
    plainLabel: 'Network ID',
    shortExplanation: 'Principal derived from a key',
    plainExplanation: 'Your identifier derived from your keys.',
    fullExplanation:
        'An IC Principal is the identifier derived from a public key on the Internet Computer. Each keypair has a corresponding principal that identifies it on the network.',
  ),
  passkey(
    term: 'Passkey',
    plainLabel: 'Biometric Login',
    shortExplanation: 'Secure login with fingerprint or Face ID',
    plainExplanation: 'Use your face or fingerprint to log in securely.',
    fullExplanation:
        'A passkey is a secure authentication method that uses biometrics (fingerprint, Face ID) or a hardware key instead of a password. Passkeys are phishing-resistant and stored securely on your device.',
  );

  const TechTerm({
    required this.term,
    required this.plainLabel,
    required this.shortExplanation,
    required this.plainExplanation,
    required this.fullExplanation,
  });

  final String term;
  final String plainLabel;
  final String shortExplanation;
  final String plainExplanation;
  final String fullExplanation;

  static TechTerm? findByTerm(String term) {
    for (final t in values) {
      if (t.term.toLowerCase() == term.toLowerCase()) {
        return t;
      }
    }
    return null;
  }

  static TechTerm? findByPlainLabel(String label) {
    for (final t in values) {
      if (t.plainLabel.toLowerCase() == label.toLowerCase()) {
        return t;
      }
    }
    return null;
  }
}
