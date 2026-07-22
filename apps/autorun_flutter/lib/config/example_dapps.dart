import 'package:shared_preferences/shared_preferences.dart';

/// Where a shipped example's default canister LIVES. Drives the catalog badge
/// + the runner's honest empty-state so a user never opens a silently-dead tab.
enum DappEnvironment {
  /// Points at a real PUBLIC mainnet canister — works for every user out of the
  /// box, no setup. (HUMAN_EXPECTATIONS §3: talk to a REAL canister.)
  mainnet,

  /// Needs a LOCAL replica the user starts themselves (`dfx start --clean` +
  /// `dfx deploy` from `examples/icp_poll_dapp`). A developer/teaching example;
  /// the runner shows the exact commands to bring it up.
  localReplica,
}

/// Access paths a dapp exposes. Each card in the Dapps catalog advertises the
/// paths it supports so the runner knows which affordances to show.
enum DappPath {
  /// Path B: the app talks to the backend canister directly from this app,
  /// rendered by [ScriptAppHost] using the bundled TS app.
  backendDirect,

  /// Path A: open the dapp's hosted frontend in the system browser.
  frontendBrowser,
}

/// Immutable descriptor for a shipped example dapp.
///
/// The connection values ([backendCanisterId], [host]) are defaults only.
/// For [DappEnvironment.localReplica] examples they are NOT stable across a
/// fresh `dfx start --clean`, so the runner UI lets users override them via
/// [DappRuntimeConfig]; for [DappEnvironment.mainnet] examples they are the
/// real public values and need no override.
class DappDescriptor {
  const DappDescriptor({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.backendCanisterId,
    required this.host,
    required this.frontendUrl,
    required this.bundleAssetPath,
    this.environment = DappEnvironment.mainnet,
    this.paths = const <DappPath>[
      DappPath.backendDirect,
      DappPath.frontendBrowser,
    ],
    this.keylessHint,
  });

  /// Stable identifier used to key per-dapp persisted overrides.
  final String id;
  final String title;
  final String description;
  final String emoji;

  /// Where the default canister lives — drives the catalog badge + the
  /// runner's empty-state copy.
  final DappEnvironment environment;

  /// Default backend canister id (mainnet public id, or a local-replica id).
  final String backendCanisterId;

  /// Default canister host (mainnet gateway, or a local-replica host).
  final String host;

  /// Hosted frontend URL (Path A: opened in the system browser).
  final String frontendUrl;

  /// Flutter asset path to the bundled TS app (Path B source).
  final String bundleAssetPath;

  final List<DappPath> paths;

  /// Optional dapp-specific hint shown to keyless (no-profile) users in the
  /// runner (W6-1 Bug 3). When null the runner uses a generic dapp-agnostic
  /// hint. Set this only when a dapp has a more specific "what signing
  /// unlocks" message (e.g. a poll dapp: "vote"); otherwise the generic copy
  /// avoids polluting unrelated dapps (e.g. the ICP Ledger) with misleading
  /// language.
  final String? keylessHint;

  bool get hasBackendDirect => paths.contains(DappPath.backendDirect);
  bool get hasFrontendBrowser => paths.contains(DappPath.frontendBrowser);
  bool get isMainnet => environment == DappEnvironment.mainnet;
  bool get isLocalReplica => environment == DappEnvironment.localReplica;
}

// =============================================================================
// Single source of truth for the connection defaults shipped with each example.
// =============================================================================
// MAINNET examples reference real public canisters every user can reach — no
// setup. The ICP ledger id is the well-known mainnet ICP ledger (verified live:
// `symbol() → "ICP"`, `name() → "Internet Computer"`, `decimals() → 8`).
const String kMainnetIcGateway = 'https://ic0.app';
const String kMainnetIcpLedgerCanisterId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';

// NNS Governance canister — verified live 2026-07-21 via dfx
// (`list_proposals` returns proposal_info; same canister ALPHA-Vote /
// CO.DELTA in third_party/ automate in Rust). Public + read-only.
const String kMainnetNnsGovernanceCanisterId = 'rrkah-fqaaa-aaaaa-aaaaq-cai';

// OpenChat SNS Governance canister — verified live 2026-07-21 via dfx
// (`list_proposals` returns proposals; status must be INFERRED from
// timestamp fields; topic is an opt variant). The default DAO for the SNS
// Proposals demo; the user can paste any other SNS governance id in-app.
const String kMainnetOpenChatSnsGovernanceCanisterId = '2jvtu-yqaaa-aaaaq-aaama-cai';

