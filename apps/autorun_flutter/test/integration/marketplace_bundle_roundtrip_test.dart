@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/script_signature_service.dart';
import 'package:icp_autorun/utils/principal.dart';

import '../shared/test_keypair_factory.dart';
import '../shared/ts_bundle_fixtures.dart';

void main() {
  final String baseUrl = _requireBaseUrl();
  final String pilotBundle = loadPilotBundle();
  final RustBridgeLoader loader = const RustBridgeLoader();

  late MarketplaceOpenApiService service;
  late ProfileKeypair authorKeypair;
  late String authorPrincipal;
  final List<String> createdIds = <String>[];

  setUpAll(() async {
    suppressDebugOutput = true;
    AppConfig.setTestEndpoint(baseUrl);
    await _requireHealthy(baseUrl);
    service = MarketplaceOpenApiService()..resetHttpClient();
    authorKeypair = await TestKeypairFactory.getEd25519Keypair();
    authorPrincipal = PrincipalUtils.textFromRecord(authorKeypair);
  });

  tearDown(() async {
    for (final id in createdIds) {
      await _deleteScript(baseUrl, id, authorKeypair);
    }
    createdIds.clear();
  });

  group('marketplace signed TS bundle roundtrip — POSITIVE', () {
    test('signed bundle survives upload -> GET -> download -> execute on the '
        '`bundle` wire key', () async {
      final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
      const String title = 'TQ-6 Signed Bundle Roundtrip';
      const String description = 'End-to-end marketplace bundle wire-field test';
      const String category = 'utility';
      const String version = '1.0.0';
      const List<String> tags = <String>['tq6', 'roundtrip'];
      final String timestamp = DateTime.now().toUtc().toIso8601String();

      final String signature = await ScriptSignatureService.signScriptUpload(
        authorKeypair: authorKeypair,
        title: title,
        description: description,
        category: category,
        bundle: pilotBundle,
        version: version,
        tags: tags,
        timestampIso: timestamp,
      );

      final MarketplaceScript uploaded = await service.uploadScript(
        slug: 'tq6-bundle-$stamp',
        title: title,
        description: description,
        category: category,
        tags: tags,
        bundle: pilotBundle,
        version: version,
        price: 0.0,
        authorPrincipal: authorPrincipal,
        authorPublicKey: authorKeypair.publicKey,
        signature: signature,
        timestampIso: timestamp,
      );
      createdIds.add(uploaded.id);

      expect(uploaded.id, isNotEmpty);

      final Map<String, dynamic> wire = await _fetchScriptWire(baseUrl, uploaded.id);
      expect(wire['bundle'], equals(pilotBundle),
          reason: 'server must echo the uploaded bundle byte-identically');
      expect(wire.containsKey('code'), isFalse,
          reason: 'bundle must NOT be carried on a legacy `code` wire key');
      expect(wire.containsKey('lua'), isFalse,
          reason: 'bundle must NOT be carried on a legacy `lua` wire key');
      expect(wire.containsKey('lua_source'), isFalse,
          reason: 'bundle must NOT be carried on a legacy `lua_source` wire key');

      final MarketplaceScript detail = await service.getScriptDetails(uploaded.id);
      expect(detail.bundle, equals(pilotBundle));

      final String downloadedBundle = await service.downloadScript(uploaded.id);
      expect(downloadedBundle, equals(pilotBundle));

      if (!nativeLibAvailable(loader)) {
        debugPrint(
            'SKIP execute-step: libicp_core.so did not load; upload/GET/download already proven.');
        return;
      }

      final Map<String, dynamic> initObj =
          await bootRuntime().init(script: downloadedBundle, budgetMs: 1000);
      expect(initObj['ok'], isTrue);
      final Map<String, dynamic> state =
          Map<String, dynamic>.from(initObj['state'] as Map);
      expect(state['count'], 0);
      expect(state['enabled'], isTrue);
      expect(state['role'], 'user');
    });
  });

  group('marketplace signed TS bundle roundtrip — NEGATIVE', () {
    test('upload with a tampered signature is rejected with HTTP 401 and an '
        'Invalid signature error', () async {
      final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
      const String title = 'TQ-6 Tampered Signature';
      const String description = 'Must be rejected by signature verification';
      const String category = 'utility';
      const String version = '1.0.0';
      const List<String> tags = <String>['tq6', 'negative'];
      final String timestamp = DateTime.now().toUtc().toIso8601String();

      final String validSignature = await ScriptSignatureService.signScriptUpload(
        authorKeypair: authorKeypair,
        title: title,
        description: description,
        category: category,
        bundle: pilotBundle,
        version: version,
        tags: tags,
        timestampIso: timestamp,
      );
      final String tamperedSignature = _corruptSignature(validSignature);

      expect(
        () => service.uploadScript(
          slug: 'tq6-tampered-$stamp',
          title: title,
          description: description,
          category: category,
          tags: tags,
          bundle: pilotBundle,
          version: version,
          price: 0.0,
          authorPrincipal: authorPrincipal,
          authorPublicKey: authorKeypair.publicKey,
          signature: tamperedSignature,
          timestampIso: timestamp,
        ),
        throwsA(isA<Exception>().having((Exception e) => e.toString(), 'message',
            allOf(contains('HTTP 401'), contains('Invalid signature')))),
      );
    });
  });
}

String _requireBaseUrl() {
  final String port = Platform.environment['MARKETPLACE_API_PORT'] ?? '';
  if (port.isEmpty) {
    throw Exception('MARKETPLACE_API_PORT environment variable not set. '
        'Start the dev API with: just api-dev-up');
  }
  return 'http://127.0.0.1:$port';
}

Future<void> _requireHealthy(String baseUrl) async {
  const int maxAttempts = 10;
  final http.Client client = http.Client();
  try {
    for (int i = 0; i < maxAttempts; i++) {
      final http.Response response = await client
          .get(Uri.parse('$baseUrl/api/v1/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('API server not healthy at $baseUrl after $maxAttempts probes');
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _fetchScriptWire(String baseUrl, String id) async {
  final http.Response response = await http
      .get(Uri.parse('$baseUrl/api/v1/scripts/$id'))
      .timeout(const Duration(seconds: 10));
  expect(response.statusCode, 200, reason: 'GET script detail must succeed');
  final Map<String, dynamic> decoded =
      jsonDecode(response.body) as Map<String, dynamic>;
  expect(decoded['success'], isTrue);
  return Map<String, dynamic>.from(decoded['data'] as Map);
}

Future<void> _deleteScript(
    String baseUrl, String id, ProfileKeypair keypair) async {
  final String timestamp = DateTime.now().toUtc().toIso8601String();
  final String signature = await ScriptSignatureService.signScriptDeletion(
    authorKeypair: keypair,
    scriptId: id,
    timestampIso: timestamp,
  );
  await http
      .delete(
        Uri.parse('$baseUrl/api/v1/scripts/$id'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'action': 'delete',
          'script_id': id,
          'author_principal': PrincipalUtils.textFromRecord(keypair),
          'author_public_key': keypair.publicKey,
          'signature': signature,
          'timestamp': timestamp,
        }),
      )
      .timeout(const Duration(seconds: 10));
}

String _corruptSignature(String signature) {
  final String first = signature[0];
  final String replacement = first == 'A' ? 'B' : 'A';
  return '$replacement${signature.substring(1)}';
}
