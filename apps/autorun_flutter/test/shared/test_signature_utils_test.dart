import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import 'test_keypair_factory.dart';
import 'test_signature_utils.dart';
import 'unified_test_builder.dart';

/// W6-11 — `generateTestSignatureSync` MUST produce a REAL verifiable Ed25519
/// signature, not the fake DJB2-style hash it emitted before. These tests prove
/// it by verifying the signature against the keypair's public key using
/// `package:ed25519_edwards` — the SAME independent reference verifier already
/// trusted by `test/features/web/ed25519_principal_test.dart`.
///
/// See AGENTS.md: "use REAL keypairs, never mock cryptography".

/// Reproduce the canonical JSON signing input the helper signs over.
/// Mirrors `TestSignatureUtils._canonicalJsonEncode` (sorted keys → jsonEncode).
String canonicalJsonEncode(Map<String, dynamic> data) {
  final sortedMap = <String, dynamic>{};
  final sortedKeys = data.keys.toList()..sort();
  for (final key in sortedKeys) {
    final value = data[key];
    if (value is Map<String, dynamic>) {
      sortedMap[key] = jsonDecode(canonicalJsonEncode(value));
    } else {
      sortedMap[key] = value;
    }
  }
  return jsonEncode(sortedMap);
}

Uint8List payloadBytes(Map<String, dynamic> payload) =>
    Uint8List.fromList(utf8.encode(canonicalJsonEncode(payload)));

void main() {
  setUpAll(() async {
    await TestSignatureUtils.ensureInitialized();
  });

  group('W6-11 generateTestSignatureSync — real Ed25519', () {
    final payload = <String, dynamic>{
      'action': 'upload',
      'title': 'Test Script',
      'description': 'A test script',
      'category': 'utility',
      'bundle': 'print("Hello")',
      'version': '1.0.0',
      'tags': <String>['test', 'utility'],
      'author_principal': TestSignatureUtils.getPrincipal(),
      'timestamp': '2026-07-10T00:00:00.000Z',
    };

    test('signature VERIFIES against the keypair public key (reference verifier)',
        () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final signatureB64 =
          TestSignatureUtils.generateTestSignatureSync(payload);
      final sigBytes = base64Decode(signatureB64);
      final pubBytes = base64Decode(keypair.publicKey);

      // The real, independent Ed25519 verifier (NOT the same code path that
      // produced the signature — generateTestSignatureSync uses the
      // `cryptography` algorithm internally; this is the cross-library check).
      final verified = ed.verify(
        ed.PublicKey(Uint8List.fromList(pubBytes)),
        payloadBytes(payload),
        Uint8List.fromList(sigBytes),
      );

      expect(verified, isTrue,
          reason:
              'generateTestSignatureSync must produce a real Ed25519 signature '
              'that verifies against the public key. A fake/non-cryptographic '
              'signature will NOT verify here.');
    });

    test('signature is exactly 64 bytes (Ed25519 signature size)', () {
      final signatureB64 =
          TestSignatureUtils.generateTestSignatureSync(payload);
      expect(base64Decode(signatureB64).length, equals(64));
    });

    test('signing is deterministic — same payload yields the same signature',
        () {
      final s1 = TestSignatureUtils.generateTestSignatureSync(payload);
      final s2 = TestSignatureUtils.generateTestSignatureSync(payload);
      expect(s1, equals(s2));
    });

    test('sync signature matches the async real Ed25519 signature (same seed+msg)',
        () async {
      // Ed25519 is deterministic: real sync and real async over identical
      // canonical bytes + seed MUST be byte-equal. This is the strongest proof
      // that the sync path now uses genuine Ed25519 with the correct seed and
      // canonical encoding.
      final syncSig = TestSignatureUtils.generateTestSignatureSync(payload);
      final asyncSig =
          await TestSignatureUtils.generateTestSignature(payload);
      expect(syncSig, equals(asyncSig));
    });

    test('tampered payload does NOT verify', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final signatureB64 =
          TestSignatureUtils.generateTestSignatureSync(payload);
      final tampered = Map<String, dynamic>.from(payload)
        ..['title'] = 'Tampered Title';

      final verified = ed.verify(
        ed.PublicKey(Uint8List.fromList(base64Decode(keypair.publicKey))),
        payloadBytes(tampered),
        Uint8List.fromList(base64Decode(signatureB64)),
      );
      expect(verified, isFalse);
    });

    test('SignatureUtils wrapper produces a verifying signature', () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final signatureB64 = SignatureUtils.generateTestSignature(payload);

      final verified = ed.verify(
        ed.PublicKey(Uint8List.fromList(base64Decode(keypair.publicKey))),
        payloadBytes(payload),
        Uint8List.fromList(base64Decode(signatureB64)),
      );
      expect(verified, isTrue);
    });

    test('UnifiedScriptTestBuilder.build() stamps a verifying signature',
        () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final record = UnifiedScriptTestBuilder.create()
          .withId('w6-11-script')
          .withTitle('W6-11 Script')
          .build();

      // Reconstruct the exact signing payload used by the builder.
      final signedPayload = <String, dynamic>{
        'action': 'upload',
        'title': record.title,
        'description': record.metadata['description'],
        'category': record.metadata['category'],
        'bundle': record.bundle,
        'version': record.metadata['version'] ?? '1.0.0',
        'tags': record.metadata['tags'] ?? <String>[],
        'author_principal': record.metadata['authorPrincipal'],
        'timestamp': record.metadata['timestamp'],
      };

      final verified = ed.verify(
        ed.PublicKey(Uint8List.fromList(base64Decode(keypair.publicKey))),
        payloadBytes(signedPayload),
        Uint8List.fromList(base64Decode(record.metadata['signature'] as String)),
      );
      expect(verified, isTrue,
          reason:
              'UnifiedScriptTestBuilder must stamp a real signature that '
              'verifies against the author public key.');
    });
  });
}
