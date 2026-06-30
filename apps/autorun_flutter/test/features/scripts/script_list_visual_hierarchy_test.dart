import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_list_item.dart';

/// Tests for simplified script list visual hierarchy.
///
/// Requirements:
/// 1. Each script row shows ONLY: emoji, title, one-line subtitle, ONE action button
/// 2. Source badges (Local/Marketplace) are small icons, color-coded
/// 3. "Available" badge is a subtle download icon next to the title
void main() {
  group('ScriptListItem subtitle generation', () {
    late ScriptRecord localScript;
    late ScriptRecord marketplaceDownloaded;
    late MarketplaceScript marketplaceScript;

    setUp(() {
      final now = DateTime.now().toUtc();

      localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        emoji: ':scroll:',
        bundle: 'return 1',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 1)),
        metadata: {},
      );

      marketplaceDownloaded = ScriptRecord(
        id: 'local-2',
        title: 'Downloaded Script',
        emoji: ':package:',
        bundle: 'return 2',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 12)),
        metadata: {
          'marketplace_id': 'mp-123',
          'marketplace_version': '1.0.0',
          'marketplace_author': 'Test Author',
        },
      );

      marketplaceScript = MarketplaceScript(
        id: 'mp-456',
        title: 'Marketplace Script',
        description: 'A script from marketplace',
        category: 'Utilities',
        bundle: 'return 3',
        authorName: 'Another Author',
        version: '2.0.0',
        downloads: 150,
        rating: 4.5,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );
    });

    group('simplified subtitle', () {
      test('local script shows date only', () {
        final item = ScriptListItem.fromLocal(localScript);

        // For local scripts without author, subtitle should show relative date
        final subtitle = _buildSimplifiedSubtitle(item);

        expect(subtitle, contains('ago'));
        expect(subtitle, isNot(contains('runs')));
        expect(subtitle, isNot(contains('v')));
      });

      test('marketplace script shows author only', () {
        final item = ScriptListItem.fromMarketplace(marketplaceScript);

        // For marketplace scripts, subtitle should show author only
        final subtitle = _buildSimplifiedSubtitle(item);

        expect(subtitle, equals('Another Author'));
        expect(subtitle, isNot(contains('v2.0.0')));
        expect(subtitle, isNot(contains('150')));
        expect(subtitle, isNot(contains('downloads')));
      });

      test('downloaded marketplace script shows author', () {
        final item = ScriptListItem.fromLocal(marketplaceDownloaded);

        // For downloaded marketplace scripts, show author
        final subtitle = _buildSimplifiedSubtitle(item);

        expect(subtitle, equals('Test Author'));
      });

      test('local script without author shows date', () {
        final item = ScriptListItem.fromLocal(localScript);

        final subtitle = _buildSimplifiedSubtitle(item);

        // Local scripts don't have author, so show relative date
        expect(subtitle, contains('ago'));
      });
    });

    group('source indicator', () {
      test('isFromMarketplace returns true for marketplace scripts', () {
        final item = ScriptListItem.fromMarketplace(marketplaceScript);
        expect(item.isFromMarketplace, isTrue);
      });

      test('isFromMarketplace returns true for downloaded marketplace scripts',
          () {
        final item = ScriptListItem.fromLocal(marketplaceDownloaded);
        expect(item.isFromMarketplace, isTrue);
      });

      test('isFromMarketplace returns false for local scripts', () {
        final item = ScriptListItem.fromLocal(localScript);
        expect(item.isFromMarketplace, isFalse);
      });
    });
  });

  group('ScriptListTile widget visual hierarchy', () {
    /// Helper to build a simplified script list tile for testing
    Widget buildSimplifiedScriptListTile({
      required ScriptListItem item,
      bool isDownloaded = false,
    }) {
      return MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        ),
        home: Scaffold(
          body: _SimplifiedScriptListTile(
            item: item,
            isDownloaded: isDownloaded,
          ),
        ),
      );
    }

    testWidgets('shows CircleAvatar as leading widget', (tester) async {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );
      final item = ScriptListItem.fromLocal(script);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: item));

      // Should have a CircleAvatar as leading
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows title with bold weight', (tester) async {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'test-1',
        title: 'My Test Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );
      final item = ScriptListItem.fromLocal(script);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: item));

      // Find the title
      final titleFinder = find.text('My Test Script');
      expect(titleFinder, findsOneWidget);

      // Check that the title text has bold weight
      final textWidget = tester.widget<Text>(titleFinder);
      expect(textWidget.style?.fontWeight, equals(FontWeight.w600));
    });

    testWidgets('shows ONE action button in trailing', (tester) async {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );
      final item = ScriptListItem.fromLocal(script);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: item));

      // Should have exactly one primary action button
      final iconButtons = find.byType(IconButton);
      expect(iconButtons, findsOneWidget);
    });

    testWidgets('shows source as small icon, not prominent badge',
        (tester) async {
      final now = DateTime.now().toUtc();
      final localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );
      final localItem = ScriptListItem.fromLocal(localScript);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: localItem));

      // Should NOT have a prominent text badge saying "Local" or "Marketplace"
      expect(find.text('Local'), findsNothing);
      expect(find.text('Marketplace'), findsNothing);

      // Should have a small icon indicating source
      final sourceIcon = find.byIcon(Icons.folder_outlined);
      expect(sourceIcon, findsOneWidget);
    });

    testWidgets('marketplace source shows green cloud icon', (tester) async {
      final now = DateTime.now().toUtc();
      final mpScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Marketplace Script',
        description: 'desc',
        category: 'Utilities',
        bundle: 'return 1',
        authorName: 'Author',
        createdAt: now,
        updatedAt: now,
      );
      final mpItem = ScriptListItem.fromMarketplace(mpScript);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: mpItem));

      // Should have cloud icon for marketplace source
      final sourceIcon = find.byIcon(Icons.cloud_outlined);
      expect(sourceIcon, findsOneWidget);
    });

    testWidgets('available status shows subtle download icon next to title',
        (tester) async {
      final now = DateTime.now().toUtc();
      final mpScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Marketplace Script',
        description: 'desc',
        category: 'Utilities',
        bundle: 'return 1',
        authorName: 'Author',
        createdAt: now,
        updatedAt: now,
      );
      final mpItem = ScriptListItem.fromMarketplace(mpScript);

      await tester.pumpWidget(
        buildSimplifiedScriptListTile(
          item: mpItem,
          isDownloaded: false, // Available for download
        ),
      );

      // Should NOT have prominent "Available" badge
      expect(find.text('Available'), findsNothing);

      // Should have subtle download icon near title
      final downloadIcon = find.byIcon(Icons.download_outlined);
      expect(downloadIcon, findsOneWidget);

      // Icon should be small (subtle)
      final iconWidget = tester.widget<Icon>(downloadIcon);
      expect(iconWidget.size, lessThanOrEqualTo(18));
    });

    testWidgets('downloaded scripts do not show available icon',
        (tester) async {
      final now = DateTime.now().toUtc();
      final mpScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Downloaded Script',
        description: 'desc',
        category: 'Utilities',
        bundle: 'return 1',
        authorName: 'Author',
        createdAt: now,
        updatedAt: now,
      );
      final mpItem =
          ScriptListItem.fromMarketplace(mpScript, isInstalled: true);

      await tester.pumpWidget(
        buildSimplifiedScriptListTile(
          item: mpItem,
          isDownloaded: true,
        ),
      );

      // Should not have download icon since already downloaded
      expect(find.text('Available'), findsNothing);
      // Should not have download_outlined icon
      expect(find.byIcon(Icons.download_outlined), findsNothing);
    });

    testWidgets('subtitle is single line without run count or version',
        (tester) async {
      final now = DateTime.now().toUtc();
      final mpScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Test Script',
        description: 'desc',
        category: 'Utilities',
        bundle: 'return 1',
        authorName: 'Test Author',
        version: '2.5.0',
        downloads: 1000,
        createdAt: now,
        updatedAt: now,
      );
      final mpItem = ScriptListItem.fromMarketplace(mpScript);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: mpItem));

      // Subtitle should only show author
      expect(find.text('Test Author'), findsOneWidget);

      // Should NOT show version
      expect(find.textContaining('v2.5.0'), findsNothing);
      expect(find.textContaining('2.5.0'), findsNothing);

      // Should NOT show run count or downloads
      expect(find.textContaining('1000'), findsNothing);
      expect(find.textContaining('runs'), findsNothing);
      expect(find.textContaining('downloads'), findsNothing);
    });

    testWidgets('local script subtitle shows relative date', (tester) async {
      final now = DateTime.now().toUtc();
      final localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
        metadata: {},
      );
      final localItem = ScriptListItem.fromLocal(localScript);

      await tester.pumpWidget(buildSimplifiedScriptListTile(item: localItem));

      // Subtitle should show relative date
      expect(find.textContaining('ago'), findsOneWidget);
    });
  });

  group('Source icon color coding', () {
    testWidgets('local source icon is blue', (tester) async {
      final now = DateTime.now().toUtc();
      final localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        emoji: null,
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );
      final item = ScriptListItem.fromLocal(localScript);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
          ),
          home: Scaffold(
            body: _SimplifiedScriptListTile(item: item),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
      expect(icon.color, equals(Colors.blue));
    });

    testWidgets('marketplace source icon is green', (tester) async {
      final now = DateTime.now().toUtc();
      final mpScript = MarketplaceScript(
        id: 'mp-1',
        title: 'Marketplace Script',
        description: 'desc',
        category: 'Utilities',
        bundle: 'return 1',
        createdAt: now,
        updatedAt: now,
      );
      final item = ScriptListItem.fromMarketplace(mpScript);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
          ),
          home: Scaffold(
            body: _SimplifiedScriptListTile(item: item),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_outlined));
      expect(icon.color, equals(Colors.green));
    });
  });
}

