// ignore_for_file: lines_longer_than_80_chars

/// Test-only state isolation for the unified e2e harness.
///
/// The shared-boot model boots the real app ONCE per keyring-mode and runs many
/// flows. Between flows, [resetAppState] wipes every on-disk + prefs surface a
/// flow can touch, so the next phase starts in a true first-run state. Pair
/// with `driver.remount(tester)` (cheap in-process reboot) to re-fire the
/// first-run gate.
///
/// This is a TEST AFFORDANCE over the real app — not a mock. It deletes the
/// same real stores the app uses; production code paths are unchanged.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/services/profile_repository.dart';

/// The path_provider `appSupport` resolution on this Linux build.
String _appSupportDir() {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return '$xdg/com.example.icp_autorun';
  }
  final home = Platform.environment['HOME'] ?? '/tmp';
  return '$home/.cache/data/com.example.icp_autorun';
}

/// When non-null (set via `--dart-define=ICP_E2E_STOP_AFTER=<flow-id>`), the
/// suite stops after running this flow — enabling sub-suite single-flow
/// iteration via `just e2e-one <flow-id>`.
const _stopAfter = String.fromEnvironment('ICP_E2E_STOP_AFTER');

/// Whether the suite should stop after this flow (for `just e2e-one`).
bool shouldStopAfter(String flowId) =>
    _stopAfter.isNotEmpty && _stopAfter == flowId;

/// SharedPreferences keys that gate flow state. Cleared wholesale by
/// [resetAppState]. The dapp trust grants use a `dapp.` prefix (see
/// example_dapps.dart `_trustKey`/`_backendKey`/`_hostKey`).
const String kPrefActiveProfileId = 'active_profile_id';
const String kPrefFirstRunDismissed = 'first_run_wizard_dismissed';
const String kPrefDevOptions = 'developer_options_enabled';
const String kPrefSpotlightStarted = 'spotlight_explicitly_started';
const String _kDappPrefix = 'dapp.';

/// Wipe all per-flow state so the next phase boots first-run clean.
///
/// 1. Secure storage (private keys / mnemonics) — via the real
///    `ProfileRepository.deleteAllSecureData()` (libsecret round-trip; MUST
///    run under `tester.runAsync` because it hits the platform channel).
///    Skipped when [wipeSecureStorage] is false: on the KEYRING-LESS surface
///    no Secret Service exists, so no secrets could ever have been written
///    (the readiness gate blocks profile creation). Opting out there avoids a
///    spurious `PlatformException(Libsecret error)` while remaining honest —
///    there is genuinely nothing to wipe.
/// 2. The whole app-support directory: `profiles.json`, `scripts.json`,
///    `bookmarks.json`, `shared_preferences.json`, the cached-image index,
///    any other on-disk artifact. Wiping the directory wholesale (vs.
///    resetting individual files) is the only way to guarantee a true
///    first-run state, since the app can add new state files at any time.
///    Without this, scripts.json / bookmarks.json accumulate across phases
///    and leak "Hello IC Starter (Marketplace)" / "E2E CRUD Script" tiles
///    into the next flow, breaking text-based finders.
/// 3. SharedPreferences in-memory cache (the gating keys + every `dapp.*`
///    trust grant) — see [kPrefActiveProfileId] etc.
///
/// After this, call `driver.remount(tester)` to mount a fresh shell that
/// loads the now-empty store.
Future<void> resetAppState({
  WidgetTester? tester,
  bool wipeSecureStorage = true,
}) async {
  // (1) Secure storage. Hits libsecret → must be real-async.
  if (wipeSecureStorage) {
    Future<void> wipeSecure() => ProfileRepository().deleteAllSecureData();
    if (tester != null) {
      await tester.runAsync(wipeSecure);
    } else {
      await wipeSecure();
    }
  }

  // (2) Wipe the entire app-support directory WHOLESALE. The path follows the
  //     app's path_provider resolution (XDG_DATA_HOME > $HOME/.cache/data),
  //     plus the older $HOME/.local/share location used by some Flutter
  //     versions — belt-and-suspenders so we don't leave state behind on any
  //     layout the test box might use.
  final dir = Directory(_appSupportDir());
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  final legacy = Directory(
      '${Platform.environment['HOME'] ?? '/tmp'}/.local/share/com.example.icp_autorun');
  if (await legacy.exists()) {
    await legacy.delete(recursive: true);
  }

  // (3) SharedPreferences — iterate over a snapshot (mutating during iteration
  // is unsafe). Clears the two gating keys + every dapp trust grant.
  final prefs = await SharedPreferences.getInstance();
  final keys = prefs.getKeys().toList(growable: false);
  for (final key in keys) {
    if (key == kPrefActiveProfileId ||
        key == kPrefFirstRunDismissed ||
        key == kPrefDevOptions ||
        key == kPrefSpotlightStarted ||
        key.startsWith(_kDappPrefix)) {
      await prefs.remove(key);
    }
  }
}
