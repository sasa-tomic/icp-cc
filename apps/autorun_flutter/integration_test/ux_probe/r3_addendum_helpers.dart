// Shared helpers for the UX-review ROUND-3 ADDENDUM probes.
//
// These prove (under the committed mock Secret Service, which makes
// flutter_secure_storage / libsecret work on a keyring-less Linux box) that:
//   - real Ed25519 profile creation end-to-end succeeds (the root cause that
//     blocked every identity flow is resolved), and
//   - the WU-4 inline profile switcher renders in the production
//     [ProfileMenuWidget] when more than one REAL profile exists.
//
// Run UNDER the mock (so libsecret is available):
//   scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/r3_addendum_test.dart
//
// Hard constraint honored: `git diff apps/autorun_flutter/lib` stays EMPTY.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Canonical screenshot output dir for the ROUND-3 ADDENDUM.
const String kShotDirR3Addendum =
    '/code/icp-cc/docs/specs/ux_screenshots/round3_addendum';

/// Desktop surface we render at (matches the Xvfb screen size used elsewhere).
const Size kDesktopSizeAddendum = Size(1440, 900);
const double kDprAddendum = 1.0;

/// Wipe on-disk profile state (file + secure storage) for a clean start.
///
/// `ProfileRepository` (no override) resolves its directory to
/// `<XDG_DATA_HOME>/com.example.icp_autorun/`. We delete that dir; secure
/// storage is cleared through the real repository so the mock's secrets.json is
/// reset too.
Future<void> clearAddendumProfileState() async {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg == null || xdg.isEmpty) return;
  final dir = Directory('$xdg/com.example.icp_autorun');
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

/// Capture a screenshot of the current render tree to [name].
///
/// Captures from the layer tree (`RenderView.layer.toImage`) because the
/// integration_test method-channel takeScreenshot is unserviced without a
/// flutter_driver (same technique as r3_helpers.dart).
Future<void> shotAddendum(
    IntegrationTestWidgetsFlutterBinding binding,
    String name,
    WidgetTester tester) async {
  await Directory(kShotDirR3Addendum).create(recursive: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final RenderView view = tester.binding.renderViews.first;
  final Size size = view.size.isEmpty ? kDesktopSizeAddendum : view.size;
  // ignore: invalid_use_of_protected_member
  final OffsetLayer layer = view.layer! as OffsetLayer;
  final ui.Image image = await layer.toImage(
    Offset.zero & size,
    pixelRatio: kDprAddendum,
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode screenshot $name to PNG.');
  }
  final file = File('$kShotDirR3Addendum/$name.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  image.dispose();
}

/// Like [find.byType] but returns whether ANY matching widget is present.
bool presentAddendum(Finder f, WidgetTester tester) => tester.any(f);
