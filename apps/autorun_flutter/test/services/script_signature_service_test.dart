import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/script_signature_service.dart';
import 'package:icp_autorun/utils/principal.dart';

import '../test_helpers/test_keypair_factory.dart';

void main() {
  group('ScriptSignatureService', () {
    late Ed25519 algorithm;
    late SimplePublicKey publicKey;
    late ProfileKeypair keypair;
    late String principal;

    setUpAll(() async {
      algorithm = Ed25519();
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final publicKeyBytes = base64Decode(keypair.publicKey);
      publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      principal = PrincipalUtils.textFromRecord(keypair);
    });

    test('signScriptUpload uses provided timestamp', () async {
      final timestamp = '2025-01-01T00:00:00Z';
      final signature = await ScriptSignatureService.signScriptUpload(
        authorKeypair: keypair,
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

    test('signScriptUpdate requires non-empty scriptId and verifies payload',
        () async {
      const scriptId = 'script-123';
      final timestamp = '2025-01-01T00:00:00Z';

      final signature = await ScriptSignatureService.signScriptUpdate(
        authorKeypair: keypair,
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
          authorKeypair: keypair,
          scriptId: '',
          updates: const {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('signScriptDeletion signs canonical payload and validates scriptId',
        () async {
      const scriptId = 'script-456';
      final timestamp = '2025-02-02T03:04:05Z';

      final signature = await ScriptSignatureService.signScriptDeletion(
        authorKeypair: keypair,
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
          authorKeypair: keypair,
          scriptId: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('canonicalizeUpdateFields sorts tags and filters unsupported keys', () {
    final canonical = ScriptSignatureService.canonicalizeUpdateFields({
      'tags': ['beta', 'alpha'],
      'price': '2.5',
      'lua_source': '-- code',
      'unknown': 'ignore-me',
      'is_public': true,
    });

    expect(canonical.containsKey('unknown'), isFalse);
    expect(canonical['tags'], equals(['alpha', 'beta']));
    expect(canonical['price'], equals(2.5));
    expect(canonical['lua_source'], equals('-- code'));
    expect(canonical['is_public'], isTrue);
  });

  test(
      'buildSignedUpdateRequest returns canonical payload with valid signature',
      () async {
    const scriptId = 'script-321';
    final timestamp = '2025-03-03T03:03:03Z';
    final localKeypair = await TestKeypairFactory.getEd25519Keypair();
    final localPrincipal = PrincipalUtils.textFromRecord(localKeypair);
    final localPublicKey = SimplePublicKey(
      base64Decode(localKeypair.publicKey),
      type: KeyPairType.ed25519,
    );
    final localAlgorithm = Ed25519();

    final request = await ScriptSignatureService.buildSignedUpdateRequest(
      authorKeypair: localKeypair,
      scriptId: scriptId,
      updates: {
        'title': 'Update Title',
        'tags': ['delta', 'alpha'],
        'price': '3.5',
        'is_public': true,
      },
      timestampIso: timestamp,
    );

    expect(request['action'], equals('update'));
    expect(request['script_id'], equals(scriptId));
    expect(request['author_principal'], equals(localPrincipal));
    expect(request['author_public_key'], equals(localKeypair.publicKey));
    expect(request['tags'], equals(['alpha', 'delta']));
    expect(request['price'], equals(3.5));
    expect(request['timestamp'], equals(timestamp));

    final payloadForVerification = _canonicalJsonEncode({
      'action': 'update',
      'script_id': scriptId,
      'title': 'Update Title',
      'tags': ['alpha', 'delta'],
      'price': 3.5,
      'is_public': true,
      'author_principal': localPrincipal,
      'timestamp': timestamp,
    });

    final signature = request['signature'] as String;
    final isValid = await _verifySignature(
      localAlgorithm,
      signature,
      payloadForVerification,
      localPublicKey,
    );
    expect(isValid, isTrue);
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
