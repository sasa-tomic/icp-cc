import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/script_signature_service.dart';
import 'package:icp_autorun/utils/principal.dart';

import '../test_helpers/test_identity_factory.dart';

void main() {
  group('ScriptSignatureService', () {
    late Ed25519 algorithm;
    late SimplePublicKey publicKey;
    late IdentityRecord identity;
    late String principal;

    setUpAll(() async {
      algorithm = Ed25519();
      identity = await TestIdentityFactory.getEd25519Identity();
      final publicKeyBytes = base64Decode(identity.publicKey);
      publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      principal = PrincipalUtils.textFromRecord(identity);
    });

    test('signScriptUpload uses provided timestamp', () async {
      final timestamp = '2025-01-01T00:00:00Z';
      final signature = await ScriptSignatureService.signScriptUpload(
        authorIdentity: identity,
        title: 'Upload Title',
        description: 'Upload Description',
        category: 'utilities',
        luaSource: 'print("hello")',
        version: '1.0.0',
        tags: ['b', 'a'],
        timestampIso: timestamp,
      );

      final payload = _canonicalJsonEncode({
        'action': 'upload',
        'title': 'Upload Title',
        'description': 'Upload Description',
        'category': 'utilities',
        'lua_source': 'print("hello")',
        'version': '1.0.0',
        'tags': ['a', 'b'],
        'author_principal': principal,
        'timestamp': timestamp,
      });

      final isValid = await _verifySignature(
        algorithm,
        signature,
        payload,
        publicKey,
      );

      expect(isValid, isTrue);

      final mismatchPayload = _canonicalJsonEncode({
        'action': 'upload',
        'title': 'Upload Title',
        'description': 'Upload Description',
        'category': 'utilities',
        'lua_source': 'print("hello")',
        'version': '1.0.0',
        'tags': ['a', 'b'],
        'author_principal': principal,
        'timestamp': '2025-01-01T00:00:01Z',
      });

      final mismatchValid = await _verifySignature(
        algorithm,
        signature,
        mismatchPayload,
        publicKey,
      );

      expect(mismatchValid, isFalse);
    });

    test('signScriptUpdate requires non-empty scriptId and verifies payload', () async {
      const scriptId = 'script-123';
      final timestamp = '2025-01-01T00:00:00Z';

      final signature = await ScriptSignatureService.signScriptUpdate(
        authorIdentity: identity,
        scriptId: scriptId,
        updates: {
          'title': 'Updated Title',
          'price': 2.5,
          'tags': ['beta', 'alpha'],
        },
        timestampIso: timestamp,
      );

      final payload = _canonicalJsonEncode({
        'action': 'update',
        'script_id': scriptId,
        'title': 'Updated Title',
        'price': 2.5,
        'tags': ['alpha', 'beta'],
        'author_principal': principal,
        'timestamp': timestamp,
      });

      final isValid = await _verifySignature(
        algorithm,
        signature,
        payload,
        publicKey,
      );
      expect(isValid, isTrue);

      final mismatchPayload = _canonicalJsonEncode({
        'action': 'update',
        'script_id': 'other-script',
        'title': 'Updated Title',
        'price': 2.5,
        'tags': ['alpha', 'beta'],
        'author_principal': principal,
        'timestamp': timestamp,
      });

      final mismatchValid = await _verifySignature(
        algorithm,
        signature,
        mismatchPayload,
        publicKey,
      );
      expect(mismatchValid, isFalse);

      await expectLater(
        () => ScriptSignatureService.signScriptUpdate(
          authorIdentity: identity,
          scriptId: '',
          updates: const {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('signScriptDeletion signs canonical payload and validates scriptId', () async {
      const scriptId = 'script-456';
      final timestamp = '2025-02-02T03:04:05Z';

      final signature = await ScriptSignatureService.signScriptDeletion(
        authorIdentity: identity,
        scriptId: scriptId,
        timestampIso: timestamp,
      );

      final payload = _canonicalJsonEncode({
        'action': 'delete',
        'script_id': scriptId,
        'author_principal': principal,
        'timestamp': timestamp,
      });

      final isValid = await _verifySignature(
        algorithm,
        signature,
        payload,
        publicKey,
      );
      expect(isValid, isTrue);

      final mismatchPayload = _canonicalJsonEncode({
        'action': 'delete',
        'script_id': 'other-script',
        'author_principal': principal,
        'timestamp': timestamp,
      });

      final mismatchValid = await _verifySignature(
        algorithm,
        signature,
        mismatchPayload,
        publicKey,
      );
      expect(mismatchValid, isFalse);

      await expectLater(
        () => ScriptSignatureService.signScriptDeletion(
          authorIdentity: identity,
          scriptId: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Future<bool> _verifySignature(
  SignatureAlgorithm algorithm,
  String signatureB64,
  String canonicalPayload,
  SimplePublicKey publicKey,
) async {
  final messageBytes = utf8.encode(canonicalPayload);
  final signatureBytes = base64Decode(signatureB64);
  final signature = Signature(
    signatureBytes,
    publicKey: publicKey,
  );
  return algorithm.verify(
    messageBytes,
    signature: signature,
  );
}

String _canonicalJsonEncode(Map<String, dynamic> data) {
  final sortedKeys = data.keys.toList()..sort();
  final Map<String, dynamic> sortedMap = <String, dynamic>{};

  for (final key in sortedKeys) {
    final value = data[key];
    if (value is Map<String, dynamic>) {
      sortedMap[key] = _canonicalJsonEncode(value);
    } else if (value is List) {
      sortedMap[key] = value;
    } else {
      sortedMap[key] = value;
    }
  }

  return jsonEncode(sortedMap);
}
