// H-3 Tier 2 — REAL app web boot via `flutter drive`. CURRENTLY BLOCKED.
//
// Unlike `flutter test -d chrome` (TestWidgetsFlutterBinding: fake HTTP 400 +
// no real plugins), `flutter drive` boots the full production platform with
// REAL network and REAL plugins — the only NO-MOCKS path to real-app web e2e.
//
// BLOCKED ON FLUTTER 3.38.3: `integration_test`-on-web is not supported.
// `flutter drive -d chrome --target=<integration_test>` fails at WEB DEBUG
// COMPILE on Flutter's OWN framework code — `<invalid>` exhaustiveness errors
// in cupertino/colors.dart:1024 and material/tooltip.dart:827 (not app code;
// cache-clear doesn't help). This file is kept as the repro + entry point for
// when Flutter ships working integration_test-on-web. Then the desktop FlowRun
// bodies move over UNCHANGED (same WidgetTester + E2EDriver API).
//
// Repro (Xvfb:97 + chromedriver 149 + 3 container Chrome flags required):
//   DISPLAY=:97 CHROME_EXECUTABLE=<playwright-chrome> flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/e2e/web_drive_smoke_test.dart -d chrome \
//     --web-browser-flag=--no-sandbox --web-browser-flag=--disable-gpu \
//     --web-browser-flag=--disable-dev-shm-usage
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web drive boot — real app renders', (tester) async {
    await tester.pumpWidget(const app.KeypairApp());

    var booted = false;
    for (var i = 0; i < 60 && !booted; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      booted = tester.any(find.byType(MaterialApp));
    }
    expect(booted, isTrue, reason: 'MaterialApp should mount on web boot.');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
