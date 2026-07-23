// ignore_for_file: lines_longer_than_80_chars

/// Fast widget-test e2e harness — boots the REAL app on the Dart VM with
/// substrate fakes at the I/O boundary + REAL FFI (`libicp_core.so`).
///
/// This is the radical speed improvement over the integration-test suites:
/// instead of 4 separate `IntegrationTestWidgetsFlutterBinding` boots at ~9m
/// total, ALL flows run as widget tests in ~60–90s while still exercising the
/// real `KeypairApp()` widget tree, real QuickJS, real Ed25519/Argon2id/AES,
/// and real conditional-import `native_bridge_io.dart`.
///
/// The only mocks are at the smallest I/O boundary (same boundary the Web e2e
/// harness mocks):
///   - **SharedPreferences** (SDK mock) — settings, onboarding gate, store
///   - **FlutterSecureStorage** (SDK mock) — keypairs, mnemonics
///   - **HTTP** (MockClient on MarketplaceOpenApiService + PasskeyService) —
///     marketplace, vault, passkey endpoints
///   - **path_provider** (fake platform) — temp dir for FileJsonStore
///   - **package_info** (fake platform) — version display
///   - **app_links** (silencer) — deep-link handler
///
/// **Connectivity note:** `ConnectivityService`'s raw `dart:io HttpClient`
/// health probe will fail (no network on dev box) → app shows offline banner.
/// This does NOT affect flows — all marketplace/account/vault data comes
/// through the substrate MockClient, not the dart:io HttpClient. The offline
/// banner is purely cosmetic in this harness. A proper fix would inject a
/// `ConnectivityService(probe: () async => true)` via `ConnectivityScope`'s
/// `service` parameter, but that requires a production-code seam.
///
/// Flows use the SAME `E2EDriver` + `FlowRegistry` + `FlowCatalog` as the
/// integration-test and Web suites — one flow body, three surfaces.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/main.dart' as app;
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/json_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../integration_test/e2e/e2e_driver.dart';
import '../e2e_web/substrate/substrate.dart';

/// Orchestrates the fast e2e harness lifecycle.
///
/// Typical usage in a test file:
/// ```dart
/// final harness = FastHarness();
///
/// setUpAll(() async {
///   await harness.setUp();
/// });
///
/// tearDownAll(() async {
///   await harness.tearDown();
/// });
///
/// testWidgets('scripts.browse_marketplace', (tester) async {
///   harness.resetState();
///   await harness.boot(tester);
///   await harness.driver.dismissWizard(tester);
///   // ... run flow ...
/// });
/// ```
class FastHarness {
  late final E2EDriver driver;
  late final SubstrateJsonStore _jsonStore;

  FastHarness();

  /// Install ALL substrate fakes. Call once per suite (`setUpAll`).
  Future<void> setUp() async {
    // 1. SharedPreferences: SDK-blessed in-memory mock.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();

    // 2. FlutterSecureStorage: SDK-blessed in-memory mock.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    // 3. Substrate HTTP server + MockClient install.
    installSubstrateHttp(defaultServer());

    // 4. Path provider: fake platform returning a real temp dir.
    installSubstratePathProvider();

    // 5. Package info: fake platform.
    installSubstratePackageInfo();

    // 6. App links: silencer.
    installSubstrateAppLinksSilencer();

    // 7. In-memory JsonDocumentStore: FileJsonStore's real dart:io file I/O
    //    hangs under the test binding's fake clock. This injects a pure-Dart
    //    store that completes synchronously (same as WebJsonStore on Web).
    //    The SAME instance is kept across all tests — clearing its data in
    //    [resetState] is enough because ScriptRepository._instance (a static
    //    singleton) caches the _store reference and would ignore a new instance.
    _jsonStore = installSubstrateJsonStore();

    // 8. AppConfig: point at an invalid local port so the ConnectivityService's
    //    health probe fails fast with SocketRefused (no external network
    //    dependency). The app shows "offline" but flows work — all data comes
    //    from the substrate MockClient, not the dart:io HttpClient.
    AppConfig.setTestEndpoint('http://127.0.0.1:1');

    // 9. E2EDriver: use the web substrate-aware boot path (pumpWidget +
    //    runAsync loop). This works on the Dart VM — the conditional imports
    //    resolve to the IO variants (real FFI), but the boot logic is the
    //    same as web: pump the production widget tree, drive the async chain.
    driver = E2EDriver(
      surface: E2ESurface.web,
      substrateAware: true,
    );
  }

  /// Reset ALL substrate state to a clean slate. Call at the top of each
  /// `testWidgets` to isolate flows from each other.
  void resetState() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    installSubstrateHttp(defaultServer());
    installSubstratePathProvider();
    _jsonStore.reset();
  }

  /// Boot the REAL app. Pumps `KeypairApp(key: UniqueKey())` so each boot
  /// creates a fresh `_KeypairAppState` (controllers re-init, store re-loads).
  /// The substrate-aware runAsync loop drives the async boot chain
  /// (ensureLoaded → first-run gate) to completion.
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopSize * kDesktopDpr;
    tester.view.devicePixelRatio = kDesktopDpr;
    WidgetController.hitTestWarningShouldBeFatal = true;

    await tester.pumpWidget(app.KeypairApp(key: UniqueKey()));

    // Drive the unawaited async chain via runAsync so real plugin round-trips
    // (SharedPreferences, FlutterSecureStorage, path_provider) complete and
    // the first-run gate evaluates. Same pattern as the web substrate-aware
    // boot in E2EDriver.boot().
    for (var i = 0; i < 30; i++) {
      await tester.runAsync<void>(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      final settled = driver.present(
        find.byWidgetPredicate((w) =>
            w is UnifiedSetupWizard ||
            (w is Text &&
                (w.data?.contains('Set up profile') ?? false))),
        tester,
      );
      if (settled) break;
    }
  }

  /// Dismiss the first-run wizard if present.
  Future<void> dismissWizard(WidgetTester tester) async {
    await driver.dismissWizard(tester);
  }

  /// Tear down. Call in `tearDownAll`.
  Future<void> tearDown() async {
    testJsonStoreOverride = null;
  }
}
