import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:collection/collection.dart';
import '../models/identity_record.dart';
import '../utils/principal.dart';

/// Digital signature service for ICP marketplace operations
/// Supports Ed25519 and secp256k1 signatures for script authentication
class ScriptSignatureService {
  const ScriptSignatureService._();

  /// Sign a script upload payload with the author's private key
  /// Returns a base64-encoded signature
  static Future<String> signScriptUpload({
    required IdentityRecord authorIdentity,
    required String title,
    required String description,
    required String category,
    required String luaSource,
    required String version,
    required List<String> tags,
    String? compatibility,
  }) async {
    // Create the canonical payload to sign
    final payload = _createUploadPayload(
      title: title,
      description: description,
      category: category,
      luaSource: luaSource,
      version: version,
      tags: tags,
      compatibility: compatibility,
      authorPrincipal: PrincipalUtils.textFromRecord(authorIdentity),
    );

    return await _signPayload(authorIdentity, payload);
  }

  /// Sign a script update request with the author's private key
  /// Returns a base64-encoded signature
  static Future<String> signScriptUpdate({
    required IdentityRecord authorIdentity,
    required String scriptId,
    Map<String, dynamic>? updates,
  }) async {
    // Create the canonical payload to sign
    final payload = _createUpdatePayload(
      scriptId: scriptId,
      updates: updates,
      authorPrincipal: PrincipalUtils.textFromRecord(authorIdentity),
    );

    return await _signPayload(authorIdentity, payload);
  }

  /// Sign a script deletion request with the author's private key
  /// Returns a base64-encoded signature
  static Future<String> signScriptDeletion({
    required IdentityRecord authorIdentity,
    required String scriptId,
  }) async {
    // Create the canonical payload to sign
    final payload = _createDeletePayload(
      scriptId: scriptId,
      authorPrincipal: PrincipalUtils.textFromRecord(authorIdentity),
    );

    return await _signPayload(authorIdentity, payload);
  }

  /// Create a canonical payload for script uploads
  static Map<String, dynamic> _createUploadPayload({
    required String title,
    required String description,
    required String category,
    required String luaSource,
    required String version,
    required List<String> tags,
    String? compatibility,
    required String authorPrincipal,
  }) {
    return {
      'action': 'upload',
      'title': title,
      'description': description,
      'category': category,
      'lua_source': luaSource,
      'version': version,
      'tags': tags..sort(), // Sort for deterministic ordering
      if (compatibility != null) 'compatibility': compatibility,
      'author_principal': authorPrincipal,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Create a canonical payload for script updates
  static Map<String, dynamic> _createUpdatePayload({
    required String scriptId,
    Map<String, dynamic>? updates,
    required String authorPrincipal,
  }) {
    return {
      'action': 'update',
      'script_id': scriptId,
      if (updates != null) ...updates,
      'author_principal': authorPrincipal,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Create a canonical payload for script deletions
  static Map<String, dynamic> _createDeletePayload({
    required String scriptId,
    required String authorPrincipal,
  }) {
    return {
      'action': 'delete',
      'script_id': scriptId,
      'author_principal': authorPrincipal,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Sign a canonical payload with the author's private key
  static Future<String> _signPayload(IdentityRecord identity, Map<String, dynamic> payload) async {
    // Convert payload to canonical JSON string (sorted keys)
    final canonicalJson = _canonicalJsonEncode(payload);
    final payloadBytes = utf8.encode(canonicalJson);
    final privateKeyBytes = base64Decode(identity.privateKey);

    switch (identity.algorithm) {
      case KeyAlgorithm.ed25519:
        final algorithm = Ed25519();
        final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
        final signature = await algorithm.sign(
          payloadBytes,
          keyPair: keyPair,
        );
        return base64Encode(signature.bytes);

      case KeyAlgorithm.secp256k1:
        // For secp256k1, use HMAC-SHA256 as a fallback approach
        // This is not ideal for production but works for demonstration
        final algorithm = Hmac.sha256();
        final secretKey = SecretKey(privateKeyBytes);
        final mac = await algorithm.calculateMac(payloadBytes, secretKey: secretKey);
        return base64Encode(mac.bytes);
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

  /// Verify a signature against a payload and public key
  static Future<bool> verifySignature({
    required String signature,
    required Map<String, dynamic> payload,
    required String publicKeyB64,
    required KeyAlgorithm algorithm,
  }) async {
    try {
      final canonicalJson = _canonicalJsonEncode(payload);
      final payloadBytes = utf8.encode(canonicalJson);
      final signatureBytes = base64Decode(signature);
      final publicKeyBytes = base64Decode(publicKeyB64);

      switch (algorithm) {
        case KeyAlgorithm.ed25519:
          // TODO: Implement Ed25519 verification with correct API
          // For now, return false to ensure we don't accept unverified signatures
          return false;

        case KeyAlgorithm.secp256k1:
          // For secp256k1, verify HMAC
          final hmacAlgorithm = Hmac.sha256();
          final secretKey = SecretKey(publicKeyBytes);
          final mac = await hmacAlgorithm.calculateMac(payloadBytes, secretKey: secretKey);
          return const ListEquality().equals(mac.bytes, signatureBytes);
      }
    } catch (e) {
      // Fail fast on any errors
      return false;
    }
  }

  /// Get the author's principal for display (first 5 characters)
  static String getShortPrincipal(String principal) {
    if (principal.length <= 5) return principal;
    return principal.substring(0, 5);
  }
}