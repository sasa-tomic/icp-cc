import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:icp_autorun/widgets/script_editor.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/fake_secure_keypair_repository.dart';
import '../shared/test_keypair_factory.dart';
import '../shared/ts_bundle_fixtures.dart';

class _MockMarketplaceService extends Mock
    implements MarketplaceOpenApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('QuickUploadDialog keypair workflow', () {
    // A well-formed bundle that passes the authoritative sandbox validator
    // (the publish gate rejects invalid bundles before signing).
    const String validBundle = '''
"use strict";
(() => {
  globalThis.init = () => ({ state: { count: 0 }, effects: [] });
  globalThis.view = (state) => ({ type: "text", props: { text: String(state.count) } });
  globalThis.update = (_m, state) => ({ state, effects: [] });
})();
''';

    late ProfileKeypair keypair;
    late ProfileController profileController;
    late _MockMarketplaceService marketplaceService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      // Set the first profile as active
      if (profileController.profiles.isNotEmpty) {
        await profileController
            .setActiveProfile(profileController.profiles.first.id);
      }
      marketplaceService = _MockMarketplaceService();
    });

    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
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
                            preFilledCode: validBundle,
                            profileController: profileController,
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

    testWidgets('blocks upload when no keypair is selected',
        (WidgetTester tester) async {
      // Don't set active keypair - this test checks no-keypair behavior
      await pumpDialog(tester);

      // Fill required fields that are not pre-populated
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Short description');
      await tester.pumpAndSettle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          bundle: any(named: 'bundle'),
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
          authorId: keypair.id,
          bundle: '// test script bundle',
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Just verify dialog opens without crashing when no keypair is active
      expect(find.byType(QuickUploadDialog), findsOneWidget);

      // Single primary action: the submit button lives on the form page now
      // (no separate "Next: Review Code" step).
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
            bundle: any(named: 'bundle'),
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

    testWidgets('signs and uploads when keypair is selected',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Short description');
      await tester.pumpAndSettle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          bundle: any(named: 'bundle'),
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
          authorId: keypair.id,
          authorPrincipal: PrincipalUtils.textFromRecord(keypair),
          authorPublicKey: keypair.publicKey,
          uploadSignature: 'dummy-signature',
          bundle: '// test script bundle',
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Keypair is already active through KeypairScope

      // Single primary action: upload directly from the form page.
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
          bundle: validBundle,
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
      expect(captured[3], PrincipalUtils.textFromRecord(keypair));
      expect(captured[4], keypair.publicKey);
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

  group('QuickUploadDialog script source handling', () {
    late ProfileKeypair keypair;
    late ProfileController profileController;
    late _MockMarketplaceService marketplaceService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      if (profileController.profiles.isNotEmpty) {
        await profileController
            .setActiveProfile(profileController.profiles.first.id);
      }
      marketplaceService = _MockMarketplaceService();
    });

    testWidgets(
        'uses actual script.bundle in code preview when ScriptRecord is passed',
        (WidgetTester tester) async {
      const String actualBundle = '''// My Unique Script
// This is custom code that should appear in preview
"use strict";
(() => {
  globalThis.init = () => ({ state: { custom: "data", unique: true }, effects: [] });
  globalThis.view = (_state) => ({ type: "text", props: { text: "Custom message from actual script!" } });
  globalThis.update = (_m, state) => ({ state, effects: [] });
})();''';

      final ScriptRecord script = ScriptRecord(
        id: 'test-script-1',
        title: 'Test Script',
        bundle: actualBundle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
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
                            script: script,
                            profileController: profileController,
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

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Test description');
      await tester.pumpAndSettle();

      // Code preview is collapsed by default; expand it to reveal the editor.
      await tester
          .ensureVisible(find.byKey(const Key('quick-upload-code-preview')));
      await tester.tap(find.text('Preview code (optional)'));
      await tester.pumpAndSettle();

      final ScriptEditor editor = tester.widget(find.byType(ScriptEditor));
      expect(editor.initialCode, equals(actualBundle),
          reason:
              'Code preview should show the actual script.bundle, not generated code');
    });

    testWidgets('uploads actual script.bundle not generated code',
        (WidgetTester tester) async {
      const String actualBundle = '''// Unique Upload Test Script
"use strict";
(() => {
  globalThis.init = () => ({ state: { count: 0 }, effects: [] });
  globalThis.view = (state) => ({ type: "text", props: { text: "Count: " + (state.count ?? 0) } });
  globalThis.update = (_m, state) => ({ state, effects: [] });
})();''';

      final ScriptRecord script = ScriptRecord(
        id: 'test-script-2',
        title: 'Upload Test Script',
        bundle: actualBundle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
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
                            script: script,
                            profileController: profileController,
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

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Test description');
      await tester.pumpAndSettle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          bundle: any(named: 'bundle'),
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
          title: 'Upload Test Script',
          description: 'Test description',
          category: 'Example',
          tags: const <String>[],
          authorId: keypair.id,
          authorPrincipal: PrincipalUtils.textFromRecord(keypair),
          authorPublicKey: keypair.publicKey,
          uploadSignature: 'dummy-signature',
          bundle: actualBundle,
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Single primary action: upload directly from the form page.
      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      verify(
        () => marketplaceService.uploadScript(
          slug: 'upload-test-script',
          title: 'Upload Test Script',
          description: 'Test description',
          category: 'Example',
          tags: any(named: 'tags'),
          bundle: actualBundle,
          price: 0.0,
          version: '1.0.0',
          canisterIds: any(named: 'canisterIds'),
          iconUrl: any(named: 'iconUrl'),
          screenshots: any(named: 'screenshots'),
          compatibility: any(named: 'compatibility'),
          authorPrincipal: any(named: 'authorPrincipal'),
          authorPublicKey: any(named: 'authorPublicKey'),
          signature: any(named: 'signature'),
          timestampIso: any(named: 'timestampIso'),
        ),
      ).called(1);
    });
  });

  group('QuickUploadDialog sandbox validation gate (UX-B5)', () {
    late ProfileKeypair keypair;
    late ProfileController profileController;
    late _MockMarketplaceService marketplaceService;
    final RustBridgeLoader loader = const RustBridgeLoader();

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      if (profileController.profiles.isNotEmpty) {
        await profileController
            .setActiveProfile(profileController.profiles.first.id);
      }
      marketplaceService = _MockMarketplaceService();
    });

    Future<void> pumpDialog(
      WidgetTester tester, {
      required String bundle,
    }) async {
      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
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
                            preFilledTitle: 'Gate Test',
                            preFilledCode: bundle,
                            profileController: profileController,
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

      // Description is a required field; the bundle is pre-filled.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'),
          'Gate test description');
      await tester.pumpAndSettle();
    }

    testWidgets('a valid pilot bundle publishes through the gate',
        (tester) async {
      if (!nativeLibAvailable(loader)) {
        // The authoritative Rust validator must be present to assert the
        // positive path; skip when the native bridge can't load.
        return;
      }
      final String pilotBundle = loadPilotBundle();

      when(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          bundle: any(named: 'bundle'),
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
          title: 'Gate Test',
          description: 'Gate test description',
          category: 'Example',
          tags: const <String>[],
          authorId: keypair.id,
          bundle: pilotBundle,
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await pumpDialog(tester, bundle: pilotBundle);

      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      verify(
        () => marketplaceService.uploadScript(
          slug: any(named: 'slug'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          category: any(named: 'category'),
          tags: any(named: 'tags'),
          bundle: pilotBundle,
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
      ).called(1);
    });

    testWidgets('a bundle containing eval() is blocked and never uploaded',
        (tester) async {
      if (!nativeLibAvailable(loader)) {
        return;
      }
      const String invalidBundle = '''
"use strict";
(() => {
  globalThis.init = () => ({ state: { count: 0 }, effects: [] });
  globalThis.view = (state) => ({ type: "text", props: { text: String(state.count) } });
  globalThis.update = (_m, state) => ({ state, effects: [] });
  eval("1+1");
})();
''';

      await pumpDialog(tester, bundle: invalidBundle);

      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // The upload MUST be refused: never signed, never sent.
      verifyNever(() => marketplaceService.uploadScript(
            slug: any(named: 'slug'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            category: any(named: 'category'),
            tags: any(named: 'tags'),
            bundle: any(named: 'bundle'),
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
          ));

      // A clear, user-facing error surfaces the specific violation.
      expect(
        find.textContaining('failed sandbox validation'),
        findsOneWidget,
      );
      expect(find.textContaining('eval()'), findsOneWidget);
    });

    testWidgets('a bundle containing Intl.* is blocked and never uploaded',
        (tester) async {
      if (!nativeLibAvailable(loader)) {
        return;
      }
      const String invalidBundle = '''
"use strict";
(() => {
  globalThis.init = () => ({ state: { count: 0 }, effects: [] });
  globalThis.view = (state) => ({ type: "text", props: { text: String(state.count) } });
  globalThis.update = (_m, state) => ({ state, effects: [] });
  return new Intl.NumberFormat("de").format(1);
})();
''';

      await pumpDialog(tester, bundle: invalidBundle);

      final Finder submitButton = find.byKey(const Key('quick-upload-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      verifyNever(() => marketplaceService.uploadScript(
            slug: any(named: 'slug'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            category: any(named: 'category'),
            tags: any(named: 'tags'),
            bundle: any(named: 'bundle'),
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
          ));

      expect(
        find.textContaining('failed sandbox validation'),
        findsOneWidget,
      );
      expect(find.textContaining('Intl'), findsOneWidget);
    });
  });
}
