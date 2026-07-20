// ignore_for_file: lines_longer_than_80_chars

/// The coverage contract for the unified e2e harness.
///
/// Every supported user flow is listed ONCE here as const data. This catalog
/// is the single source of truth for "what does the app do, and is it covered".
/// A spec without a registered `run` (see [FlowRegistry]) is surfaced as a
/// coverage gap by [FlowCatalog.coverageReport].
///
/// Surfaces (per human steering 2026-07-15): "TUI" = Flutter Linux desktop
/// (native); "Web UI" = Flutter Web. There is no terminal UI.
///
/// Flow *implementations* are registered at runtime via [FlowRegistry], so this
/// file stays pure data (const) and the coverage matrix is auditable in place.
library;

import 'package:flutter_test/flutter_test.dart';

import 'e2e_driver.dart';

/// Which surface a flow is exercisable on.
enum Surface { desktop, web }

/// What the flow needs from the OS Secret Service (a desktop concern: on Linux
/// `flutter_secure_storage` → libsecret needs a running keyring).
enum Keyring {
  /// No secure-storage access (browse/search/settings/…).
  none,

  /// Creates or reads keypairs → needs a Secret Service on desktop (the mock
  /// keyring in CI, gnome-keyring on a real desktop).
  mockSecretService,

  /// This flow IS the keyring-down detection (the WU-S2 actionable panel).
  detectsFailure,
}

/// One row in the coverage contract.
class FlowSpec {
  const FlowSpec({
    required this.id,
    required this.name,
    required this.surfaces,
    this.keyring = Keyring.none,
    this.tags = const <String>{},
    this.entry,
    this.broken = false,
    this.brokenNote,
  });

  /// Dotted id, e.g. `first_run.create_profile`. Stable — never rename.
  final String id;

  /// Human label for reports / failure messages.
  final String name;

  /// Where this flow runs.
  final Set<Surface> surfaces;

  final Keyring keyring;

  /// Subset tags for fast dev loops (`smoke`, `marketplace`, `onboarding`…).
  final Set<String> tags;

  /// Starting screen/widget (informational).
  final String? entry;

  /// True when the flow is known to throw / dead-end today (see knownIssues).
  final bool broken;
  final String? brokenNote;

  bool get runsOnDesktop => surfaces.contains(Surface.desktop);
  bool get runsOnWeb => surfaces.contains(Surface.web);
}

/// A flow implementation. Bound to a [FlowSpec.id] via [FlowRegistry].
typedef FlowRun = Future<void> Function(WidgetTester tester, E2EDriver driver);

/// Runtime registry of implemented flows. A spec is "covered" when a `run` is
/// registered for its id. Phase 1 wires smoke flows; Phase 2 migrates the rest.
class FlowRegistry {
  final Map<String, FlowRun> _runs = <String, FlowRun>{};

  void register(String id, FlowRun run) {
    if (!FlowCatalog.allIds.contains(id)) {
      throw StateError(
          'FlowRegistry: unknown flow id "$id". Add it to FlowCatalog first.');
    }
    _runs[id] = run;
  }

  FlowRun? runFor(String id) => _runs[id];
  bool isImplemented(String id) => _runs.containsKey(id);
  int get implementedCount => _runs.length;
}

/// A discovered defect (the Phase-0 seed list + anything surfaced later). Each
/// drives a RED test → fix → GREEN in Phase 3.
class KnownIssue {
  const KnownIssue({
    required this.id,
    required this.flowId,
    required this.severity,
    required this.summary,
    this.evidence,
  });
  final String id; // F1..F8…
  final String flowId; // the FlowSpec.id it belongs to
  final IssueSeverity severity;
  final String summary;
  final String? evidence;
}

enum IssueSeverity { blocker, major, minor, doc }

