import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('Publish button visibility', () {
    late ScriptRecord localScript;
    late ScriptRecord marketplaceScript;

    setUp(() {
      localScript = ScriptRecord(
        id: 'local-1',
        title: 'My Local Script',
        emoji: '📜',
        luaSource: 'return 1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {},
      );

      marketplaceScript = ScriptRecord(
        id: 'mp-1',
        title: 'Downloaded Script',
        luaSource: 'return 2',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        metadata: {
          'marketplace_id': 'mp-123',
        },
      );
    });

    test('Local script is not from marketplace', () {
      expect(localScript.isFromMarketplace, isFalse);
    });

    test('Marketplace script has marketplace_id', () {
      expect(marketplaceScript.isFromMarketplace, isTrue);
    });

    test('Can publish returns true for local scripts only', () {
      final canPublishLocal = !localScript.isFromMarketplace;
      final canPublishMarketplace = !marketplaceScript.isFromMarketplace;

      expect(canPublishLocal, isTrue);
      expect(canPublishMarketplace, isFalse);
    });

    testWidgets('Share is in overflow menu (not inline) on local script row',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalScriptRowTest(
              script: localScript,
              onPublish: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // No inline share button
      expect(find.byIcon(Icons.share), findsNothing);
      // Play button and overflow menu are visible
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Open overflow menu to find Share
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Share to Marketplace'), findsOneWidget);
    });

    testWidgets('Share NOT in overflow menu for marketplace script row',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalScriptRowTest(
              script: marketplaceScript,
              onPublish: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Open overflow menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // No Share to Marketplace option for already-published scripts
      expect(find.text('Share to Marketplace'), findsNothing);
    });

    testWidgets('Share in overflow menu triggers publish callback',
        (tester) async {
      var publishCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalScriptRowTest(
              script: localScript,
              onPublish: () {
                publishCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Open overflow menu and tap Share to Marketplace
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share to Marketplace'));
      await tester.pump();

      expect(publishCalled, isTrue);
    });
  });

  group('Share banner', () {
    testWidgets('Banner appears when user has unpublishable local scripts',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShareBannerTest(
              hasUnpublishableScripts: true,
              isDismissed: false,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Share your first script!'), findsOneWidget);
    });

    testWidgets('Banner does not appear when dismissed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShareBannerTest(
              hasUnpublishableScripts: true,
              isDismissed: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Share your first script!'), findsNothing);
    });

    testWidgets('Banner does not appear when no unpublishable scripts',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShareBannerTest(
              hasUnpublishableScripts: false,
              isDismissed: false,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Share your first script!'), findsNothing);
    });

    testWidgets('Banner has Share button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareBannerTest(
              hasUnpublishableScripts: true,
              isDismissed: false,
              onShare: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.widgetWithText(TextButton, 'Share'), findsOneWidget);
    });

    testWidgets('Banner has Dismiss button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareBannerTest(
              hasUnpublishableScripts: true,
              isDismissed: false,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.widgetWithText(TextButton, 'Dismiss'), findsOneWidget);
    });
  });
}

class LocalScriptRowTest extends StatelessWidget {
  const LocalScriptRowTest({
    super.key,
    required this.script,
    required this.onPublish,
  });

  final ScriptRecord script;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final canPublish = !script.isFromMarketplace;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PRIMARY ACTION: Play button only
        IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () {},
          tooltip: 'Run script',
        ),
        // OVERFLOW MENU: All secondary actions including Share to Marketplace
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'publish') {
              onPublish();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text('Edit'),
            ),
            const PopupMenuItem(
              value: 'duplicate',
              child: Text('Duplicate'),
            ),
            if (canPublish)
              const PopupMenuItem(
                value: 'publish',
                child: Text('Share to Marketplace'),
              ),
            const PopupMenuItem(
              value: 'export',
              child: Text('Copy Source'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class ShareBannerTest extends StatelessWidget {
  const ShareBannerTest({
    super.key,
    required this.hasUnpublishableScripts,
    required this.isDismissed,
    this.onShare,
    this.onDismiss,
  });

  final bool hasUnpublishableScripts;
  final bool isDismissed;
  final VoidCallback? onShare;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!hasUnpublishableScripts || isDismissed) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Share your first script!'),
                Text('Help others by sharing your scripts to the marketplace.'),
              ],
            ),
          ),
          TextButton(
            onPressed: onShare,
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