// ALPHA-Vote known public neuron ids (canonical mainnet, from
// third_party/ALPHA-Vote/README.md). Used as the recommendation surface in
// the Neuron Voting dapp (the bundle shows what these 3 neurons voted on
// each open proposal) + the D-QUORUM upstream diligent voter surfaced as an
// extra Follow affordance. Verified live 2026-07-21 via dfx against NNS
// Governance rrkah-fqaaa-aaaaa-aaaaq-cai (a real authenticated manage_neuron
// with a non-owned neuron returns the structured "Neuron not found" Error,
// proving the auth round-trip — see docs/specs/2026-07-21-alpha-vote-dapp.md
// §10.2 for the transcript).
const String kAlphaVoteNeuronId   = '2947465672511369';
const String kOmegaVoteNeuronId   = '18363645821499695760';
const String kOmegaRejectNeuronId = '18422777432977120264';
const String kDQuorumNeuronId     = '4713806069430754115';

// LOCAL-REPLICA example: these match a replica deployed from
// examples/icp_poll_dapp. A fresh `dfx start --clean` + `dfx deploy` regenerates
// different ids, which is exactly why the runner exposes editable Connection
// fields. Reference these constants symbolically rather than re-spelling them.
const String kLocalPollBackendCanisterId = 'uxrrr-q7777-77774-qaaaq-cai';
const String kLocalPollHost = 'http://127.0.0.1:4943';
const String kLocalPollFrontendUrl =
    'http://localhost:4943?canisterId=u6s2n-gx777-77774-qaaba-cai';

/// Every example dapp shipped with the app. Add new entries here (and only
/// here) — the catalog screen and runner both read from this list.
///
/// Order matters for UX: the always-working [DappEnvironment.mainnet] example
/// is listed FIRST so a brand-new user lands on a tab that works out of the box,
/// followed by the [DappEnvironment.localReplica] developer example.
const List<DappDescriptor> exampleDapps = <DappDescriptor>[
  // ── Always works: real mainnet canister, read-only ──────────────────────
  DappDescriptor(
    id: 'icp_ledger',
    title: 'ICP Ledger',
    emoji: '🪙',
    description: 'Read the ICP token metadata (symbol, name, decimals) '
        'straight from the live Internet Computer ledger on mainnet. '
        'Works out of the box — no setup, no signing, read-only.',
    backendCanisterId: kMainnetIcpLedgerCanisterId,
    host: kMainnetIcGateway,
    frontendUrl: '',
    bundleAssetPath: 'lib/examples/07_icp_ledger.js',
    environment: DappEnvironment.mainnet,
    // The ledger is a backend-only canister (no hosted frontend UI).
    paths: <DappPath>[DappPath.backendDirect],
  ),

  // ── Always works: live NNS governance proposals (read-only) ─────────────
  DappDescriptor(
    id: 'nns_proposals',
    title: 'NNS Proposals',
    emoji: '🗳️',
    description: 'Browse LIVE Internet Computer governance proposals — open, '
        'adopted, rejected, or executed. Filter by status and topic, watch '
        'the tally, see real deadlines. Reads from the NNS Governance '
        'canister — no setup required.',
    backendCanisterId: kMainnetNnsGovernanceCanisterId,
    host: kMainnetIcGateway,
    frontendUrl: 'https://nns.ic0.app/proposals',
    bundleAssetPath: 'lib/examples/08_nns_proposals.js',
    environment: DappEnvironment.mainnet,
    keylessHint: 'Browsing proposals is read-only. Signing is only needed '
        'to vote (which this demo does not do).',
  ),

  // ── Always works: live SNS DAO governance proposals (read-only) ─────────
  DappDescriptor(
    id: 'sns_proposals',
    title: 'SNS DAO Proposals',
    emoji: '🏛️',
    description: 'Browse LIVE proposals for any SNS DAO on the Internet '
        'Computer. Defaults to OpenChat SNS — paste any SNS governance '
        'canister id to switch. Filter by status, watch the tally, see '
        'deadlines countdown. Demonstrates per-DAO branded themes.',
    backendCanisterId: kMainnetOpenChatSnsGovernanceCanisterId,
    host: kMainnetIcGateway,
    frontendUrl: 'https://dashboard.internetcomputer.org/sns',
    bundleAssetPath: 'lib/examples/09_sns_proposals.js',
    environment: DappEnvironment.mainnet,
    keylessHint: 'Browsing proposals is read-only. Signing is only needed '
        'to vote (which this demo does not do).',
  ),

  // ── Authenticated: live NNS neuron voting (RegisterVote + Follow) ───────
  DappDescriptor(
    id: 'alpha_vote',
    title: 'Neuron Voting',
    emoji: '⚡',
    description: 'Cast authenticated NNS votes from inside icp-cc. Browse '
        'open proposals, see what the ALPHA-Vote public neurons recommend, '
        'then vote Yes/No or set up recurring Following — signed with your '
        'active profile\'s keypair. Requires a staked NNS neuron.',
    backendCanisterId: kMainnetNnsGovernanceCanisterId,
    host: kMainnetIcGateway,
    frontendUrl: '',
    bundleAssetPath: 'lib/examples/10_alpha_vote.js',
    environment: DappEnvironment.mainnet,
    paths: <DappPath>[DappPath.backendDirect],
    keylessHint: 'Browsing proposals works without a profile. Signing '
        'in unlocks neuron discovery and one-tap voting.',
  ),

  // ── Developer example: needs a local replica ────────────────────────────
  DappDescriptor(
    id: 'icp_poll',
    title: 'On-chain Polls',
    emoji: '🗳️',
    description: 'Create polls and vote live on the Internet Computer. A '
        'developer example — start a local replica and paste the backend '
        'canister id. Authenticated effects sign as your active profile.',
    backendCanisterId: kLocalPollBackendCanisterId,
    host: kLocalPollHost,
    frontendUrl: kLocalPollFrontendUrl,
    bundleAssetPath: 'lib/examples/06_icp_poll.js',
    environment: DappEnvironment.localReplica,
  ),
];

