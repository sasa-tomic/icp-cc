import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Upload Fix Verification Tests', () {
    late MarketplaceOpenApiService marketplaceService;

    setUpAll(() async {
      await WranglerManager.initialize();
      marketplaceService = MarketplaceOpenApiService();
      SharedPreferences.setMockInitialValues({});
      suppressDebugOutput = false;
    });

    tearDownAll(() async {
      await WranglerManager.cleanup();
    });

    Widget createTestApp({required Widget child}) {
      return MaterialApp(
        home: Scaffold(
          body: child,
        ),
      );
    }

    testWidgets('Upload dialog with valid form should succeed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(
        child: QuickUploadDialog(),
      ));
      await tester.pumpAndSettle();

      // Fill form with valid data
      final testTitle = 'Fix Verification Test ${DateTime.now().millisecondsSinceEpoch}';
      
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        testTitle,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description *'),
        'Test script for upload fix verification',
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Author Name *'),
        'Fix Verification Test Runner',
      );
      await tester.pumpAndSettle();

      // Submit form
      final uploadButton = find.text('Upload to Marketplace');
      if (uploadButton.evaluate().isEmpty) {
        print('Upload button not found, might be in uploading state');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }
      await tester.tap(uploadButton.first);
      await tester.pumpAndSettle();

      // Wait for upload (may take a few seconds)
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Should show success message (not error)
      expect(find.text('Script published successfully!'), findsOneWidget);
      
      print('✅ Upload dialog form submission works!');
    });

    test('API: Upload with non-empty lua_source should succeed', () async {
      final testTitle = 'Direct API Test ${DateTime.now().millisecondsSinceEpoch}';
      
      // Test direct API call with non-empty lua_source
      final uploadedScript = await marketplaceService.uploadScript(
        title: testTitle,
        description: 'Direct API test for upload fix verification',
        category: 'Development',
        tags: ['fix-test', 'api-direct'],
        luaSource: '''-- Direct API Test Script
function init(arg)
  return {
    message = "Hello from direct API test!"
  }, {}
end

function view(state)
  return {
    type = "text",
    props = {
      text = state.message
    }
  }
end

function update(msg, state)
  return state, {}
end''',
        authorName: 'Direct API Test Runner',
        version: '1.0.0',
        price: 0.0,
      );

      expect(uploadedScript.title, equals(testTitle));
      expect(uploadedScript.description, contains('Direct API test'));
      expect(uploadedScript.category, equals('Development'));
      expect(uploadedScript.authorName, equals('Direct API Test Runner'));
      expect(uploadedScript.luaSource, contains('Direct API Test Script'));

      // Verify it appears in search
      final searchResult = await marketplaceService.searchScripts(
        query: testTitle,
        limit: 10,
      );

      expect(searchResult.scripts.isNotEmpty, isTrue);
      final foundScript = searchResult.scripts.firstWhere(
        (script) => script.id == uploadedScript.id,
        orElse: () => throw Exception('Script not found in search'),
      );
      expect(foundScript.title, equals(testTitle));

      // Clean up
      await marketplaceService.deleteScript(uploadedScript.id);

      print('✅ Direct API upload with lua_source works!');
    });
  });
}