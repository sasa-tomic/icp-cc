import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/widgets/scripts_list_item_tile.dart';

/// Tests for the browse/list tile leading avatar (IH-6 / UXR-4).
///
/// Marketplace scripts carry an author-set `iconUrl` image; the tile must
/// render that image (not the generic 📦) when present, and fall back to the
/// emoji on a missing iconUrl or a failed image load.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  MarketplaceScript marketplaceScript({
    String? iconUrl,
  }) =>
      MarketplaceScript(
        id: 'mp-1',
        title: 'Marketplace Script',
        description: 'desc',
        category: 'Tools',
        iconUrl: iconUrl,
        bundle: 'print(1)',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

  testWidgets(
    'marketplace item WITH iconUrl renders a CachedNetworkImage (not the emoji)',
    (tester) async {
      final item = ScriptListItem.fromMarketplace(
        marketplaceScript(iconUrl: 'https://example.com/icon.png'),
      );

      await tester.pumpWidget(wrap(ScriptsListItemTile(item: item)));

      final cni = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(cni, isNotNull);
      expect(cni.imageUrl, 'https://example.com/icon.png');
      // The placeholder shows while loading; assert it falls back to the 📦
      // emoji, not a blank/spinner.
      expect(find.text('📦'), findsOneWidget);
    },
  );

  testWidgets(
    'marketplace item WITHOUT iconUrl renders the 📦 emoji fallback (no image widget)',
    (tester) async {
      final item =
          ScriptListItem.fromMarketplace(marketplaceScript(iconUrl: null));

      await tester.pumpWidget(wrap(ScriptsListItemTile(item: item)));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('📦'), findsOneWidget);
    },
  );

  testWidgets(
    'marketplace item with EMPTY iconUrl also renders the emoji fallback',
    (tester) async {
      final item =
          ScriptListItem.fromMarketplace(marketplaceScript(iconUrl: ''));

      await tester.pumpWidget(wrap(ScriptsListItemTile(item: item)));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('📦'), findsOneWidget);
    },
  );

  testWidgets(
    'local script (no emoji) renders the 📜 fallback',
    (tester) async {
      final record = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        bundle: 'print(1)',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      final item = ScriptListItem.fromLocal(record);

      await tester.pumpWidget(wrap(ScriptsListItemTile(item: item)));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('📜'), findsOneWidget);
    },
  );

  testWidgets(
    'icon image load failure surfaces the emoji fallback (errorWidget path)',
    (tester) async {
      const url = 'https://broken.example/icon.png';
      final item =
          ScriptListItem.fromMarketplace(marketplaceScript(iconUrl: url));

      await tester.pumpWidget(wrap(ScriptsListItemTile(item: item)));

      // Exercise the errorWidget builder directly — deterministic, no network.
      // This proves a failed load degrades to the emoji rather than a broken
      // image icon.
      final cni = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      final errorWidget =
          cni.errorWidget!(tester.element(find.byType(CachedNetworkImage)), url,
              Exception('load failed'));

      await tester.pumpWidget(wrap(Material(child: errorWidget)));

      expect(find.text('📦'), findsOneWidget);
    },
  );
}
