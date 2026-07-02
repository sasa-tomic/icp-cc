// Shared helpers for UX-review ROUND-3 re-review probes.
//
// These probes launch the REAL app (lib/main.dart) under the Flutter
// integration-test binding, drive interactive flows, capture screenshots
// directly into docs/specs/ux_screenshots/round3/, and print decisive
// widget-tree assertions that back the CONFIRM/REFUTE/CANNOT-VERIFY verdicts
// in docs/specs/UX_REVIEW_ROUND3.md.
//
// They intentionally exercise the production widget tree (no widget mocks) so
// the screenshots + assertions reflect what a user actually sees. This is a
// round-3 copy of ux_helpers.dart with only the output directory changed, so
// round-2 evidence remains untouched.
//
// Hard constraint honored: `git diff apps/autorun_flutter/lib` stays EMPTY.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/main.dart' as app;

/// Canonical screenshot output dir for ROUND-3 (matches docs/specs layout).
const String kShotDirR3 =
    '/code/icp-cc/docs/specs/ux_screenshots/round3';

/// Desktop surface we render at (matches the Xvfb screen size).
const Size kDesktopSizeR3 = Size(1440, 900);
const double kDprR3 = 1.0;

/// Wipe on-disk profile state so the first-run gate fires.
///
/// path_provider's getApplicationSupportDirectory() on this Linux build
/// resolves to ~/.cache/data/com.example.icp_autorun/. Clearing profiles.json
/// is enough to force `profiles.isEmpty` for a clean first-run.
Future<void> clearProfileStateR3() async {
  final home = Platform.environment['HOME'] ?? '/tmp';
  final dir = Directory('$home/.cache/data/com.example.icp_autorun');
  if (await dir.exists()) {
    final profiles = File('${dir.path}/profiles.json');
    if (await profiles.exists()) {
      await profiles.writeAsString('{"version":1,"profiles":[]}');
    }
  }
  // Also clear the path the round-2 helper assumed, just in case.
  final alt = Directory('$home/.local/share/com.example.icp_autorun');
  if (await alt.exists()) {
    await alt.delete(recursive: true);
  }
}

/// Configure a desktop-sized rendering surface and launch the real app.
Future<void> launchAppR3(WidgetTester tester) async {
  tester.view.physicalSize = kDesktopSizeR3 * kDprR3;
  tester.view.devicePixelRatio = kDprR3;
  await tester.runAsync(() async {
    app.main();
  });
  // Let async init (FFI load, profile load, theme load) complete.
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Capture a screenshot of the current render tree to [name] under kShotDirR3.
///
/// Captures straight from the layer tree (`RenderView.layer.toImage`) because
/// the integration_test method-channel takeScreenshot is unserviced without a
/// flutter_driver.
Future<void> shotR3(IntegrationTestWidgetsFlutterBinding binding, String name,
    WidgetTester tester) async {
  await Directory(kShotDirR3).create(recursive: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final RenderView view = tester.binding.renderViews.first;
  final Size size = view.size.isEmpty ? kDesktopSizeR3 : view.size;
  // Screenshot capture requires direct access to the render layer tree; this is
  // a legitimate test-only use of the protected member.
  // ignore: invalid_use_of_protected_member
  final OffsetLayer layer = view.layer! as OffsetLayer;
  final ui.Image image = await layer.toImage(
    Offset.zero & size,
    pixelRatio: kDprR3,
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode screenshot $name to PNG.');
  }
  final file = File('$kShotDirR3/$name.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  image.dispose();
}

/// Like [find.byType] but returns whether ANY matching widget is present.
bool presentR3(Finder f, WidgetTester tester) => tester.any(f);

/// Dismiss the first-run wizard by tapping its AppBar `Icons.close` leading
/// button. Bounded pumps (pumpAndSettle never returns: the Scripts screen
/// kicks off marketplace fetches against the unreachable prod URL).
Future<void> dismissWizardR3(WidgetTester tester) async {
  int guard = 0;
  while (!presentR3(find.byIcon(Icons.close), tester) && guard < 60) {
    await tester.pump(const Duration(milliseconds: 200));
    guard++;
  }
  if (presentR3(find.byIcon(Icons.close), tester)) {
    await tester.tap(find.byIcon(Icons.close).first);
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}
