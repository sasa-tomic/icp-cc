import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/widgets/script_card.dart';

void main() {
  group('ScriptCard identity display', () {
    MarketplaceScript buildScript({
      String? principal,
      String authorName = 'Test Author',
      String authorId = 'author-12345',
      String title = 'Compact Test Script',
    }) {
      final now = DateTime.now();
      return MarketplaceScript(
        id: 'script-1',
        title: title,
        description: 'Test description',
        category: 'Utility',
        tags: const ['utility'],
        authorId: authorId,
        authorName: authorName,
        authorPrincipal: principal,
        authorPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        uploadSignature: 'c2lnbmF0dXJl',
        price: 0.0,
        currency: 'USD',
        downloads: 42,
        rating: 4.5,
        reviewCount: 10,
        luaSource: 'return {}',
        iconUrl: null,
        screenshots: const [],
        canisterIds: const [],
        compatibility: null,
        version: '1.0.0',
        isPublic: true,
        createdAt: now,
        updatedAt: now,
      );
    }

    testWidgets('renders principal prefix when signature metadata is present', (tester) async {
      final script = buildScript(principal: 'aaaaa-aa');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: ScriptCard(
                  script: script,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('aaaaa...'), findsOneWidget,
          reason: 'Principal prefix should be derived from authorPrincipal');
      expect(find.text('UNVERIFIED SIGNATURE'), findsNothing,
          reason: 'Verified scripts must not display unverified badge');
    });

    testWidgets('highlights unverified signature state when principal is missing', (tester) async {
      final now = DateTime.now();
      MarketplaceScript scriptWithoutPrincipal = MarketplaceScript(
        id: 'script-2',
        title: 'Unsigned Script',
        description: 'Test description',
        category: 'Utility',
        tags: const ['utility'],
        authorId: 'anonymous',
        authorName: 'Unknown',
        authorPrincipal: null,
        authorPublicKey: null, // No public key to trigger unverified state
        uploadSignature: null,
        price: 0.0,
        currency: 'USD',
        downloads: 42,
        rating: 4.5,
        reviewCount: 10,
        luaSource: 'return {}',
        iconUrl: null,
        screenshots: const [],
        canisterIds: const [],
        compatibility: null,
        version: '1.0.0',
        isPublic: true,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: ScriptCard(
                  script: scriptWithoutPrincipal,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('UNVERIFIED SIGNATURE'), findsOneWidget,
          reason: 'Scripts without principals must clearly show unverified status');
    });
  });
}
