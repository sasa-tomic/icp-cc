// Unified helpers for all ux_probe integration tests.
//
// Consolidates the former ux_helpers.dart, r3_helpers.dart, and
// r3_addendum_helpers.dart — which were near-identical copies differing only
// in the screenshot output directory. Each probe now passes its own dir to
// [shot].
//
// These probes launch the REAL app (lib/main.dart) under the Flutter
// integration-test binding, drive interactive flows, capture screenshots, and
// assert behaviors. They exercise the production widget tree (no widget mocks)
// so screenshots + assertions reflect what a user actually sees.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart' as app;

/// Desktop surface we render at (matches the Xvfb screen size).
const Size kDesktopSize = Size(1440, 900);
const double kDpr = 1.0;

/// Screenshot output dirs per review round.
const String kShotDirRound2 =
    '/code/icp-cc/docs/specs/ux_screenshots/round2';
const String kShotDirRound3 =
    '/code/icp-cc/docs/specs/ux_screenshots/round3';
const String kShotDirRound3Addendum =
    '/code/icp-cc/docs/specs/ux_screenshots/round3_addendum';

/// Wipe on-disk profile state so the first-run gate fires.
///
/// Clears every path that [ProfileRepository] has historically resolved to on
/// this Linux build: `~/.cache/data/...`, `~/.local/share/...`, and
/// `$XDG_DATA_HOME/...`. Rewriting profiles.json to the empty list forces
/// `profiles.isEmpty` for a clean first-run.
Future<void> clearProfileState() async {
  final home = Platform.environment['HOME'] ?? '/tmp';

  // Primary: the path path_provider resolves to on Linux.
  final cacheDir = Directory('$home/.cache/data/com.example.icp_autorun');
  if (await cacheDir.exists()) {
    final profiles = File('${cacheDir.path}/profiles.json');
    if (await profiles.exists()) {
      await profiles.writeAsString('{"version":1,"profiles":[]}');
    }
  }

  // Legacy/alt path under ~/.local/share.
  final alt = Directory('$home/.local/share/com.example.icp_autorun');
  if (await alt.exists()) {
    await alt.delete(recursive: true);
  }

  // XDG_DATA_HOME override (used by run-with-mock-keyring.sh).
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    final xdgDir = Directory('$xdg/com.example.icp_autorun');
    if (await xdgDir.exists()) {
      await xdgDir.delete(recursive: true);
    }
  }
}

/// Configure a desktop-sized rendering surface and launch the real app.
Future<void> launchApp(WidgetTester tester) async {
  tester.view.physicalSize = kDesktopSize * kDpr;
  tester.view.devicePixelRatio = kDpr;
  await tester.runAsync(() async {
    app.main();
  });
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Capture a screenshot of the current render tree to [name] under [dir].
///
/// Captures straight from the layer tree (`RenderView.layer.toImage`) because
/// the integration_test method-channel takeScreenshot is unserviced without a
/// flutter_driver.
Future<void> shot(
  WidgetTester tester,
  String name, {
  required String dir,
}) async {
  await Directory(dir).create(recursive: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final RenderView view = tester.binding.renderViews.first;
  final Size size = view.size.isEmpty ? kDesktopSize : view.size;
  // Screenshot capture requires direct access to the render layer tree; this is
  // a legitimate test-only use of the protected member.
  // ignore: invalid_use_of_protected_member
  final OffsetLayer layer = view.layer! as OffsetLayer;
  final ui.Image image = await layer.toImage(
    Offset.zero & size,
    pixelRatio: kDpr,
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode screenshot $name to PNG.');
  }
  final file = File('$dir/$name.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  image.dispose();
}

/// Like [find.byType] but returns whether ANY matching widget is present.
bool present(Finder f, WidgetTester tester) => tester.any(f);

/// Dismiss the first-run wizard by tapping its AppBar `Icons.close` leading
/// button. Bounded pumps — `pumpAndSettle` never returns because the Scripts
/// screen kicks off marketplace fetches that animate indefinitely.
Future<void> dismissWizard(WidgetTester tester) async {
  int guard = 0;
  while (!present(find.byIcon(Icons.close), tester) && guard < 60) {
    await tester.pump(const Duration(milliseconds: 200));
    guard++;
  }
  if (present(find.byIcon(Icons.close), tester)) {
    await tester.tap(find.byIcon(Icons.close).first);
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}