/// The full, auditable coverage contract.
abstract final class FlowCatalog {
  static const Set<Surface> _d = <Surface>{Surface.desktop};
  static const Set<Surface> _w = <Surface>{Surface.web};
  static const Set<Surface> _b = <Surface>{Surface.desktop, Surface.web};

  // ── A. First-run / setup wizard ──────────────────────────────────────────
  static const firstRun = <FlowSpec>[
    FlowSpec(id: 'first_run.create_profile', name: 'Create profile (no username)', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'smoke', 'onboarding'}, entry: 'unified_setup_wizard.dart'),
    FlowSpec(id: 'first_run.create_profile_with_account', name: 'Create profile + register username', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'onboarding'}, entry: 'unified_setup_wizard.dart'),
    FlowSpec(id: 'first_run.dismiss_wizard', name: 'Dismiss wizard (browse as guest)', surfaces: _b, tags: {'onboarding'}, entry: 'unified_setup_wizard.dart'),
    FlowSpec(id: 'first_run.keyring_unavailable', name: 'Secure-storage blocking panel (keyring-down)', surfaces: _d, keyring: Keyring.detectsFailure, tags: {'onboarding', 'linux'}, entry: 'secure_storage_readiness.dart'),
    FlowSpec(id: 'first_run.reopen_wizard_chip', name: 'Re-open wizard via persistent chip', surfaces: _b, tags: {'onboarding'}, entry: 'profile_setup_chip.dart'),
  ];

  // ── B. Profile management ────────────────────────────────────────────────
  static const profile = <FlowSpec>[
    FlowSpec(id: 'profile.open_menu', name: 'Open profile menu', surfaces: _b, tags: {'smoke'}, entry: 'profile_menu.dart'),
    FlowSpec(id: 'profile.create_via_menu_dialog', name: 'Create profile via menu dialog', surfaces: _b, keyring: Keyring.mockSecretService, entry: 'profile_menu.dart'),
    FlowSpec(id: 'profile.switch_inline', name: 'Switch profile inline', surfaces: _b, entry: 'profile_menu.dart'),
    FlowSpec(id: 'profile.switch_via_manage_sheet', name: 'Switch profile via manage sheet', surfaces: _b, entry: 'profile_menu.dart'),
    FlowSpec(id: 'profile.open_account_profile', name: 'Open account profile screen', surfaces: _b, entry: 'profile_menu.dart'),
  ];

  // ── C. Keypair management ────────────────────────────────────────────────
  static const keypair = <FlowSpec>[
    FlowSpec(id: 'keypair.generate_local', name: 'Generate keypair (local profile)', surfaces: _b, keyring: Keyring.mockSecretService, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'keypair.generate_registered', name: 'Add key (registered account)', surfaces: _b, keyring: Keyring.mockSecretService, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'keypair.set_signing', name: 'Set signing key', surfaces: _b, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'keypair.edit_label', name: 'Edit key label', surfaces: _b, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'keypair.delete_registered', name: 'Delete key', surfaces: _b, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'keypair.export', name: 'Export keys (encrypted)', surfaces: _b, entry: 'export_keys_dialog.dart'),
    FlowSpec(id: 'keypair.import', name: 'Import keys', surfaces: _b, keyring: Keyring.mockSecretService, entry: 'import_keys_dialog.dart'),
  ];

  // ── D. Account registration & editing ────────────────────────────────────
  static const account = <FlowSpec>[
    FlowSpec(id: 'account.register_from_local', name: 'Register account from local profile', surfaces: _b, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'account.register_from_publish', name: 'Register account when publishing', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'account.edit_profile', name: 'Edit account profile', surfaces: _b, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'account.refresh', name: 'Refresh account', surfaces: _b, entry: 'account_profile_screen.dart'),
  ];

  // ── E. Scripts / marketplace ─────────────────────────────────────────────
  static const scripts = <FlowSpec>[
    FlowSpec(id: 'scripts.browse_marketplace', name: 'Browse marketplace', surfaces: _b, tags: {'smoke', 'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.search', name: 'Search scripts', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.filter_category', name: 'Filter by category', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.filter_sort', name: 'Sort scripts', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.filter_downloaded_only', name: 'Filter downloaded only', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.filter_favorites_only', name: 'Filter favorites only', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.view_details', name: 'View script details', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.download_free', name: 'Download free script', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.download_paid', name: 'Download paid script', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.buy', name: 'Buy paid script (provider-agnostic)', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.share', name: 'Share script', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.toggle_favorite', name: 'Toggle favorite', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.create', name: 'Create script', surfaces: _b, tags: {'smoke'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.run', name: 'Run script (QuickJS)', surfaces: _d, tags: {'desktop-only'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.edit', name: 'Edit script', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.duplicate', name: 'Duplicate script', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.delete', name: 'Delete script', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.publish', name: 'Publish script', surfaces: _b, tags: {'marketplace'}, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.copy_source', name: 'Copy script source', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.view_in_marketplace', name: 'View script in marketplace', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.load_more', name: 'Load more (pagination)', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.refresh_pull', name: 'Pull-to-refresh scripts', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.empty_library', name: 'Empty library state', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.search_no_results', name: 'Search no-results state', surfaces: _b, entry: 'scripts_screen.dart'),
    FlowSpec(id: 'scripts.marketplace_load_error', name: 'Marketplace load-error panel', surfaces: _b, entry: 'scripts_screen.dart'),
  ];

  // ── F. Download history ──────────────────────────────────────────────────
  static const downloads = <FlowSpec>[
    FlowSpec(id: 'download_history.view', name: 'View download history', surfaces: _b, entry: 'download_history_screen.dart'),
    FlowSpec(id: 'download_history.run', name: 'Run from history', surfaces: _d, entry: 'download_history_screen.dart'),
    FlowSpec(id: 'download_history.remove', name: 'Remove from history', surfaces: _b, entry: 'download_history_screen.dart'),
    FlowSpec(id: 'download_history.clear', name: 'Clear history', surfaces: _b, entry: 'download_history_screen.dart'),
  ];

  // ── G. Canisters (Bookmarks tab) ─────────────────────────────────────────
  static const canisters = <FlowSpec>[
    FlowSpec(id: 'canisters.open_inline_client', name: 'Open inline canister client', surfaces: _d, tags: {'desktop-only'}, entry: 'bookmarks_screen.dart'),
    FlowSpec(id: 'canisters.bookmark_well_known', name: 'Bookmark a well-known canister', surfaces: _b, entry: 'bookmarks_screen.dart'),
    FlowSpec(id: 'canisters.save_composer', name: 'Save via bookmark composer', surfaces: _b, entry: 'bookmarks_screen.dart'),
    FlowSpec(id: 'canisters.tap_bookmark', name: 'Tap a saved bookmark', surfaces: _d, tags: {'desktop-only'}, entry: 'bookmarks_screen.dart'),
    FlowSpec(id: 'canisters.recent_calls', name: 'Open recent call', surfaces: _d, tags: {'desktop-only'}, entry: 'bookmarks_screen.dart'),
    FlowSpec(id: 'canisters.refresh_pull', name: 'Pull-to-refresh canisters', surfaces: _b, entry: 'bookmarks_screen.dart'),
  ];

  // ── H. Dapps (tab + runner) ───────────────────────────────────────────────
  static const dapps = <FlowSpec>[
    FlowSpec(id: 'dapps.open_catalog', name: 'Open dapp catalog', surfaces: _b, tags: {'smoke'}, entry: 'dapps_screen.dart'),
    FlowSpec(id: 'dapps.run_ledger_mainnet', name: 'Run ICP Ledger dapp (mainnet)', surfaces: _d, tags: {'desktop-only'}, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.run_poll', name: 'Run on-chain poll + vote', surfaces: _d, keyring: Keyring.mockSecretService, tags: {'desktop-only'}, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.create_profile_to_vote', name: 'Create profile to vote (mid-flow)', surfaces: _b, keyring: Keyring.mockSecretService, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.open_frontend', name: 'Open dapp frontend in browser', surfaces: _b, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.apply_connection', name: 'Apply connection override', surfaces: _b, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.refresh', name: 'Refresh dapp', surfaces: _d, tags: {'desktop-only'}, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.trust_grant', name: 'Grant dapp trust', surfaces: _b, entry: 'script_app_host.dart'),
    FlowSpec(id: 'dapps.manage_trust_revoke', name: 'Revoke dapp trust', surfaces: _b, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.copy_principal', name: 'Copy principal', surfaces: _b, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'dapps.local_replica_unreachable', name: 'Local replica unreachable panel', surfaces: _b, entry: 'dapp_runner_screen.dart'),
  ];

  // ── I. Vault (zero-knowledge credential store) ───────────────────────────
  static const vault = <FlowSpec>[
    FlowSpec(id: 'vault.route_from_menu', name: 'Reach vault from profile menu', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'smoke', 'vault'}, entry: 'profile_menu.dart'),
    FlowSpec(id: 'vault.setup', name: 'Set up vault (encrypt locally)', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'vault'}, entry: 'vault_password_setup_screen.dart'),
    FlowSpec(id: 'vault.unlock', name: 'Unlock vault (decrypt locally)', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'vault'}, entry: 'vault_unlock_screen.dart'),
    FlowSpec(id: 'vault.unlock_wrong_password', name: 'Unlock with wrong password fails loud', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'vault'}, entry: 'vault_unlock_screen.dart'),
    FlowSpec(id: 'vault.use_recovery_code', name: 'Use recovery code', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'vault'}, entry: 'vault_unlock_screen.dart'),
  ];

  // ── J. Passkeys (web-only authenticator) ─────────────────────────────────
  static const passkey = <FlowSpec>[
    FlowSpec(id: 'passkey.list', name: 'List passkeys', surfaces: _w, tags: {'web-only'}, entry: 'passkey_management_screen.dart'),
    FlowSpec(id: 'passkey.register', name: 'Register a passkey', surfaces: _w, keyring: Keyring.mockSecretService, tags: {'web-only'}, entry: 'passkey_management_screen.dart'),
    FlowSpec(id: 'passkey.delete', name: 'Delete a passkey', surfaces: _w, keyring: Keyring.mockSecretService, tags: {'web-only'}, entry: 'passkey_management.dart'),
    FlowSpec(id: 'passkey.unsupported_linux', name: 'Linux desktop unsupported notice', surfaces: _d, tags: {'desktop-only'}, entry: 'account_profile_screen.dart'),
  ];

  // ── K. Settings ──────────────────────────────────────────────────────────
  static const settings = <FlowSpec>[
    FlowSpec(id: 'settings.open', name: 'Open settings', surfaces: _b, tags: {'smoke'}, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.theme', name: 'Change theme', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.docs_link', name: 'Open documentation link', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.report_issue', name: 'Open report-issue link', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.getting_started', name: 'Reset getting-started', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.restart_tour', name: 'Restart tour', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.unlock_dev_options', name: 'Unlock dev options (7 taps)', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.clear_dev_options', name: 'Clear dev options', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.copy_api_endpoint', name: 'Copy API endpoint', surfaces: _b, entry: 'settings_screen.dart'),
    FlowSpec(id: 'settings.version_display', name: 'Version display', surfaces: _b, entry: 'settings_screen.dart'),
  ];

  // ── L. Keyboard shortcuts (desktop) ──────────────────────────────────────
  static const shortcuts = <FlowSpec>[
    FlowSpec(id: 'shortcut.new_script', name: 'N — new script', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.focus_search', name: '/ and Ctrl+F — focus search', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.refresh', name: 'R — refresh', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.tab_switch', name: 'Alt+1/2/3 — switch tabs', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.show_help', name: '? — show shortcuts help', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.dapp_refresh', name: 'R — refresh dapp', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'dapp_runner_screen.dart'),
    FlowSpec(id: 'shortcut.account_save', name: 'Ctrl+S — save profile', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'account_profile_screen.dart'),
    FlowSpec(id: 'shortcut.escape_back', name: 'Esc — back/close', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'keyboard_shortcuts.dart'),
    FlowSpec(id: 'shortcut.details_prev_next_tab', name: '←/→ — detail dialog tabs', surfaces: _d, tags: {'desktop-only', 'keyboard'}, entry: 'script_details_dialog.dart'),
  ];

  // ── M. Deep links (Phase L: Web Tier A substrate lets these run on Web too)
  // The desktop routes deep links through `app_links`; the Web Tier A
  // harness pumps synthetic URIs through `DeepLinkService.instance.handleLink`
  // directly (the same public API the app's listener subscribes to on
  // non-linux surfaces) and asserts dispatch behaviour at the parsing layer.
  static const deeplink = <FlowSpec>[
    FlowSpec(id: 'deeplink.open_script', name: 'Open script via deep link', surfaces: _b, keyring: Keyring.mockSecretService, tags: {'desktop-only', 'phase-l-web'}, entry: 'main.dart'),
    FlowSpec(id: 'deeplink.purchase_unavailable', name: 'Deep-link purchase unavailable notice', surfaces: _b, tags: {'phase-l-web'}, entry: 'main.dart'),
    FlowSpec(id: 'deeplink.invalid_scheme', name: 'Invalid deep-link scheme ignored', surfaces: _b, tags: {'phase-l-web'}, entry: 'deep_link_service.dart'),
  ];

  static List<FlowSpec> get all => <FlowSpec>[
        ...firstRun, ...profile, ...keypair, ...account, ...scripts,
        ...downloads, ...canisters, ...dapps, ...vault, ...passkey,
        ...settings, ...shortcuts, ...deeplink,
      ];

  static Set<String> get allIds =>
      all.map((FlowSpec f) => f.id).toSet();

  /// Filter by surface + (optional) tag.
  static List<FlowSpec> select({
    Surface? surface,
    String? tag,
    bool Function(FlowSpec)? where,
  }) =>
      all.where((FlowSpec f) {
        if (surface != null && !f.surfaces.contains(surface)) return false;
        if (tag != null && !f.tags.contains(tag)) return false;
        if (where != null && !where(f)) return false;
        return true;
      }).toList();

  /// Coverage vs a registry of implementations.
  static ({int total, int implemented, List<String> gaps, List<String> covered})
      coverageReport(FlowRegistry registry) {
    final gaps = <String>[];
    final covered = <String>[];
    for (final spec in all) {
      if (registry.isImplemented(spec.id)) {
        covered.add(spec.id);
      } else {
        gaps.add(spec.id);
      }
    }
    return (
      total: all.length,
      implemented: covered.length,
      gaps: gaps,
      covered: covered,
    );
  }

  /// The Phase-0 seed defect list (drives Phase 3 RED→GREEN). Source of truth
  /// for the issue tracker; extend as the real-app sweep surfaces more.
  /// Known defects discovered during Phase-0 recon. Each was a RED test → fix →
  /// GREEN in Phase 3. F1–F5, F7, F8 are **resolved** (see git history + TODO.md).
  /// F6 remains environmental (canned-bridge test does not reproduce the 530).
  static const knownIssues = <KnownIssue>[
    KnownIssue(id: 'F6', flowId: 'dapps.run_poll', severity: IssueSeverity.major, summary: 'dapp vote flow reports HTTP 530 on catalog fetch — environmental; the test uses a canned bridge so this is likely stale', evidence: 'f_dapp_vote_flow_test.dart uses _RecordingBridge, not mainnet'),
  ];
}
