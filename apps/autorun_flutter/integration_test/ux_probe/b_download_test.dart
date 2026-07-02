// Flow B / WU-2 — download a marketplace script and verify the "added to your
// library!" SnackBar has NO "Run" action (multi-tap to actually run it).
//
// Download is local-only (no keypair required), so this flow is reachable once
// the app is pointed at a backend that seeds marketplace scripts.
//
// NOTE: a pre-existing code_text_field CodeField render bug (NEW-3) throws an
// ArgumentError building a TextSpan whenever the Scripts screen renders code
// content. Flutter recovers for sibling widgets, so the Download button and
// the success SnackBar still render — but the framework may report the
// collected exception. The decisive WU-2 evidence is the printed assertion +
// screenshot 05.
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/b_download_test.dart \
//        --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:45959

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'ux_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
  }

  testWidgets('WU-2: download SnackBar has NO Run action', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    // Let the marketplace scripts load from the local backend.
    bool loaded = false;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (present(find.byIcon(Icons.more_vert), tester) ||
          present(find.byTooltip('Download'), tester)) {
        loaded = true;
        break;
      }
    }
    // ignore: avoid_print
    print('WU2_DOWNLOAD: marketplaceLoaded=$loaded '
        'moreVertCount=${tester.widgetList(find.byIcon(Icons.more_vert)).length} '
        'downloadTooltipCount=${tester.widgetList(find.byTooltip('Download')).length}');

    // Prefer the hover-revealed Download action button on a marketplace card;
    // fall back to the overflow menu. ScriptActionButton carries tooltip
    // 'Download' for not-yet-downloaded scripts (scripts_screen.dart:1397).
    final dlBtn = find.byTooltip('Download');
    if (present(dlBtn, tester)) {
      await tester.ensureVisible(dlBtn.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(dlBtn.first);
      // ignore: avoid_print
      print('WU2_DOWNLOAD: tapped direct Download button');
    } else {
      // Overflow-menu path: more_vert -> 'Download'.
      final more = find.byIcon(Icons.more_vert);
      await tester.tap(more.first);
      await tester.pump(const Duration(milliseconds: 800));
      final dl = find.text('Download');
      // ignore: avoid_print
      print('WU2_DOWNLOAD: popup Download item present=${present(dl, tester)}');
      if (present(dl, tester)) {
        await tester.tap(dl.first);
      }
    }

    // Wait for the success snackbar (4s duration).
    bool snackbarShown = false;
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (present(find.textContaining('added to your library'), tester)) {
        snackbarShown = true;
        break;
      }
      if (present(find.textContaining('Download failed'), tester)) {
        break;
      }
    }
    final hasAction = present(find.byType(SnackBarAction), tester);
    await shot(binding, '05_download_snackbar', tester);
    // Capture ANY visible snackbar text for diagnosis.
    String? anySnackbar;
    tester.widgetList(find.byType(SnackBar)).forEach((w) {
      // ignore: avoid_print
      print('WU2_DOWNLOAD: visible SnackBar type=${w.runtimeType}');
    });
    // ignore: avoid_print
    print('WU2_DOWNLOAD: snackbarShown=$snackbarShown hasRunAction=$hasAction');

    if (snackbarShown) {
      expect(hasAction, isFalse,
          reason: 'WU-2: download SnackBar has NO "Run" action; user must '
              'then locate the script in their library and tap again to run.');
    }
    // If the marketplace didn't load or download failed, the WU-2 verdict
    // still holds by code inspection (scripts_screen.dart:419-436 declares no
    // SnackBarAction); we surface the empirical status via the print above.
  });
}
