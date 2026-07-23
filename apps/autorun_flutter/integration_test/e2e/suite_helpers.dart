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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/widgets/scripts_search_bar.dart';

import 'e2e_driver.dart';
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

/// Stop the image cache manager cleanly before deleting its on-disk state.
///
/// `flutter_cache_manager`'s `JsonCacheInfoRepository` holds an in-memory
/// index of every cached image URL and a 3-second `Timer` that lazily writes
/// `libCachedImageData.json` into the app-support dir. If `resetAppState`
/// deletes that dir out from under the manager, the next timer fire throws
/// `PathNotFoundException`, which propagates as a `_pendingFrame == null`
/// assertion in `LiveTestWidgetsFlutterBinding.postTest` and kills the suite
/// (NEW-1, 2026-07-21).
///
/// `emptyCache()` clears the in-memory index AND deletes the on-disk cache
/// files via the manager's own concurrency-safe path. `dispose()` flushes the
/// JSON repository (writing the now-empty `[]` to disk) and cancels the lazy
/// Timer so no deferred write can race the directory delete below. After
/// `dispose()`, subsequent calls re-open the repository lazily on next access,
/// so this helper is safe to call across phases.
///
/// Must run under `tester.runAsync` because it hits `path_provider`'s platform
/// channel when re-opening the repository.
Future<void> _stopImageCache(WidgetTester? tester) async {
  Future<void> flush() async {
    await DefaultCacheManager().emptyCache();
    await DefaultCacheManager().dispose();
  }

  if (tester != null) {
    await tester.runAsync(flush);
  } else {
    await flush();
  }
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
  // (0) Stop the image cache manager FIRST so its lazy-write Timer doesn't
  //     fire mid-wipe and throw PathNotFoundException on the deleted dir
  //     (NEW-1). Must run under `tester.runAsync` (hits path_provider).
  await _stopImageCache(tester);

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
  //
  //     After the delete, the directory is RECREATED empty so any lingering
  //     lazy write from a path_provider-cached handle (see NEW-1) lands on a
  //     valid path instead of throwing PathNotFoundException.
  final dir = Directory(_appSupportDir());
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  final legacy = Directory(
      '${Platform.environment['HOME'] ?? '/tmp'}/.local/share/com.example.icp_autorun');
  if (await legacy.exists()) {
    await legacy.delete(recursive: true);
  }
  await legacy.create(recursive: true);

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

// ── Marketplace suite helpers (shared between keyring-less + marketplace) ────

/// Backend script titles (real data, verified via curl on the dev backend).
const kCounterTitle = 'Interactive Counter';
const kBalanceTitle = 'ICP Balance Reader';
const kHelloTitle = 'Hello IC Starter';

/// Enter text into the search bar, clear first, then wait for debounce + fetch.
Future<void> enterSearch(
    WidgetTester tester, E2EDriver d, String query) async {
  final searchField = find.descendant(
      of: find.byType(ScriptsSearchBar),
      matching: find.byType(TextField));
  await tester.enterText(searchField, '');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(searchField, query);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Clear the search field and wait for the full list to restore.
Future<void> clearSearch(WidgetTester tester, E2EDriver d) async {
  final searchField = find.descendant(
      of: find.byType(ScriptsSearchBar),
      matching: find.byType(TextField));
  await tester.enterText(searchField, '');
  await tester.pump(const Duration(milliseconds: 500));
  // Unfocus the search field without tapping the screen — a center-screen
  // tap hits a script tile and opens a details dialog.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  // Wait for at least one marketplace script to reappear after clearing.
  await d.waitUntil(
      tester, () => d.present(find.text(kCounterTitle), tester),
      timeout: const Duration(seconds: 10));
}

/// Open the filter bottom sheet by invoking the search bar's filter callback.
///
/// The filter IconButton's tap gesture is intercepted by the Overlay's modal
/// barrier in the integration-test headless environment. Invoking the callback
/// directly tests the real filter code path — showModalBottomSheet →
/// FilterBottomSheet — without relying on gesture hit-testing.
Future<void> openFilterSheet(WidgetTester tester, E2EDriver d) async {
  final searchBar = tester.widget<ScriptsSearchBar>(find.byType(ScriptsSearchBar));
  searchBar.onFilterButtonPressed();
  final sheetOpen = await d.waitUntil(
      tester, () => d.present(find.text('Filters'), tester),
      timeout: const Duration(seconds: 5));
  assert(sheetOpen, 'Filter button callback must open the bottom sheet.');
  await tester.pump(const Duration(milliseconds: 300));
}

/// Close the filter bottom sheet by pressing Escape (modal dismiss).
Future<void> closeFilterSheet(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Dismiss the post-registration "Secure your account" prompt (UX-H6) if it
/// appears after the wizard's `registerAccount` call succeeds. The prompt
/// blocks the wizard from reaching the Success screen. In e2e we always skip
/// (the vault + passkey flows are exercised by their own dedicated flows).
///
/// Polls for up to [timeout] for the dialog title "Secure your account"; if
/// found, taps "Skip for now". If the dialog never appears (e.g. local-only
/// profile path, or the wizard went straight to Success), returns without
/// error.
Future<void> dismissPostRegistrationSecurityPrompt(
  WidgetTester tester,
  E2EDriver d, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final appeared = await d.waitUntil(
    tester,
    () => d.present(find.text('Secure your account'), tester),
    timeout: timeout,
  );
  if (!appeared) return;
  await tester.tap(find.text('Skip for now'));
  await tester.pump(const Duration(milliseconds: 500));
}
