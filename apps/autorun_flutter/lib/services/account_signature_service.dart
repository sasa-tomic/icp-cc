import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/identity_record.dart';
import '../models/account.dart';

/// Digital signature service for account management operations
///
/// Implements cryptographic signing per ACCOUNT_PROFILES_DESIGN.md:
/// 1. Construct canonical JSON (alphabetically ordered fields, no whitespace)
/// 2. UTF-8 encode to bytes
/// 3. Compute SHA-256 hash
/// 4. Sign hash with Ed25519 private key
/// 5. Encode signature as hex
class AccountSignatureService {
  const AccountSignatureService._();

  static const _uuid = Uuid();

  /// Create and sign a registration request
  static Future<RegisterAccountRequest> createRegisterAccountRequest({
    required IdentityRecord identity,
    required String username,
    required String displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    final timestamp = _getCurrentTimestamp();
    final nonce = _uuid.v4();
    final publicKeyHex = _publicKeyToHex(identity.publicKey);

    final request = RegisterAccountRequest(
      username: username,
      displayName: displayName,
      contactEmail: contactEmail,
      contactTelegram: contactTelegram,
      contactTwitter: contactTwitter,
      contactDiscord: contactDiscord,
      websiteUrl: websiteUrl,
      bio: bio,
      publicKey: publicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: '', // placeholder
    );

    final signature = await _signPayload(
      identity: identity,
      payload: request.toCanonicalPayload(),
    );

    return RegisterAccountRequest(
      username: username,
      displayName: displayName,
      contactEmail: contactEmail,
      contactTelegram: contactTelegram,
      contactTwitter: contactTwitter,
      contactDiscord: contactDiscord,
      websiteUrl: websiteUrl,
      bio: bio,
      publicKey: publicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: signature,
    );
  }

  /// Create and sign an add key request
  static Future<AddPublicKeyRequest> createAddPublicKeyRequest({
    required IdentityRecord signingIdentity,
    required String username,
    required String newPublicKeyB64,
  }) async {
    final timestamp = _getCurrentTimestamp();
    final nonce = _uuid.v4();
    final signingPublicKeyHex = _publicKeyToHex(signingIdentity.publicKey);
    final newPublicKeyHex = _publicKeyToHex(newPublicKeyB64);

    final request = AddPublicKeyRequest(
      username: username,
      newPublicKey: newPublicKeyHex,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: '', // placeholder
    );

    final signature = await _signPayload(
      identity: signingIdentity,
      payload: request.toCanonicalPayload(),
    );

    return AddPublicKeyRequest(
      username: username,
      newPublicKey: newPublicKeyHex,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: signature,
    );
  }

  /// Create and sign a remove key request
  static Future<RemovePublicKeyRequest> createRemovePublicKeyRequest({
    required IdentityRecord signingIdentity,
    required String username,
    required String keyId,
  }) async {
    final timestamp = _getCurrentTimestamp();
    final nonce = _uuid.v4();
    final signingPublicKeyHex = _publicKeyToHex(signingIdentity.publicKey);

    final request = RemovePublicKeyRequest(
      username: username,
      keyId: keyId,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: '', // placeholder
    );

    final signature = await _signPayload(
      identity: signingIdentity,
      payload: request.toCanonicalPayload(),
    );

    return RemovePublicKeyRequest(
      username: username,
      keyId: keyId,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: signature,
    );
  }

  /// Create and sign an update account request
  static Future<UpdateAccountRequest> createUpdateAccountRequest({
    required IdentityRecord signingIdentity,
    required String username,
    String? displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    final timestamp = _getCurrentTimestamp();
    final nonce = _uuid.v4();
    final signingPublicKeyHex = _publicKeyToHex(signingIdentity.publicKey);

    final request = UpdateAccountRequest(
      username: username,
      displayName: displayName,
      contactEmail: contactEmail,
      contactTelegram: contactTelegram,
      contactTwitter: contactTwitter,
      contactDiscord: contactDiscord,
      websiteUrl: websiteUrl,
      bio: bio,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: '', // placeholder
    );

    final signature = await _signPayload(
      identity: signingIdentity,
      payload: request.toCanonicalPayload(),
    );

    return UpdateAccountRequest(
      username: username,
      displayName: displayName,
      contactEmail: contactEmail,
      contactTelegram: contactTelegram,
      contactTwitter: contactTwitter,
      contactDiscord: contactDiscord,
      websiteUrl: websiteUrl,
      bio: bio,
      signingPublicKey: signingPublicKeyHex,
      timestamp: timestamp,
      nonce: nonce,
      signature: signature,
    );
  }

  /// Sign a canonical payload using standard cryptographic algorithms
  ///
  /// Process:
  /// 1. Encode payload to canonical JSON (sorted keys)
  /// 2. UTF-8 encode to bytes
  /// 3. Sign with algorithm-specific process:
  ///    - Ed25519: Sign message directly (standard RFC 8032)
  ///    - secp256k1: SHA-256 hash then sign (ECDSA requirement)
  /// 4. Hex encode the signature
  static Future<String> _signPayload({
    required IdentityRecord identity,
    required Map<String, dynamic> payload,
  }) async {
    // 1. Canonical JSON (sorted keys, no whitespace)
    final canonicalJson = _canonicalJsonEncode(payload);

    // 2. UTF-8 encode
    final payloadBytes = utf8.encode(canonicalJson);

    // 3. Sign (algorithm-specific)
    final privateKeyBytes = base64Decode(identity.privateKey);

    final signature = await _signMessage(
      messageBytes: payloadBytes,
      privateKeyBytes: privateKeyBytes,
      algorithm: identity.algorithm,
    );

    // 4. Hex encode
    return _bytesToHex(signature);
  }

  /// Sign a message with the private key (algorithm-specific)
  static Future<List<int>> _signMessage({
    required List<int> messageBytes,
    required List<int> privateKeyBytes,
    required KeyAlgorithm algorithm,
  }) async {
    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        // Standard Ed25519: sign message directly (RFC 8032)
        // The algorithm does SHA-512 internally as part of the signature process
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPairFromSeed(privateKeyBytes);
        final signature = await ed25519.sign(
          messageBytes,
          keyPair: keyPair,
        );
        return signature.bytes;

      case KeyAlgorithm.secp256k1:
        // Standard secp256k1: SHA-256 hash then sign (ECDSA requirement)
        // TODO: Implement secp256k1 with Rust FFI bridge
        throw UnimplementedError(
          'secp256k1 signatures require Rust FFI bridge - use Ed25519 for now',
        );
    }
  }

  /// Encode JSON with deterministic sorting for consistent signatures
  static String _canonicalJsonEncode(Map<String, dynamic> data) {
    final sortedMap = <String, dynamic>{};
    final sortedKeys = data.keys.toList()..sort();

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

  /// Get current Unix timestamp in seconds
  static int _getCurrentTimestamp() {
    return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  /// Convert base64 public key to hex (with 0x prefix)
  static String publicKeyToHex(String base64Key) {
    final bytes = base64Decode(base64Key);
    return '0x${_bytesToHex(bytes)}';
  }

  // Private alias for internal use
  static String _publicKeyToHex(String base64Key) => publicKeyToHex(base64Key);

  /// Convert bytes to hex string (without 0x prefix)
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Validate username format
  ///
  /// Rules:
  /// - Length: 3-32 characters
  /// - Characters: [a-z0-9_-] (lowercase alphanumeric, underscore, hyphen)
  /// - Format: Cannot start/end with hyphen or underscore
  /// - Regex: ^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$
  static UsernameValidation validateUsername(String username) {
    // Normalize: lowercase + trim
    final normalized = username.toLowerCase().trim();

    // Length check
    if (normalized.length < 3) {
      return UsernameValidation.invalid('Username must be at least 3 characters');
    }
    if (normalized.length > 32) {
      return UsernameValidation.invalid('Username must be at most 32 characters');
    }

    // Format check
    final regex = RegExp(r'^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$');
    if (!regex.hasMatch(normalized)) {
      if (normalized.startsWith('-') || normalized.startsWith('_')) {
        return UsernameValidation.invalid('Username cannot start with - or _');
      }
      if (normalized.endsWith('-') || normalized.endsWith('_')) {
        return UsernameValidation.invalid('Username cannot end with - or _');
      }
      return UsernameValidation.invalid('Username can only contain lowercase letters, numbers, - and _');
    }

    // Reserved usernames
    const reserved = <String>[
      'admin',
      'api',
      'system',
      'root',
      'support',
      'moderator',
      'icp',
      'administrator',
      'test',
      'null',
      'undefined',
    ];

    if (reserved.contains(normalized)) {
      return UsernameValidation.invalid('This username is reserved');
    }

    return UsernameValidation.valid;
  }

  /// Normalize username (lowercase + trim)
  static String normalizeUsername(String username) {
    return username.toLowerCase().trim();
  }
}
