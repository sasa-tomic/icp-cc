import 'package:flutter_test/flutter_test.dart';
import 'package:autorun_flutter/services/marketplace_open_api_service.dart';
import 'package:autorun_flutter/services/script_signature_service.dart';
import 'package:autorun_flutter/models/marketplace_script.dart';

import '../shared/test_helpers.dart';

/// E2E test: User can upload scripts to marketplace
/// 
/// This test covers the complete upload flow:
/// 1. Create signed upload request
/// 2. Submit to marketplace
/// 3. Verify script appears in search
/// 4. Update script
/// 5. Delete script
void main() {
  late MarketplaceOpenApiService apiService;
  late TestKeypair testKeypair;

  setUpAll(() async {
    apiService = await ApiServiceManager.createTestService();
    testKeypair = TestKeypairFactory.getEd25519Keypair();
  });

  group('upload script to marketplace', () {
    late String uploadedScriptId;
    final testSlug = 'test-${DateTime.now().millisecondsSinceEpoch}';

    test('user can create signed upload request', () async {
      final request = await TestSignatureUtils.createTestScriptRequest(
        keypair: testKeypair,
        slug: testSlug,
        title: 'Test Script for E2E',
        description: 'A test script for marketplace upload testing',
        category: 'Utilities',
        luaSource: '-- Test Lua script\nreturn { message = "Hello" }',
      );

      expect(request, isNotNull);
      expect(request['slug'], equals(testSlug));
      expect(request['signature'], isNotEmpty);
      expect(request['authorPublicKey'], isNotEmpty);
    });

    test('user can upload script with valid signature', () async {
      final request = await TestSignatureUtils.createTestScriptRequest(
        keypair: testKeypair,
        slug: testSlug,
        title: 'Test Script for E2E',
        description: 'A test script for marketplace upload testing',
        category: 'Utilities',
        luaSource: '-- Test Lua script\nreturn { message = "Hello" }',
      );

      final script = await apiService.uploadScript(
        slug: request['slug'],
        title: request['title'],
        description: request['description'],
        category: request['category'],
        tags: ['test', 'e2e'],
        luaSource: request['luaSource'],
        authorPrincipal: request['authorPrincipal'],
        authorPublicKey: request['authorPublicKey'],
        signature: request['signature'],
        timestampIso: request['timestampIso'],
      );

      expect(script, isNotNull);
      expect(script.slug, equals(testSlug));
      expect(script.title, equals('Test Script for E2E'));
      
      uploadedScriptId = script.id;
    });

    test('uploaded script appears in search results', () async {
      assumeTrue(uploadedScriptId.isNotEmpty, 'Need uploaded script ID');

      // Wait a moment for indexing
      await Future.delayed(Duration(milliseconds: 500));

      final result = await apiService.searchScripts(
        query: testSlug,
        limit: 10,
      );

      expect(result.scripts, isNotEmpty,
        reason: 'Uploaded script should appear in search');
      
      final found = result.scripts.any((s) => s.id == uploadedScriptId);
      expect(found, isTrue,
        reason: 'Uploaded script with ID $uploadedScriptId should be found');
    });

    test('user can update uploaded script', () async {
      assumeTrue(uploadedScriptId.isNotEmpty, 'Need uploaded script ID');

      final updateRequest = await TestSignatureUtils.createTestScriptRequest(
        keypair: testKeypair,
        slug: testSlug,
        title: 'Updated Test Script',
        description: 'Updated description',
        category: 'Utilities',
        luaSource: '-- Updated Lua script\nreturn { message = "Updated" }',
        action: 'update',
        scriptId: uploadedScriptId,
      );

      final updated = await apiService.updateScript(
        scriptId: uploadedScriptId,
        title: updateRequest['title'],
        description: updateRequest['description'],
        luaSource: updateRequest['luaSource'],
        authorPublicKey: updateRequest['authorPublicKey'],
        signature: updateRequest['signature'],
        timestampIso: updateRequest['timestampIso'],
      );

      expect(updated, isNotNull);
      expect(updated.title, equals('Updated Test Script'));
    });

    test('user can delete uploaded script', () async {
      assumeTrue(uploadedScriptId.isNotEmpty, 'Need uploaded script ID');

      final deleteRequest = await TestSignatureUtils.createTestScriptRequest(
        keypair: testKeypair,
        slug: testSlug,
        action: 'delete',
        scriptId: uploadedScriptId,
      );

      await apiService.deleteScript(
        scriptId: uploadedScriptId,
        authorPublicKey: deleteRequest['authorPublicKey'],
        signature: deleteRequest['signature'],
        timestampIso: deleteRequest['timestampIso'],
      );

      // Verify script no longer appears in search
      final result = await apiService.searchScripts(query: testSlug);
      final found = result.scripts.any((s) => s.id == uploadedScriptId);
      expect(found, isFalse,
        reason: 'Deleted script should not appear in search');
    });
  });
}
