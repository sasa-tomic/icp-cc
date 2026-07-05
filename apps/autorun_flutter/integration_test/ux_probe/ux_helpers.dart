// Shared helpers for UX-review round-2 integration probes.
//
// These probes launch the REAL app (lib/main.dart) under the Flutter
// integration-test binding, drive interactive flows, capture screenshots
// directly into docs/specs/ux_screenshots/round2/, and assert behaviors that
// back the CONFIRM/REFUTE verdicts in docs/specs/UX_REVIEW_ROUND2.md.
//
// They intentionally exercise the production widget tree (no widget mocks) so
// the screenshots + assertions reflect what a user actually sees.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/main.dart' as app;

/// Canonical screenshot output dir (matches docs/specs layout).
const String kShotDir =
    '/code/icp-cc/docs/specs/ux_screenshots/round2';

/// Desktop surface we render at (matches the Xvfb screen size used for the
/// real-bundle screenshots).
const Size kDesktopSize = Size(1440, 900);
const double kDpr = 1.0;

/// Wipe on-disk profile state so the first-run gate fires.
///
/// Profile metadata lives at the `appSupport`/profiles.json path and secrets
/// live in FlutterSecureStorage. We can only reliably clear the file side here
/// (libsecret state is owned by the OS keyring); clearing the file is enough
/// to force `profiles.isEmpty` for a clean first-run.
///
/// path_provider's getApplicationSupportDirectory() on this Linux build
/// resolves to ~/.cache/data/com.example.icp_autorun/ (see r3_helpers.dart);
/// the legacy ~/.local/share/... path is cleared too for belt-and-suspenders.
Future<void> clearProfileState() async {
  final home = Platform.environment['HOME'] ?? '/tmp';
  // Primary: the path path_provider actually resolves to on Linux.
  final cacheDir = Directory('$home/.cache/data/com.example.icp_autorun');
  if (await cacheDir.exists()) {
    final profiles = File('${cacheDir.path}/profiles.json');
    if (await profiles.exists()) {
      await profiles.writeAsString('{"version":1,"profiles":[]}');
    }
  }
  // Legacy/alt path: clear wholesale if it ever exists.
  final alt = Directory('$home/.local/share/com.example.icp_autorun');
  if (await alt.exists()) {
    await alt.delete(recursive: true);
  }
}

/// Configure a desktop-sized rendering surface and launch the real app.
Future<void> launchApp(WidgetTester tester) async {
  tester.view.physicalSize = kDesktopSize * kDpr;
  tester.view.devicePixelRatio = kDpr;
  // Fake a "no connectivity" baseline so the app doesn't hang on network calls
  // during first-run probing; the wizard is fully local.
  await tester.runAsync(() async {
    app.main();
  });
  // Let async init (FFI load, profile load, theme load) complete.
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Capture a screenshot of the current render tree to [name] under kShotDir.
///
/// We render the live app on the Xvfb display but capture straight from the
/// layer tree (`RenderView.layer.toImage`) instead of the
/// `integration_test` method-channel `takeScreenshot`, because that channel is
/// only serviced when a flutter_driver is attached — which it isn't under a
/// plain `flutter test` run.
Future<void> shot(IntegrationTestWidgetsFlutterBinding binding, String name,
    WidgetTester tester) async {
  await Directory(kShotDir).create(recursive: true);
  // Force a fresh frame so the layer tree is current before we snapshot it.
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
  final file = File('$kShotDir/$name.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  image.dispose();
}

/// Like [find.byType] but returns whether ANY matching widget is present.
bool present(Finder f, WidgetTester tester) => tester.any(f);