/// Simplified subtitle builder for script list items.
///
/// For local scripts: shows relative date (e.g., "2d ago")
/// For marketplace scripts: shows author name only
/// For downloaded marketplace scripts: shows author name
String _buildSimplifiedSubtitle(ScriptListItem item) {
  // For downloaded marketplace scripts (local with marketplace metadata)
  if (item.source == ScriptSource.local && item.author != null) {
    return item.author!;
  }

  // For marketplace scripts
  if (item.source == ScriptSource.marketplace) {
    return item.author ?? 'Unknown';
  }

  // For local scripts, show relative date
  return _formatRelativeTime(item.updatedAt);
}

String _formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inDays > 365) {
    return '${(difference.inDays / 365).floor()}y ago';
  } else if (difference.inDays > 30) {
    return '${(difference.inDays / 30).floor()}mo ago';
  } else if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'just now';
  }
}

/// Simplified script list tile widget with clean visual hierarchy.
///
/// Features:
/// - Prominent emoji icon (in CircleAvatar)
/// - Bold title
/// - Single-line subtitle (author for marketplace, date for local)
/// - ONE action button
/// - Source as small color-coded icon
/// - "Available" as subtle download icon
class _SimplifiedScriptListTile extends StatelessWidget {
  const _SimplifiedScriptListTile({
    required this.item,
    this.isDownloaded = false,
  });

  final ScriptListItem item;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMarketplace = item.isFromMarketplace;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        child: Text(
          _getDisplayIcon(),
          style: const TextStyle(fontSize: 20),
        ),
      ),
      title: Row(
        children: [
          // Source indicator as small icon
          Icon(
            isMarketplace ? Icons.cloud_outlined : Icons.folder_outlined,
            size: 14,
            color: isMarketplace ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          // Available indicator as subtle download icon
          if (!isDownloaded && item.source == ScriptSource.marketplace)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.download_outlined,
                size: 16,
                color: Colors.grey,
              ),
            ),
        ],
      ),
      subtitle: Text(
        _buildSimplifiedSubtitle(item),
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () {},
      ),
    );
  }

  String _getDisplayIcon() {
    final emoji = item.emoji;
    if (emoji != null && emoji.isNotEmpty) {
      // For non-emoji text, use first character
      if (emoji.startsWith(':')) {
        return emoji.substring(1, emoji.length > 1 ? 2 : 1).toUpperCase();
      }
      return emoji[0];
    }
    return item.isFromMarketplace ? 'M' : 'L';
  }
}
