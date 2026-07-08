import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../models/profile_keypair.dart';

/// Produces the signed payload for the authenticated
/// `POST /api/v1/scripts/:id/download` endpoint.
///
/// The canonical payload is a plain UTF-8 string
/// `download:{script_id}:{timestamp}:{nonce}` (NO JSON, NO canonicalisation)
/// signed with the caller's Ed25519 private key. The matching public key is
/// sent alongside in the request body so the backend can resolve the owning
/// account and verify the signature. This mirrors the backend's
/// `build_download_payload` (`backend/src/main.rs`) byte-for-byte.
///
/// Kept as its own service (rather than folded into `ScriptSignatureService`)
/// because the payload format is a positional colon-joined string — distinct
/// from the canonical-JSON signatures used by upload/update/delete — so
/// isolating it avoids muddying the JSON-canonicalisation helpers.
class DownloadSignatureService {
  const DownloadSignatureService._();

  static const _uuid = Uuid();

  /// The canonical, backend-matching payload string for a download request.
  ///
  /// Exposed so tests can assert the wire format without re-deriving it.
  static String buildCanonicalPayload({
    required String scriptId,
    required String timestamp,
    required String nonce,
  }) {
    return 'download:$scriptId:$timestamp:$nonce';
  }

  /// Create a fully-signed download request — the four fields the backend's
  /// `DownloadRequest` expects (`public_key`, `signature`, `timestamp`,
  /// `nonce`) plus the caller's [accountId] for client-side correlation.
  ///
  /// [timestampIso] / [nonce] are optional for testability; production callers
  /// should let them default so each request gets a fresh timestamp + UUID
  /// (replay protection is enforced server-side).
  static Future<SignedDownloadRequest> createSignedRequest({
    required ProfileKeypair signingKeypair,
    required String accountId,
    required String scriptId,
    String? timestampIso,
    String? nonce,
  }) async {
    if (signingKeypair.algorithm != KeyAlgorithm.ed25519) {
      throw ArgumentError(
        'Paid download signing requires an Ed25519 keypair '
        '(got ${signingKeypair.algorithm}). secp256k1 is not supported '
        'for the download endpoint.',
      );
    }
    final timestamp = timestampIso ?? DateTime.now().toUtc().toIso8601String();
    final resolvedNonce = nonce ?? _uuid.v4();

    final payload = buildCanonicalPayload(
      scriptId: scriptId,
      timestamp: timestamp,
      nonce: resolvedNonce,
    );
    final signature = await _signEd25519(
      message: utf8.encode(payload),
      privateKeyB64: signingKeypair.privateKey,
    );

    return SignedDownloadRequest(
      accountId: accountId,
      publicKeyB64: signingKeypair.publicKey,
      signatureB64: signature,
      timestamp: timestamp,
      nonce: resolvedNonce,
    );
  }

  /// Sign a message with an Ed25519 private key (RFC 8032: sign the message
  /// directly; Ed25519 does SHA-512 internally). Returns base64.
  static Future<String> _signEd25519({
    required List<int> message,
    required String privateKeyB64,
  }) async {
    final algorithm = Ed25519();
    final privateKeyBytes = base64Decode(privateKeyB64);
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final signature = await algorithm.sign(message, keyPair: keyPair);
    return base64Encode(signature.bytes);
  }
}

/// The four signed fields consumed by `MarketplaceOpenApiService
/// .downloadPaidScriptBundle`, bundled with the caller's [accountId] for
/// high-level orchestration/logging. The wire body is exactly
/// `{public_key, signature, timestamp, nonce}` — [accountId] is NOT sent.
class SignedDownloadRequest {
  final String accountId;
  final String publicKeyB64;
  final String signatureB64;
  final String timestamp;
  final String nonce;

  const SignedDownloadRequest({
    required this.accountId,
    required this.publicKeyB64,
    required this.signatureB64,
    required this.timestamp,
    required this.nonce,
  });

  @override
  String toString() =>
      'SignedDownloadRequest{account: $accountId, publicKey: $publicKeyB64, '
      'timestamp: $timestamp, nonce: $nonce}';
}
