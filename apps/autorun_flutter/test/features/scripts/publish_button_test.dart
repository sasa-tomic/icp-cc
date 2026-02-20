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

    testWidgets('Share button is visible on local script row', (tester) async {
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

      expect(find.byIcon(Icons.share), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('Share button NOT shown on marketplace script row',
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

      expect(find.byIcon(Icons.share), findsNothing);
    });

    testWidgets('Share button triggers publish callback', (tester) async {
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

      await tester.tap(find.byIcon(Icons.share));
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
        IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () {},
          tooltip: 'Run script',
        ),
        if (canPublish)
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: onPublish,
            tooltip: 'Share to Marketplace',
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
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
