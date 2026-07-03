import 'package:shared_preferences/shared_preferences.dart';

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
/// The local-replica connection values ([backendCanisterId], [host]) are
/// defaults only — they are NOT stable across a fresh `dfx start --clean`, so
/// the runner UI lets users override them via [DappRuntimeConfig].
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
    this.paths = const <DappPath>[
      DappPath.backendDirect,
      DappPath.frontendBrowser,
    ],
  });

  /// Stable identifier used to key per-dapp persisted overrides.
  final String id;
  final String title;
  final String description;
  final String emoji;

  /// Default backend canister id for the local replica.
  final String backendCanisterId;

  /// Default replica host.
  final String host;

  /// Hosted frontend URL (Path A: opened in the system browser).
  final String frontendUrl;

  /// Flutter asset path to the bundled TS app (Path B source).
  final String bundleAssetPath;

  final List<DappPath> paths;

  bool get hasBackendDirect => paths.contains(DappPath.backendDirect);
  bool get hasFrontendBrowser => paths.contains(DappPath.frontendBrowser);
}

// =============================================================================
// Single source of truth for the local-replica connection defaults.
// =============================================================================
// These match a replica deployed from examples/icp_poll_dapp. A fresh
// `dfx start --clean` + `dfx deploy` regenerates different ids, which is
// exactly why the runner exposes editable Connection fields. Reference these
// constants symbolically rather than re-spelling the literals.
const String kLocalPollBackendCanisterId = 'uxrrr-q7777-77774-qaaaq-cai';
const String kLocalPollHost = 'http://127.0.0.1:4943';
const String kLocalPollFrontendUrl =
    'http://localhost:4943?canisterId=u6s2n-gx777-77774-qaaba-cai';

/// Every example dapp shipped with the app. Add new entries here (and only
/// here) — the catalog screen and runner both read from this list.
const List<DappDescriptor> exampleDapps = <DappDescriptor>[
  DappDescriptor(
    id: 'icp_poll',
    title: 'On-chain Polls',
    emoji: '🗳️',
    description:
        'Create polls and vote live on the Internet Computer. Authenticated '
        'effects sign as your active profile — the bundle never holds keys.',
    backendCanisterId: kLocalPollBackendCanisterId,
    host: kLocalPollHost,
    frontendUrl: kLocalPollFrontendUrl,
    bundleAssetPath: 'lib/examples/06_icp_poll.js',
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
