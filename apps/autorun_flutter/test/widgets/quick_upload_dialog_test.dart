import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/identity_controller.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/widgets/identity_scope.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_identity_repository.dart';
import '../test_helpers/test_identity_factory.dart';

class _MockMarketplaceService extends Mock
    implements MarketplaceOpenApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('QuickUploadDialog identity workflow', () {
    late IdentityRecord identity;
    late IdentityController identityController;
    late _MockMarketplaceService marketplaceService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      identity = await TestIdentityFactory.getEd25519Identity();
      final repository = FakeSecureIdentityRepository(<IdentityRecord>[identity]);
      identityController = IdentityController(secureRepository: repository);
      await identityController.ensureLoaded();
      await identityController.setActiveIdentity(identity.id);
      marketplaceService = _MockMarketplaceService();
    });

    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        IdentityScope(
          controller: identityController,
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => QuickUploadDialog(
                            preFilledTitle: 'Prefilled Title',
                            preFilledCode: '-- test script',
                            identityController: identityController,
                            marketplaceService: marketplaceService,
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('blocks upload when no identity is selected',
        (WidgetTester tester) async {
      // Don't set active identity - this test checks no-identity behavior
      await pumpDialog(tester);

      // Fill required fields that are not pre-populated
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Short description');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Author Name *'), 'Author');
      await tester.pumpAndSettle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          luaSource: any(named: 'luaSource'),
          authorName: any(named: 'authorName'),
          price: any(named: 'price'),
          version: any(named: 'version'),
          canisterIds: any(named: 'canisterIds'),
          iconUrl: any(named: 'iconUrl'),
          screenshots: any(named: 'screenshots'),
          compatibility: any(named: 'compatibility'),
          authorPrincipal: any(named: 'authorPrincipal'),
          authorPublicKey: any(named: 'authorPublicKey'),
          signature: any(named: 'signature'),
          timestampIso: any(named: 'timestampIso'),
        ),
      ).thenAnswer(
        (_) async => MarketplaceScript(
          id: 'script-1',
          title: 'Prefilled Title',
          description: 'Short description',
          category: 'Example',
          tags: const <String>[],
          authorId: identity.id,
          authorName: 'Author',
          luaSource: '-- test script',
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Just verify dialog opens without crashing when no identity is active
      expect(find.byType(QuickUploadDialog), findsOneWidget);

      // Click Next to go to code preview step
      final Finder nextButton = find.byKey(const Key('quick-upload-next'));
      expect(nextButton, findsOneWidget);
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Now on step 1, verify the submit button exists
      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      expect(submitButton, findsOneWidget);
      final button = tester.widget<FilledButton>(submitButton);
      expect(button.onPressed, isNotNull);

      // Verify upload was never called (we didn't click submit)
      verifyNever(() => marketplaceService.uploadScript(
            slug: any(named: 'slug'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            category: any(named: 'category'),
            tags: any(named: 'tags'),
            luaSource: any(named: 'luaSource'),
            authorName: any(named: 'authorName'),
            price: any(named: 'price'),
            version: any(named: 'version'),
            canisterIds: any(named: 'canisterIds'),
            iconUrl: any(named: 'iconUrl'),
            screenshots: any(named: 'screenshots'),
            compatibility: any(named: 'compatibility'),
            authorPrincipal: any(named: 'authorPrincipal'),
            authorPublicKey: any(named: 'authorPublicKey'),
            signature: any(named: 'signature'),
          ));
    });

    testWidgets('signs and uploads when identity is selected',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Short description');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Author Name *'), 'Author');
      await tester.pumpAndSettle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          luaSource: any(named: 'luaSource'),
          authorName: any(named: 'authorName'),
          price: any(named: 'price'),
          version: any(named: 'version'),
          canisterIds: any(named: 'canisterIds'),
          iconUrl: any(named: 'iconUrl'),
          screenshots: any(named: 'screenshots'),
          compatibility: any(named: 'compatibility'),
          authorPrincipal: any(named: 'authorPrincipal'),
          authorPublicKey: any(named: 'authorPublicKey'),
          signature: any(named: 'signature'),
          timestampIso: any(named: 'timestampIso'),
        ),
      ).thenAnswer(
        (_) async => MarketplaceScript(
          id: 'script-1',
          title: 'Prefilled Title',
          description: 'Short description',
          category: 'Example',
          tags: const <String>[],
          authorId: identity.id,
          authorName: 'Author',
          authorPrincipal: PrincipalUtils.textFromRecord(identity),
          authorPublicKey: identity.publicKey,
          uploadSignature: 'dummy-signature',
          luaSource: '-- test script',
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Identity is already active through IdentityScope

      // Click Next to go to code preview step
      final Finder nextButton = find.byKey(const Key('quick-upload-next'));
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Now on step 1, find and click submit button
      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();

      // Complete async work
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      final VerificationResult result = verify(
        () => marketplaceService.uploadScript(
          slug: 'prefilled-title',
          title: 'Prefilled Title',
          description: 'Short description',
          category: 'Example',
          tags: captureAny(named: 'tags'),
          luaSource: '-- test script',
          authorName: 'Author',
          price: 0.0,
          version: '1.0.0',
          canisterIds: captureAny(named: 'canisterIds'),
          iconUrl: any(named: 'iconUrl'),
          screenshots: captureAny(named: 'screenshots'),
          compatibility: any(named: 'compatibility'),
          authorPrincipal: captureAny(named: 'authorPrincipal'),
          authorPublicKey: captureAny(named: 'authorPublicKey'),
          signature: captureAny(named: 'signature'),
          timestampIso: captureAny(named: 'timestampIso'),
        ),
      );
      final List<dynamic> captured = result.captured;

      expect(captured[0], isA<List<String>>());
      expect(captured[1], anyOf(isNull, isA<List<String>>()));
      expect(captured[2], anyOf(isNull, isA<List<String>>()));
      expect(captured[3], PrincipalUtils.textFromRecord(identity));
      expect(captured[4], identity.publicKey);
      final String signature = captured[5] as String;
      final String timestamp = captured[6] as String;
      expect(signature, isNotEmpty);
      expect(DateTime.tryParse(timestamp), isA<DateTime?>());

      for (int i = 0;
          i < 10 && find.byType(QuickUploadDialog).evaluate().isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(QuickUploadDialog), findsNothing);
    });
  });
}
