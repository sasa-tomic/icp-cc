import 'dart:convert';
import 'package:cryptography/cryptography.dart';
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
    String? timestampIso,
  }) async {
    final String resolvedTimestamp =
        timestampIso ?? DateTime.now().toUtc().toIso8601String();

    final payload = _createUploadPayload(
      title: title,
      description: description,
      category: category,
      luaSource: luaSource,
      version: version,
      tags: tags,
      compatibility: compatibility,
      authorPrincipal: PrincipalUtils.textFromRecord(authorIdentity),
      timestampIso: resolvedTimestamp,
    );

    return await _signPayload(authorIdentity, payload);
  }

  /// Sign a script update request with the author's private key
  /// Returns a base64-encoded signature
  static Future<String> signScriptUpdate({
    required IdentityRecord authorIdentity,
    required String scriptId,
    Map<String, dynamic>? updates,
    String? timestampIso,
  }) async {
    final request = await buildSignedUpdateRequest(
      authorIdentity: authorIdentity,
      scriptId: scriptId,
      updates: updates ?? const {},
      timestampIso: timestampIso,
    );
    return request['signature'] as String;
  }

  /// Sign a script deletion request with the author's private key
  /// Returns a base64-encoded signature
  static Future<String> signScriptDeletion({
    required IdentityRecord authorIdentity,
    required String scriptId,
    String? timestampIso,
  }) async {
    _assertScriptId(scriptId);

    final String resolvedTimestamp =
        timestampIso ?? DateTime.now().toUtc().toIso8601String();

    // Create the canonical payload to sign
    final payload = _createDeletePayload(
      scriptId: scriptId,
      authorPrincipal: PrincipalUtils.textFromRecord(authorIdentity),
      timestampIso: resolvedTimestamp,
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
    required String timestampIso,
  }) {
    final List<String> sortedTags = List<String>.from(tags)..sort();
    return {
      'action': 'upload',
      'title': title,
      'description': description,
      'category': category,
      'lua_source': luaSource,
      'version': version,
      'tags': sortedTags,
      if (compatibility != null && compatibility.isNotEmpty)
        'compatibility': compatibility,
      'author_principal': authorPrincipal,
      'timestamp': timestampIso,
    };
  }

  /// Create a canonical payload for script updates
  static Map<String, dynamic> _createUpdatePayload({
    required String scriptId,
    Map<String, dynamic>? updates,
    required String authorPrincipal,
    required String timestampIso,
  }) {
    final Map<String, dynamic> payload = {
      'action': 'update',
      'script_id': scriptId,
      'timestamp': timestampIso,
      'author_principal': authorPrincipal,
    };

    if (updates != null) {
      payload.addAll(_sanitizeUpdateFields(updates));
    }

    return payload;
  }

  /// Create a canonical payload for script deletions
  static Map<String, dynamic> _createDeletePayload({
    required String scriptId,
    required String authorPrincipal,
    required String timestampIso,
  }) {
    return {
      'action': 'delete',
      'script_id': scriptId,
      'author_principal': authorPrincipal,
      'timestamp': timestampIso,
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
        // TODO: Implement proper secp256k1 ECDSA signature using Rust FFI
        // For now, throw to indicate this needs Rust bridge implementation
        // The elliptic Dart package doesn't provide the right signing API
        throw UnimplementedError(
          'secp256k1 signatures require Rust FFI bridge - use Ed25519 for now'
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

  static Map<String, dynamic> _sanitizeUpdateFields(
      Map<String, dynamic> updates) {
    const allowedKeys = <String>{
      'title',
      'description',
      'category',
      'lua_source',
      'version',
      'tags',
      'price',
      'is_public',
    };

    final Map<String, dynamic> sanitized = <String, dynamic>{};
    for (final entry in updates.entries) {
      final String key = entry.key;
      final dynamic value = entry.value;
      if (!allowedKeys.contains(key) || value == null) {
        continue;
      }

      if (key == 'tags') {
        if (value is List) {
          final List<String> sortedTags =
              value.map((dynamic e) => e.toString()).toList()..sort();
          sanitized[key] = sortedTags;
        }
        continue;
      }

      if (key == 'price') {
        if (value is num) {
          sanitized[key] = value.toDouble();
        } else {
          final double? parsed = double.tryParse(value.toString());
          if (parsed != null) {
            sanitized[key] = parsed;
          }
        }
        continue;
      }

      sanitized[key] = value;
    }

    return sanitized;
  }

  /// Prepare update fields for canonical signing and request payloads
  /// Ensures clients send exactly what gets signed.
  static Map<String, dynamic> canonicalizeUpdateFields(
      Map<String, dynamic> updates) {
    return _sanitizeUpdateFields(Map<String, dynamic>.from(updates));
  }

  /// Build a fully-signed update request payload that matches the canonical
  /// payload used for signature generation. Consumers should prefer this helper
  /// when constructing HTTP bodies to guarantee byte-for-byte parity with the
  /// signing input.
  static Future<Map<String, dynamic>> buildSignedUpdateRequest({
    required IdentityRecord authorIdentity,
    required String scriptId,
    required Map<String, dynamic> updates,
    String? timestampIso,
  }) async {
    _assertScriptId(scriptId);

    final Map<String, dynamic> sanitizedUpdates =
        _sanitizeUpdateFields(Map<String, dynamic>.from(updates));
    final String resolvedTimestamp =
        timestampIso ?? DateTime.now().toUtc().toIso8601String();
    final String authorPrincipal = PrincipalUtils.textFromRecord(authorIdentity);

    final Map<String, dynamic> canonicalPayload = _createUpdatePayload(
      scriptId: scriptId,
      updates: sanitizedUpdates,
      authorPrincipal: authorPrincipal,
      timestampIso: resolvedTimestamp,
    );

    final String signature =
        await _signPayload(authorIdentity, canonicalPayload);

    return {
      ...canonicalPayload,
      'author_public_key': authorIdentity.publicKey,
      'signature': signature,
    };
  }

  static void _assertScriptId(String scriptId) {
    if (scriptId.trim().isEmpty) {
      throw ArgumentError('scriptId must not be empty for signing operations');
    }
  }

  /// Verify a signature against a payload and public key
  /// Note: Verification is done on the server side
  static Future<bool> verifySignature({
    required String signature,
    required Map<String, dynamic> payload,
    required String publicKeyB64,
    required KeyAlgorithm algorithm,
  }) async {
    // Verification is done on the server side using proper cryptographic libraries
    // This client-side stub is kept for potential future local verification
    return false;
  }

  /// Get the author's principal for display (first 5 characters)
  static String getShortPrincipal(String principal) {
    if (principal.length <= 5) return principal;
    return principal.substring(0, 5);
  }
}
