import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('POC: Simplified Scripts View - Unit Tests', () {
    late ScriptRecord localScript;
    late MarketplaceScript marketplaceScript;

    setUp(() {
      final now = DateTime.now().toUtc();

      localScript = ScriptRecord(
        id: 'local-1',
        title: 'My Script',
        emoji: '📜',
        bundle: 'return 1',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 1)),
        metadata: {},
      );

      marketplaceScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Marketplace Script',
        description: 'A marketplace script',
        category: 'Utilities',
        bundle: 'return 2',
        authorName: 'Author',
        version: '1.0.0',
        downloads: 500,
        rating: 4.8,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );
    });

    test('POC: createHybridList merges local and marketplace scripts', () {
      final items = ScriptListItem.createHybridList(
        localScripts: [localScript],
        marketplaceScripts: [marketplaceScript],
        installedMarketplaceIds: {},
      );

      expect(items.length, equals(2));
      expect(items.any((i) => i.source == ScriptSource.local), isTrue);
      expect(items.any((i) => i.source == ScriptSource.marketplace), isTrue);
    });

    test('POC: new user sees marketplace scripts without local scripts', () {
      final items = ScriptListItem.createHybridList(
        localScripts: [],
        marketplaceScripts: [marketplaceScript],
        installedMarketplaceIds: {},
      );

      expect(items.length, equals(1));
      expect(items.first.source, equals(ScriptSource.marketplace));
    });

    test('POC: user with scripts sees both sources in unified list', () {
      final items = ScriptListItem.createHybridList(
        localScripts: [localScript],
        marketplaceScripts: [marketplaceScript],
        installedMarketplaceIds: {},
      );

      final localItems =
          items.where((i) => i.source == ScriptSource.local).toList();
      final marketplaceItems =
          items.where((i) => i.source == ScriptSource.marketplace).toList();

      expect(localItems.length, equals(1));
      expect(marketplaceItems.length, equals(1));
    });
  });

  group('Simplified Scripts View - Widget Tests', () {
    testWidgets('SegmentedButton is NOT present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(SegmentedButton), findsNothing,
          reason: 'SegmentedButton should be removed entirely');
    });

    testWidgets('No section headers with counts visible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('My Scripts'), findsNothing,
          reason: 'Section header "My Scripts" should not be visible');
      expect(find.text('Marketplace'), findsNothing,
          reason: 'Section header "Marketplace" should not be visible');
    });

    testWidgets('Search and filter controls remain', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('FAB for creating scripts remains', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectivityScope(
            child: ScriptsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });
}
