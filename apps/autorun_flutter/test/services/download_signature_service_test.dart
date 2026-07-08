import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/download_signature_service.dart';

import '../shared/test_keypair_factory.dart';

/// Coverage for [DownloadSignatureService]:
/// - The canonical payload string matches the backend byte-for-byte
///   (`download:{script_id}:{timestamp}:{nonce}`).
/// - The Ed25519 signature over that string verifies against the matching
///   public key (REAL crypto roundtrip — no mocking).
/// - secp256k1 keypairs are rejected (download endpoint is Ed25519-only).
void main() {
  group('DownloadSignatureService.buildCanonicalPayload', () {
    test('matches the backend build_download_payload format exactly', () {
      final payload = DownloadSignatureService.buildCanonicalPayload(
        scriptId: 'script-42',
        timestamp: '2024-01-02T03:04:05.678Z',
        nonce: '11111111-1111-1111-1111-111111111111',
      );
      // Mirrors `backend/src/main.rs` build_download_payload. Changing this
      // string without coordinating with the backend BREAKS downloads.
      expect(payload,
          'download:script-42:2024-01-02T03:04:05.678Z:11111111-1111-1111-1111-111111111111');
    });
  });

  group('DownloadSignatureService.createSignedRequest (real crypto)', () {
    test('signs the canonical payload with Ed25519 and the signature verifies',
        () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      const scriptId = 'script-paid-1';
      const accountId = 'acct-1';
      const timestamp = '2024-01-02T03:04:05.678Z';
      const nonce = '22222222-2222-2222-2222-222222222222';

      final signed = await DownloadSignatureService.createSignedRequest(
        signingKeypair: keypair,
        accountId: accountId,
        scriptId: scriptId,
        timestampIso: timestamp,
        nonce: nonce,
      );

      // The public key on the signed request is the signer's public key.
      expect(signed.publicKeyB64, keypair.publicKey);
      expect(signed.accountId, accountId);
      expect(signed.timestamp, timestamp);
      expect(signed.nonce, nonce);
      expect(signed.signatureB64, isNotEmpty);

      // REAL crypto roundtrip: verify the signature against the canonical
      // payload using the public key. The backend does this same verify.
      final payload = DownloadSignatureService.buildCanonicalPayload(
        scriptId: scriptId,
        timestamp: timestamp,
        nonce: nonce,
      );
      final algorithm = Ed25519();
      final publicKeyBytes = base64Decode(keypair.publicKey);
      final signatureBytes = base64Decode(signed.signatureB64);
      final publicKey =
          SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature =
          Signature(signatureBytes, publicKey: publicKey);
      final isVerified = await algorithm.verify(
        utf8.encode(payload),
        signature: signature,
      );
      expect(isVerified, isTrue,
          reason: 'the signature over the canonical download payload MUST '
              'verify with the matching public key (backend rejects '
              'otherwise — HTTP 401)');
    });

    test('signature fails to verify against a DIFFERENT public key (tamper)',
        () async {
      final alice = await TestKeypairFactory.getEd25519Keypair();
      final bob = await TestKeypairFactory.fromSeed(2);
      const scriptId = 'script-x';
      const timestamp = '2024-01-02T03:04:05.678Z';
      const nonce = '33333333-3333-3333-3333-333333333333';

      final signed = await DownloadSignatureService.createSignedRequest(
        signingKeypair: alice,
        accountId: 'acct-alice',
        scriptId: scriptId,
        timestampIso: timestamp,
        nonce: nonce,
      );

      // Verify against Bob's public key — MUST fail (the signature was made
      // with Alice's private key).
      final algorithm = Ed25519();
      final publicKey =
          SimplePublicKey(base64Decode(bob.publicKey), type: KeyPairType.ed25519);
      final signature = Signature(base64Decode(signed.signatureB64),
          publicKey: publicKey);
      final verified = await algorithm.verify(
        utf8.encode(DownloadSignatureService.buildCanonicalPayload(
          scriptId: scriptId,
          timestamp: timestamp,
          nonce: nonce,
        )),
        signature: signature,
      );
      expect(verified, isFalse,
          reason: 'a signature made with Alice key must NOT verify against '
              'Bob public key');
    });

    test('rejects secp256k1 keypairs (download is Ed25519-only)', () async {
      final secp = await TestKeypairFactory.getSecp256k1Keypair();
      expect(
        () => DownloadSignatureService.createSignedRequest(
          signingKeypair: secp,
          accountId: 'a',
          scriptId: 's',
          timestampIso: '2024-01-02T03:04:05.678Z',
          nonce: 'n',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('defaults timestamp + nonce when not provided (replay protection)',
        () async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final signed = await DownloadSignatureService.createSignedRequest(
        signingKeypair: keypair,
        accountId: 'a',
        scriptId: 's',
      );
      expect(signed.timestamp, isNotEmpty,
          reason: 'a fresh ISO-8601 timestamp must be generated');
      // UUID v4 shape: 8-4-4-4-12 hex digits.
      expect(signed.nonce, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
    });
  });
}