/// Effective, persisted connection values for one dapp: stored override ?? the
/// descriptor default. Lets a user point the runner at their own replica /
/// canister without editing code.
class DappRuntimeConfig {
  const DappRuntimeConfig({
    required this.backendCanisterId,
    required this.host,
  });

  final String backendCanisterId;
  final String host;

  static String _backendKey(String id) => 'dapp.$id.backend_id';
  static String _hostKey(String id) => 'dapp.$id.host';

  /// Returns the effective values: a non-empty stored override wins, otherwise
  /// the descriptor default.
  static Future<DappRuntimeConfig> load(DappDescriptor descriptor) async {
    final prefs = await SharedPreferences.getInstance();
    final storedBackend = prefs.getString(_backendKey(descriptor.id));
    final storedHost = prefs.getString(_hostKey(descriptor.id));
    return DappRuntimeConfig(
      backendCanisterId: (storedBackend == null || storedBackend.isEmpty)
          ? descriptor.backendCanisterId
          : storedBackend,
      host: (storedHost == null || storedHost.isEmpty)
          ? descriptor.host
          : storedHost,
    );
  }

  /// Persists overrides for the given dapp id. Pass `null`/omit to leave a
  /// field unchanged; pass an empty string to clear it back to the default on
  /// the next [load].
  static Future<void> save(
    String id, {
    String? backendCanisterId,
    String? host,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (backendCanisterId != null) {
      await prefs.setString(_backendKey(id), backendCanisterId);
    }
    if (host != null) {
      await prefs.setString(_hostKey(id), host);
    }
  }

  /// Removes all overrides for the given dapp id (next [load] yields defaults).
  static Future<void> clear(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backendKey(id));
    await prefs.remove(_hostKey(id));
  }
}

/// Persists the user's "Trust this dapp" grant across app restarts. Keyed by
/// [DappDescriptor.id] (a stable identifier). When trusted, the runner's
/// permission gate allows ALL of that dapp's canister calls (any method, mode,
/// or auth) without further prompts — so a brand-new user opening the shipped
/// Poll dapp sees at most ONE trust prompt, then never again.
///
/// Only shipped example dapps opt into the trust model (the runner passes
/// `dappTrustId: descriptor.id` to [ScriptAppHost]); user/marketplace scripts
/// leave `dappTrustId` null and keep the strict per-method gate unchanged.
///
/// Storage reuses the same [SharedPreferences] instance as [DappRuntimeConfig]
/// — no new persistence layer.
class DappTrustStore {
  const DappTrustStore();

  static String _trustKey(String id) => 'dapp.$id.trusted';

  /// True iff the user has previously granted trust to this dapp id.
  static Future<bool> isTrusted(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_trustKey(id)) ?? false;
  }

  /// Records the trust grant persistently. Idempotent.
  static Future<void> setTrusted(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trustKey(id), true);
  }

  /// Removes the trust grant (next [isTrusted] returns false). Used by tests
  /// to reset state; no UI affordance wires this today (parity with the
  /// per-method allow-list, which also has no in-app revocation).
  static Future<void> clear(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_trustKey(id));
  }
}
