// ignore_for_file: lines_longer_than_80_chars

/// Web e2e helpers — substrate reset and boot utilities for per-flow web tests.
///
/// The web harness runs under `flutter test -d chrome` (TestWidgetsFlutter
/// Binding on Chromium). State lives in process-wide substrate singletons
/// (SharedPreferences, FlutterSecureStorage, SubstrateMockServer, FileJsonStore
/// temp dir). Unlike desktop where [resetAppState] wipes a real app-support
/// dir + libsecret, the web substrate needs explicit SDK-level resets to
/// isolate state between `testWidgets` bodies.
///
/// Key insight: `SharedPreferences` caches its instance via a static
/// `Completer`. Calling `setMockInitialValues({})` alone does NOT clear the
/// cached instance — `SharedPreferences.resetStatic()` must also be called to
/// null the completer so the next `getInstance()` re-reads from the (now
/// empty) mock store. `FlutterSecureStorage.setMockInitialValues` replaces
/// the entire platform instance, so no extra reset is needed there.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'substrate/substrate.dart';

/// Install ALL substrate fakes for a fresh test run. Call once per
/// `testWidgets` (or once per suite via `setUpAll` if state isolation is
/// handled by [resetWebAppState]).
///
/// Returns the [SubstrateMockServer] so callers can assert on substrate state
/// (e.g. passkey store contents).
SubstrateMockServer installWebSubstrate() {
  installSubstratePrefs();
  installSubstrateSecureStorage();
  final server = defaultServer();
  installSubstrateHttp(server);
  installSubstratePathProvider();
  installSubstrateAppLinksSilencer();
  installSubstratePackageInfo();
  return server;
}

/// Reset ALL web substrate state to a clean slate. Call at the top of each
/// per-flow `testWidgets` (or in `setUp`) to isolate flows from each other.
///
/// After this call, the next `KeypairApp` boot will see:
/// - Empty SharedPreferences (no onboarding gate, no settings, no profiles)
/// - Empty FlutterSecureStorage (no keypairs, no mnemonics)
/// - Empty passkey/vault buckets on the substrate HTTP server
/// - Clean FileJsonStore temp dir (new path provider → new temp dir)
void resetWebAppState() {
  // 1. SharedPreferences: replace the backing mock map AND null the cached
  //    Completer so the next getInstance() re-reads from the empty store.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  SharedPreferences.resetStatic();

  // 2. FlutterSecureStorage: replaces the entire platform instance with a
  //    fresh in-memory store (no extra reset needed).
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  // 3. SubstrateMockServer: re-create + re-install for fresh vault/passkey
  //    buckets. The HTTP singletons (MarketplaceOpenApiService,
  //    PasskeyService) get the new MockClient.
  final server = defaultServer();
  installSubstrateHttp(server);

  // 4. Path provider: re-install for a fresh temp dir. The OLD temp dir is
  //    intentionally NOT deleted — flutter_cache_manager may have a pending
  //    lazy-write Timer pointing at it. Deleting mid-write causes a
  //    PathNotFoundException. The orphaned dir is harmless (OS reaps /tmp).
  installSubstratePathProvider();
}
