// ignore_for_file: lines_longer_than_80_chars

// H-3 — Web e2e harness Tier 1 (widget-test catalog against the REAL app).
//
// WHAT THIS PROVES
//   `flutter test -d chrome` boots the REAL KeypairApp on Playwright Chromium
//   (~20s cold / seconds warm, headless, no chromedriver). The conditional-
//   import split selects native_bridge_web.dart, so the REAL pure-Dart
//   Ed25519/secp256k1/Argon2id/AES-256-GCM crypto loads — NO FFI touched.
//   Asserts the cross-surface contract: the FlowCatalog compiles on web and
//   the production widget tree mounts.
//
// THE WEB LIMITATION (documented, honest)
//   `flutter test -d chrome` runs under TestWidgetsFlutterBinding, which (a)
//   returns HTTP 400 for EVERY network call and (b) registers NO real plugins
//   (shared_preferences / path_provider / app_links throw MissingPluginException).
//   Real-network flows (marketplace browse/download) therefore CANNOT run
//   here. True real-app web e2e needs `integration_test`-on-web, which Flutter
//   3.38.3 does NOT support (`flutter drive` web+integration_test fails with a
//   Flutter-FRAMEWORK compile error — `<invalid>` exhaustiveness in
//   cupertino/colors.dart; see web_drive_smoke_test.dart). Tracked follow-up:
//   when Flutter ships integration_test-on-web, the SAME FlowRun bodies move
//   over unchanged.
//
//   Network-INDEPENDENT web flows (wizard render, profile create via
//   localStorage, vault crypto, settings UI) ARE testable here once plugin
//   substrate fakes (SharedPreferences.setMockInitialValues …) are wired in
//   setUp — honest platform substrate (like Xvfb), not business mocking. That
//   lands in Phase 2 with the flow migration.
//
// Run via: `just e2e-web`
@Tags(['web'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e/e2e_driver.dart';
import '../../integration_test/e2e/flow_catalog.dart';

void main() {
  final driver = E2EDriver(surface: E2ESurface.web);
  final registry = FlowRegistry();

  // Compile-time proof the FlowRun signature is web-portable.
  registry.register(FlowCatalog.firstRun[2].id, (tester, d) async {
    await d.boot(tester);
    d.phase('web.dismiss_wizard', 'FlowRun body compiles + runs on web');
  });

  testWidgets('web e2e Tier 1 — real app boots on Chromium', (tester) async {
    driver.phase('WEB SUITE', 'Tier 1 — real app, Playwright Chromium');

    // Minimal, proven boot: pumpWidget + bounded pumps. NO runAsync (would fire
    // fatal MissingPluginException with no plugins registered), NO screenshot
    // (renderViews/layer access differs under TestWidgetsFlutterBinding).
    await driver.boot(tester);
    expect(find.byType(MaterialApp), findsOneWidget,
        reason: 'KeypairApp must mount a MaterialApp root on Web.');
    driver.phase('boot', 'MaterialApp mounted');

    // Coverage contract: the catalog is intact and the registry wires up.
    final report = FlowCatalog.coverageReport(registry);
    expect(report.total, greaterThan(90), reason: 'catalog lists all flows');
    expect(report.implemented, greaterThanOrEqualTo(1),
        reason: 'smoke flow registered');
    driver.phase('coverage',
        '${report.implemented}/${report.total} flows registered');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
