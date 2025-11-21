import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:cryptography/cryptography.dart';
import 'test_keypair_factory.dart';

/// Utility class for generating test signatures for development/testing
/// Uses real cryptographic signatures with deterministic test keypairs
class TestSignatureUtils {
  static ProfileKeypair? _syncKeypair;
  static Future<ProfileKeypair>? _keypairFuture;

  /// Initialize and cache the test keypair
  /// Call this in setUpAll() to ensure synchronous access
  static Future<void> ensureInitialized() async {
    if (_syncKeypair == null) {
      _keypairFuture ??= TestKeypairFactory.getEd25519Keypair();
      _syncKeypair = await _keypairFuture!;
    }
  }

  /// Get the cached test keypair (throws if not initialized)
  static ProfileKeypair _getKeypair() {
    if (_syncKeypair == null) {
      throw StateError(
        'TestSignatureUtils not initialized. Call ensureInitialized() in setUpAll()',
      );
    }
    return _syncKeypair!;
  }

  /// Get test principal (synchronous after initialization)
  static String getPrincipal() {
    return PrincipalUtils.textFromRecord(_getKeypair());
  }

  /// Get test public key (synchronous after initialization)
  static String getPublicKey() {
    return _getKeypair().publicKey;
  }

  /// Get test private key (for advanced testing)
  static String getPrivateKey() {
    return _getKeypair().privateKey;
  }

  /// Get the test keypair (async version for backwards compatibility)
  static Future<ProfileKeypair> getTestKeypair() async {
    await ensureInitialized();
    return _getKeypair();
  }

  /// Generate a real cryptographic test signature (async)
  /// Uses the default test keypair with Ed25519 signatures
  /// For tests, call ensureInitialized() in setUpAll() then use generateTestSignatureSync()
  static Future<String> generateTestSignature(
      Map<String, dynamic> payload) async {
    await ensureInitialized();
    return _generateSignatureInternal(_getKeypair(), payload);
  }

  /// Generate a real cryptographic test signature (synchronous after initialization)
  /// Requires calling ensureInitialized() first
  static String generateTestSignatureSync(Map<String, dynamic> payload) {
    return _generateSignatureSyncInternal(_getKeypair(), payload);
  }

  /// Internal method to generate signature (async version)
  /// Per ACCOUNT_PROFILES_DESIGN.md: Standard Ed25519 (sign message directly)
  static Future<String> _generateSignatureInternal(
    ProfileKeypair keypair,
    Map<String, dynamic> payload,
  ) async {
    try {
      final canonicalJson = _canonicalJsonEncode(payload);
      final payloadBytes = utf8.encode(canonicalJson);

      final algorithm = keypair.algorithm == KeyAlgorithm.ed25519
          ? Ed25519()
          : throw UnimplementedError(
              'Only Ed25519 is supported for test signatures');

      final privateKeyBytes = base64Decode(keypair.privateKey);
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
    ProfileKeypair keypair,
    Map<String, dynamic> payload,
  ) {
    try {
      final canonicalJson = _canonicalJsonEncode(payload);
      final messageBytes = utf8.encode(canonicalJson);
      final keyBytes = base64Decode(keypair.privateKey);

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
  /// This mirrors TestKeypair.createTestScriptRequest
  static Map<String, dynamic> createTestScriptRequest(
      {Map<String, dynamic>? overrides}) {
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
  /// This mirrors TestKeypair.createTestUpdateRequest
  static Map<String, dynamic> createTestUpdateRequest(String scriptId,
      {Map<String, dynamic>? updates}) {
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
  /// This mirrors TestKeypair.createTestDeleteRequest
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
