// ignore_for_file: lines_longer_than_80_chars

// Phase C Tier A — REAL-app Web e2e harness via `flutter test -d chrome` with
// substrate fakes at the smallest I/O boundary.
//
// WHAT THIS PROVES
//   `flutter test -d chrome` boots the REAL KeypairApp on Playwright Chromium
//   with the REAL pure-Dart Ed25519/secp256k1/Argon2id/AES-256-GCM Web crypto
//   (NO FFI touched). The substrate fakes (HTTP mock + SharedPreferences +
//   FlutterSecureStorage + path_provider) let the unawaited async chain in
//   `_KeypairAppState.initState` (ensureLoaded → first-run gate) complete, so
//   every FlowCatalog web flow runs against the REAL widget tree with REAL
//   business logic — only the literal outbound HTTP/plugin calls are
//   boundary-faked (per AGENTS.md "mock at the smallest boundary in e2e
//   tests").
//
// CROSS-SURFACE SHARING
//   The shared flow bodies live in `integration_test/e2e/flow_implementations.dart`
//   and are surface-agnostic: they call `driver.boot(tester)` (which dispatches
//   to the substrate-aware path on web when `substrateAware: true`), then use
//   `find.*` + `tester.tap` exactly as the desktop suite does. The desktop
//   suite currently inlines its flow bodies; this library is the DRY migration
//   target (the desktop suite can swap its inlined closures for the library
//   functions one flow at a time).
//
// Run via: `just e2e-web` (justfile picks up the default smoke file). To run
// THIS suite explicitly:
//   just e2e-web file=test/e2e_web/suite_web_flows_test.dart
@Tags(['web'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e/e2e_driver.dart';
import '../../integration_test/e2e/flow_catalog.dart';
import '../../integration_test/e2e/flow_implementations.dart';
import 'substrate/substrate.dart';

void main() {
  // Install the substrate ONCE for the whole suite. The singletons capture
  // the mock client on first use; SharedPreferences / FlutterSecureStorage
  // in-memory mocks are process-wide; path_provider fake backs every
  // path-provider call with a stable temp dir.
  setUpAll(() {
    installSubstratePrefs();
    installSubstrateSecureStorage();
    installSubstrateHttp(defaultServer());
    installSubstratePathProvider();
    installSubstrateAppLinksSilencer();
    installSubstratePackageInfo();
  });

  // Substrate-aware driver: the web `boot` branch dispatches to the
  // substrate code path (runAsync drives the unawaited async chain so the
  // first-run gate evaluates).
  final driver = E2EDriver(surface: E2ESurface.web, substrateAware: true);

  final registry = FlowRegistry()
    ..register('first_run.dismiss_wizard', firstRunDismissWizard)
    ..register('first_run.reopen_wizard_chip', firstRunReopenWizardChip)
    ..register('profile.open_menu', profileOpenMenu)
    ..register('settings.open', settingsOpen)
    ..register('settings.theme', settingsTheme)
    ..register('settings.version_display', settingsVersionDisplay)
    ..register('scripts.browse_marketplace', scriptsBrowseMarketplace);

  testWidgets('web e2e Tier A — substrate harness drives 7 real-app flows',
      (tester) async {
    driver.phase('WEB SUITE',
        'Tier A — REAL app + substrate fakes on Playwright Chromium');

    // PHASE 1: boot + first-run wizard appears + dismiss.
    driver.phase('1', 'first_run.dismiss_wizard');
    await registry.runFor('first_run.dismiss_wizard')!(tester, driver);
    driver.phase('1', 'OK — first_run.dismiss_wizard');

    // PHASE 2: chip re-opens the wizard (after dismissal the chip is the
    // persistent CTA).
    driver.phase('2', 'first_run.reopen_wizard_chip');
    await registry.runFor('first_run.reopen_wizard_chip')!(tester, driver);
    driver.phase('2', 'OK — first_run.reopen_wizard_chip');

    // PHASE 3: profile menu.
    driver.phase('3', 'profile.open_menu');
    await registry.runFor('profile.open_menu')!(tester, driver);
    driver.phase('3', 'OK — profile.open_menu');

    // PHASE 4: settings opens from the menu (still open from phase 3).
    driver.phase('4', 'settings.open');
    await registry.runFor('settings.open')!(tester, driver);
    driver.phase('4', 'OK — settings.open');

    // PHASE 5: settings.version_display (Settings is mounted from phase 4).
    driver.phase('5', 'settings.version_display');
    await registry.runFor('settings.version_display')!(tester, driver);
    driver.phase('5', 'OK — settings.version_display');

    // PHASE 6: settings.theme — toggle Dark, restore System.
    driver.phase('6', 'settings.theme');
    await registry.runFor('settings.theme')!(tester, driver);
    driver.phase('6', 'OK — settings.theme');

    // PHASE 7: close settings, return to Scripts, marketplace tiles appear.
    driver.phase('7', 'scripts.browse_marketplace');
    await tester.pageBack();
    await driver.waitUntil(tester,
        () => driver.present(find.text('Scripts'), tester),
        timeout: const Duration(seconds: 5));
    // Wait for the bottom-nav "Scripts" label (alternative to top-tab label).
    await tester.runAsync<void>(
        () => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 1));
    await registry.runFor('scripts.browse_marketplace')!(tester, driver);
    driver.phase('7', 'OK — scripts.browse_marketplace');

    // Drain flutter_cache_manager's cleanup timer (10s one-shot created
    // when the wizard mounted CachedNetworkImage) so the binding's
    // `timersPending` invariant doesn't trip on teardown.
    await tester.pump(const Duration(seconds: 11));

    // Coverage report.
    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE',
        '${cov.implemented}/${cov.total} flows registered; '
        'this suite covers: ${cov.covered.join(", ")}');
    expect(cov.total, greaterThan(90), reason: 'Catalog lists all flows.');
    expect(cov.implemented, greaterThanOrEqualTo(7),
        reason: 'Tier A must cover at least 7 flows (PoC bar).');

    // ignore: avoid_print
    print('SUITE_WEB_FLOWS: PASS — ${cov.implemented} flows covered on Web.');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
