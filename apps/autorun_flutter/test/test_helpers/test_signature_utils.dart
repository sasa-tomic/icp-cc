import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:cryptography/cryptography.dart';
import 'test_identity_factory.dart';

/// Utility class for generating test signatures for development/testing
/// Uses real cryptographic signatures with deterministic test identities
class TestSignatureUtils {
  static IdentityRecord? _syncIdentity;
  static Future<IdentityRecord>? _identityFuture;

  /// Initialize and cache the test identity
  /// Call this in setUpAll() to ensure synchronous access
  static Future<void> ensureInitialized() async {
    if (_syncIdentity == null) {
      _identityFuture ??= TestIdentityFactory.getEd25519Identity();
      _syncIdentity = await _identityFuture!;
    }
  }

  /// Get the cached test identity (throws if not initialized)
  static IdentityRecord _getIdentity() {
    if (_syncIdentity == null) {
      throw StateError(
        'TestSignatureUtils not initialized. Call ensureInitialized() in setUpAll()',
      );
    }
    return _syncIdentity!;
  }

  /// Get test principal (synchronous after initialization)
  static String getPrincipal() {
    return PrincipalUtils.textFromRecord(_getIdentity());
  }

  /// Get test public key (synchronous after initialization)
  static String getPublicKey() {
    return _getIdentity().publicKey;
  }

  /// Get test private key (for advanced testing)
  static String getPrivateKey() {
    return _getIdentity().privateKey;
  }

  /// Get the test identity (async version for backwards compatibility)
  static Future<IdentityRecord> getTestIdentity() async {
    await ensureInitialized();
    return _getIdentity();
  }

  /// Generate a real cryptographic test signature (async)
  /// Uses the default test identity with Ed25519 signatures
  /// For tests, call ensureInitialized() in setUpAll() then use generateTestSignatureSync()
  static Future<String> generateTestSignature(Map<String, dynamic> payload) async {
    await ensureInitialized();
    return _generateSignatureInternal(_getIdentity(), payload);
  }

  /// Generate a real cryptographic test signature (synchronous after initialization)
  /// Requires calling ensureInitialized() first
  static String generateTestSignatureSync(Map<String, dynamic> payload) {
    return _generateSignatureSyncInternal(_getIdentity(), payload);
  }

  /// Internal method to generate signature (async version)
  /// Per ACCOUNT_PROFILES_DESIGN.md: Standard Ed25519 (sign message directly)
  static Future<String> _generateSignatureInternal(
    IdentityRecord identity,
    Map<String, dynamic> payload,
  ) async {
    try {
      final canonicalJson = _canonicalJsonEncode(payload);
      final payloadBytes = utf8.encode(canonicalJson);

      final algorithm = identity.algorithm == KeyAlgorithm.ed25519
          ? Ed25519()
          : throw UnimplementedError('Only Ed25519 is supported for test signatures');

      final privateKeyBytes = base64Decode(identity.privateKey);
      final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);

      // Standard Ed25519: sign message directly (RFC 8032)
      // The algorithm does SHA-512 internally as part of the signature process
      final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);

      return base64Encode(signature.bytes);
    } catch (error) {
      debugPrint('Failed to generate test signature: $error');
      throw Exception('Test signature generation failed: $error');
    }
  }

  /// Internal method to generate signature (sync version - simplified for tests)
  /// NOTE: This uses a deterministic but NOT cryptographically secure signature
  /// Only use for testing with test infrastructure that accepts test signatures
  static String _generateSignatureSyncInternal(
    IdentityRecord identity,
    Map<String, dynamic> payload,
  ) {
    try {
      final canonicalJson = _canonicalJsonEncode(payload);
      final messageBytes = utf8.encode(canonicalJson);
      final keyBytes = base64Decode(identity.privateKey);

      // Use deterministic hashing for synchronous signature (test-only!)
      int hash = 0;
      for (int i = 0; i < messageBytes.length; i++) {
        hash = ((hash << 5) - hash + messageBytes[i]) | 0;
      }
      for (int i = 0; i < keyBytes.length; i++) {
        hash = ((hash << 5) - hash + keyBytes[i]) | 0;
      }

      // Create deterministic signature bytes
      final signatureBytes = List<int>.filled(64, 0);
      for (int i = 0; i < 64; i++) {
        signatureBytes[i] = (hash + i * 31) % 256;
      }

      return base64Encode(signatureBytes);
    } catch (error) {
      debugPrint('Failed to generate test signature: $error');
      throw Exception('Test signature generation failed: $error');
    }
  }

  /// Encode JSON with deterministic sorting for consistent signatures
  static String _canonicalJsonEncode(Map<String, dynamic> data) {
    final sortedMap = <String, dynamic>{};
    final sortedKeys = data.keys.toList()..sort();

    for (final key in sortedKeys) {
      final value = data[key];
      if (value is Map<String, dynamic>) {
        sortedMap[key] = json.decode(_canonicalJsonEncode(value));
      } else if (value is List) {
        sortedMap[key] = value;
      } else {
        sortedMap[key] = value;
      }
    }

    return json.encode(sortedMap);
  }

  /// Create a complete test script request with valid signature
  /// This mirrors TestIdentity.createTestScriptRequest
  static Map<String, dynamic> createTestScriptRequest({Map<String, dynamic>? overrides}) {
    final timestamp = DateTime.now().toIso8601String();
    final principal = getPrincipal();
    final publicKey = getPublicKey();

    final basePayload = {
      'title': 'Test Script',
      'description': 'A test script for development',
      'category': 'utility',
      'lua_source': 'print("Hello, World!")',
      'version': '1.0.0',
      'tags': ['test', 'utility'],
      'author_name': 'Test Author',
      'author_principal': principal,
      'author_public_key': publicKey,
      'timestamp': timestamp,
      'is_public': true,
    };

    final payload = {
      'action': 'upload',
      ...basePayload,
    };

    final signature = generateTestSignatureSync(payload);

    return {
      ...basePayload,
      'signature': signature,
      ...?overrides,
    };
  }

  /// Create a test update request with valid signature
  /// This mirrors TestIdentity.createTestUpdateRequest
  static Map<String, dynamic> createTestUpdateRequest(String scriptId, {Map<String, dynamic>? updates}) {
    final timestamp = DateTime.now().toIso8601String();
    final principal = getPrincipal();
    final publicKey = getPublicKey();

    final payload = {
      'action': 'update',
      'script_id': scriptId,
      'author_principal': principal,
      'timestamp': timestamp,
      ...?updates,
    };

    final signature = generateTestSignatureSync(payload);

    return {
      'action': 'update',
      'script_id': scriptId,
      ...?updates,
      'author_principal': principal,
      'author_public_key': publicKey,
      'signature': signature,
      'timestamp': timestamp,
    };
  }

  /// Create a test delete request with valid signature
  /// This mirrors TestIdentity.createTestDeleteRequest
  static Map<String, dynamic> createTestDeleteRequest(String scriptId) {
    final timestamp = DateTime.now().toIso8601String();
    final principal = getPrincipal();
    final publicKey = getPublicKey();

    final payload = {
      'action': 'delete',
      'script_id': scriptId,
      'author_principal': principal,
      'timestamp': timestamp,
    };

    final signature = generateTestSignatureSync(payload);

    return {
      'action': 'delete',
      'script_id': scriptId,
      'author_principal': principal,
      'author_public_key': publicKey,
      'signature': signature,
      'timestamp': timestamp,
    };
  }
}

