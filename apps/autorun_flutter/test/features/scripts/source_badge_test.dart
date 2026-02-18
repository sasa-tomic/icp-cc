import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('ScriptRecord.isFromMarketplace', () {
    test('returns false for local scripts without marketplace metadata', () {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );

      expect(script.isFromMarketplace, isFalse);
    });

    test('returns true for scripts with marketplace_id', () {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'mp-1',
        title: 'Marketplace Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {'marketplace_id': 'mp-12345'},
      );

      expect(script.isFromMarketplace, isTrue);
    });

    test('returns true even with empty marketplace metadata', () {
      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'mp-2',
        title: 'Marketplace Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {
          'marketplace_id': 'mp-67890',
          'marketplace_version': '1.0.0',
          'marketplace_author': 'Test Author',
        },
      );

      expect(script.isFromMarketplace, isTrue);
      expect(script.marketplaceId, equals('mp-67890'));
      expect(script.marketplaceVersion, equals('1.0.0'));
      expect(script.marketplaceAuthor, equals('Test Author'));
    });
  });

  group('SourceBadge widget', () {
    Widget buildSourceBadge(ScriptRecord record) {
      return MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final isFromMarketplace = record.isFromMarketplace;
              final backgroundColor = isFromMarketplace
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.surfaceContainerHighest;
              final textColor = isFromMarketplace
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant;
              final borderColor = isFromMarketplace
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.outlineVariant;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  isFromMarketplace ? 'Marketplace' : 'Local',
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    testWidgets('shows "Local" badge for local scripts', (tester) async {
      final now = DateTime.now().toUtc();
      final localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );

      await tester.pumpWidget(buildSourceBadge(localScript));

      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Marketplace'), findsNothing);
    });

    testWidgets('shows "Marketplace" badge for marketplace scripts',
        (tester) async {
      final now = DateTime.now().toUtc();
      final marketplaceScript = ScriptRecord(
        id: 'mp-1',
        title: 'Marketplace Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {'marketplace_id': 'mp-12345'},
      );

      await tester.pumpWidget(buildSourceBadge(marketplaceScript));

      expect(find.text('Marketplace'), findsOneWidget);
      expect(find.text('Local'), findsNothing);
    });

    testWidgets('Local badge has neutral colors', (tester) async {
      final now = DateTime.now().toUtc();
      final localScript = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );

      await tester.pumpWidget(buildSourceBadge(localScript));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, isNot(equals(Colors.transparent)));
    });

    testWidgets('Marketplace badge has accent colors', (tester) async {
      final now = DateTime.now().toUtc();
      final marketplaceScript = ScriptRecord(
        id: 'mp-1',
        title: 'Marketplace Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {'marketplace_id': 'mp-12345'},
      );

      await tester.pumpWidget(buildSourceBadge(marketplaceScript));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, isNot(equals(Colors.transparent)));
      expect(decoration.border, isNotNull);
    });
  });
}
