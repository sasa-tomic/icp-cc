// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/mock_script_repository.dart';
import '_scripts_test_harness.dart';

/// W6-9: downloaded marketplace scripts used to revert to the generic 📦 icon
/// because the local `ScriptRecord` created at download time never received
/// the marketplace `iconUrl` — so the installed tile's `iconUrl` getter
/// returned null and `ScriptsListItemTile` fell back to the emoji. The fix
/// persists `iconUrl` (and emoji) on the local record so installed scripts
/// keep their artwork.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'W6-9: downloading a marketplace script WITH an iconUrl persists the '
      'iconUrl on the local ScriptRecord', (tester) async {
    const iconUrl = 'https://example.com/scripts/icon.png';
    final mpScript = MarketplaceScript(
      id: 'mp-icon-1',
      title: 'Iconful Script',
      description: 'has artwork',
      category: 'Tools',
      authorName: 'Artist',
      iconUrl: iconUrl,
      price: 0,
      bundle: 'print(1)',
      version: '1.0.0',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
    );

    final repo = MockScriptRepository();
    final controller = ScriptController(repo);
    final marketplace = FakeMarketplaceOpenApi(scripts: [mpScript]);

    await pumpScriptsScreen(
      tester,
      controller: controller,
      marketplaceService: marketplace,
    );

    // The marketplace row appears.
    expect(find.text('Iconful Script'), findsOneWidget);

    // Trigger download via the row's overflow popup menu.
    await tester.tap(find.byTooltip('Show menu').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download').last);
    await tester.pumpAndSettle();

    // After download, the controller holds exactly one local script that
    // carries the marketplace iconUrl (the bug: it used to be null → 📦).
    final downloaded = controller.scripts;
    expect(downloaded, hasLength(1),
        reason: 'download should create exactly one local record');
    expect(downloaded.single.imageUrl, iconUrl,
        reason: 'the local record must persist the marketplace iconUrl so the '
            'installed tile keeps its artwork instead of reverting to 📦');
    expect(downloaded.single.isFromMarketplace, isTrue);
  });
}
