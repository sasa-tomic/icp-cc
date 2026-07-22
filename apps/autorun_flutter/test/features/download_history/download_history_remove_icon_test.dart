// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/screens/download_history_screen.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';

/// CR-4: each download-history row's trailing widget was a `PopupMenuButton`
/// with exactly ONE item ("Remove from history"). A single-item popup costs
/// two taps (open menu + pick item). Replaced with a direct trash IconButton
/// that opens the same confirm dialog — one tap.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DownloadHistoryService().clearHistory();
  });

  testWidgets(
      'CR-4: row trailing is a direct remove IconButton (no single-item popup) '
      'that opens the confirm dialog on tap', (tester) async {
    await DownloadHistoryService().addToHistory(
      marketplaceScriptId: 'mp-cr4',
      title: 'Removable Script',
      authorName: 'Author',
      localScriptId: 'local-cr4',
    );

    final controller = ScriptController(MockScriptRepository());
    await controller.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(home: DownloadHistoryScreen(scriptController: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Removable Script'), findsOneWidget);

    // The single-item PopupMenuButton is gone.
    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'a 1-item popup should be a direct IconButton');

    // A direct trash IconButton with an accessible tooltip is present.
    final removeBtn = find.byTooltip('Remove from history');
    expect(removeBtn, findsOneWidget);

    // Tapping it opens the SAME confirm dialog the popup used to.
    await tester.tap(removeBtn);
    await tester.pumpAndSettle();

    expect(find.text('Remove from history'), findsWidgets);
    expect(find.textContaining('Remove "Removable Script"'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });
}
