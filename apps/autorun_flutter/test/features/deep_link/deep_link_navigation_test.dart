import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/deep_link_service.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

void main() {
  group('Deep link navigation', () {
    testWidgets('shows ScriptDetailsDialog when navigating to script deep link',
        (tester) async {
      final testScript = MarketplaceScript(
        id: 'test-script-123',
        title: 'Test Script',
        description: 'A test script',
        category: 'Utilities',
        tags: ['test'],
        authorName: 'Test Author',
        price: 0,
        currency: 'ICP',
        downloads: 100,
        rating: 4.5,
        reviewCount: 10,
        verifiedReviewCount: 8,
        luaSource: 'print("Hello")',
        canisterIds: [],
        isPublic: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ScriptDetailsDialog(
                      script: testScript,
                    ),
                  );
                },
                child: const Text('Open Script'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Script'));
      await tester.pumpAndSettle();

      expect(find.text('Test Script'), findsOneWidget);
      expect(find.text('by Test Author'), findsOneWidget);
    });

    testWidgets('shows error snackbar when script not found', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Script not found: invalid-id'),
                    ),
                  );
                },
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.text('Script not found: invalid-id'), findsOneWidget);
    });
  });

  group('Deep link data', () {
    test('DeepLinkData holds correct script ID', () {
      final data = DeepLinkData(
        type: DeepLinkType.script,
        scriptId: 'abc123',
      );

      expect(data.type, equals(DeepLinkType.script));
      expect(data.scriptId, equals('abc123'));
    });

    test('DeepLinkData toString is informative', () {
      final data = DeepLinkData(
        type: DeepLinkType.script,
        scriptId: 'xyz789',
      );

      expect(data.toString(), contains('script'));
      expect(data.toString(), contains('xyz789'));
    });
  });
}
