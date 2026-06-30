import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';

void main() {
  group('Section Separation', () {
    late ScriptRecord localScript1;
    late ScriptRecord localScript2;
    late MarketplaceScript marketplaceScript1;
    late MarketplaceScript marketplaceScript2;

    setUp(() {
      final now = DateTime.now().toUtc();

      localScript1 = ScriptRecord(
        id: 'local-1',
        title: 'My First Script',
        emoji: '📜',
        bundle: 'return 1',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 1)),
        metadata: {},
      );

      localScript2 = ScriptRecord(
        id: 'local-2',
        title: 'My Second Script',
        emoji: '🔬',
        bundle: 'return 2',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
        metadata: {},
      );

      marketplaceScript1 = MarketplaceScript(
        id: 'mp-1',
        title: 'Popular Utility',
        description: 'A popular utility script',
        category: 'Utilities',
        bundle: 'return 3',
        authorName: 'Script Author',
        version: '1.0.0',
        downloads: 500,
        rating: 4.8,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );

      marketplaceScript2 = MarketplaceScript(
        id: 'mp-2',
        title: 'Data Processor',
        description: 'Process data efficiently',
        category: 'Data',
        bundle: 'return 4',
        authorName: 'Another Author',
        version: '2.0.0',
        downloads: 250,
        rating: 4.5,
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 3)),
      );
    });

    group('ScriptListItem grouping', () {
      test('groups scripts by source correctly', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [localScript1, localScript2],
          marketplaceScripts: [marketplaceScript1, marketplaceScript2],
          installedMarketplaceIds: {},
        );

        final localItems =
            items.where((i) => i.source == ScriptSource.local).toList();
        final marketplaceItems =
            items.where((i) => i.source == ScriptSource.marketplace).toList();

        expect(localItems.length, equals(2));
        expect(marketplaceItems.length, equals(2));
      });

      test('handles empty local scripts section', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [],
          marketplaceScripts: [marketplaceScript1, marketplaceScript2],
          installedMarketplaceIds: {},
        );

        final localItems =
            items.where((i) => i.source == ScriptSource.local).toList();
        final marketplaceItems =
            items.where((i) => i.source == ScriptSource.marketplace).toList();

        expect(localItems.isEmpty, isTrue);
        expect(marketplaceItems.length, equals(2));
      });

      test('handles empty marketplace section', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [localScript1, localScript2],
          marketplaceScripts: [],
          installedMarketplaceIds: {},
        );

        final localItems =
            items.where((i) => i.source == ScriptSource.local).toList();
        final marketplaceItems =
            items.where((i) => i.source == ScriptSource.marketplace).toList();

        expect(localItems.length, equals(2));
        expect(marketplaceItems.isEmpty, isTrue);
      });

      test('handles both sections empty', () {
        final items = ScriptListItem.createHybridList(
          localScripts: [],
          marketplaceScripts: [],
          installedMarketplaceIds: {},
        );

        expect(items.isEmpty, isTrue);
      });
    });

    group('Section headers', () {
      testWidgets('renders section headers for My Scripts and Marketplace',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _TestSectionedListView(
              localScripts: [localScript1],
              marketplaceScripts: [marketplaceScript1],
            ),
          ),
        ));

        // Verify section headers are present
        expect(find.text('My Scripts'), findsOneWidget);
        expect(find.text('Marketplace'), findsOneWidget);

        // Verify script titles are present
        expect(find.text('My First Script'), findsOneWidget);
        expect(find.text('Popular Utility'), findsOneWidget);
      });

      testWidgets(
          'shows empty state for My Scripts section when only marketplace scripts exist',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _TestSectionedListView(
              localScripts: [],
              marketplaceScripts: [marketplaceScript1],
            ),
          ),
        ));

        // Both headers should still be visible
        expect(find.text('My Scripts'), findsOneWidget);
        expect(find.text('Marketplace'), findsOneWidget);

        // Empty state indicator for local section
        expect(find.text('No scripts yet'), findsOneWidget);
      });

      testWidgets(
          'shows empty state for Marketplace section when only local scripts exist',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _TestSectionedListView(
              localScripts: [localScript1],
              marketplaceScripts: [],
              isMarketplaceLoading: false,
            ),
          ),
        ));

        // Both headers should still be visible
        expect(find.text('My Scripts'), findsOneWidget);
        expect(find.text('Marketplace'), findsOneWidget);

        // Empty state indicator for marketplace section
        expect(find.text('No scripts available'), findsOneWidget);
      });

      testWidgets('shows loading indicator in Marketplace while loading',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _TestSectionedListView(
              localScripts: [localScript1],
              marketplaceScripts: [],
              isMarketplaceLoading: true,
            ),
          ),
        ));

        // Local section should show scripts
        expect(find.text('My First Script'), findsOneWidget);

        // Loading indicator should be visible
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });

    group('Section toggle', () {
      testWidgets('SegmentedButton allows switching between sections',
          (tester) async {
        int? selectedSection;

        await tester.pumpWidget(MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('All')),
                        ButtonSegment(value: 1, label: Text('My Scripts')),
                        ButtonSegment(value: 2, label: Text('Marketplace')),
                      ],
                      selected: {selectedSection ?? 0},
                      onSelectionChanged: (Set<int> selection) {
                        setState(() {
                          selectedSection = selection.first;
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ));

        // Default selection should be 'All'
        expect(find.widgetWithText(TextButton, 'All'), findsOneWidget);

        // Tap 'My Scripts' segment
        await tester.tap(find.text('My Scripts'));
        await tester.pumpAndSettle();
        expect(selectedSection, equals(1));

        // Tap 'Marketplace' segment
        await tester.tap(find.text('Marketplace'));
        await tester.pumpAndSettle();
        expect(selectedSection, equals(2));

        // Tap 'All' segment
        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        expect(selectedSection, equals(0));
      });
    });
  });
}

/// Test widget that simulates the sectioned list view with headers
class _TestSectionedListView extends StatelessWidget {
  const _TestSectionedListView({
    required this.localScripts,
    required this.marketplaceScripts,
    this.isMarketplaceLoading = false,
  });

  final List<ScriptRecord> localScripts;
  final List<MarketplaceScript> marketplaceScripts;
  final bool isMarketplaceLoading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // My Scripts Section
        _SectionHeader(title: 'My Scripts', icon: Icons.folder_outlined),
        if (localScripts.isEmpty)
          const _EmptySectionIndicator(message: 'No scripts yet')
        else
          ...localScripts.map((s) => ListTile(
                leading: CircleAvatar(child: Text(s.emoji ?? '📜')),
                title: Text(s.title),
              )),

        const Divider(height: 32),

        // Marketplace Section
        _SectionHeader(title: 'Marketplace', icon: Icons.cloud_outlined),
        if (isMarketplaceLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (marketplaceScripts.isEmpty)
          const _EmptySectionIndicator(message: 'No scripts available')
        else
          ...marketplaceScripts.map((s) => ListTile(
                leading: const CircleAvatar(child: Text('📦')),
                title: Text(s.title),
                subtitle: Text(s.authorName ?? 'Unknown'),
              )),
      ],
    );
  }
}

/// Section header widget for visual separation
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Empty section indicator
class _EmptySectionIndicator extends StatelessWidget {
  const _EmptySectionIndicator({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
        ),
      ),
    );
  }
}
