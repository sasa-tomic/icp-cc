import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
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

  /// Generate a real cryptographic Ed25519 test signature (synchronous after
  /// initialization). Requires calling `ensureInitialized()` first.
  ///
  /// Uses `package:ed25519_edwards` (pure-Dart, synchronous, RFC 8032) — the
  /// SAME independent Ed25519 implementation already trusted as the reference
  /// verifier in `test/features/web/ed25519_principal_test.dart`. Ed25519 is
  /// deterministic, so this produces a signature byte-equal to the async
  /// `generateTestSignature` over the same payload+seed, and it VERIFIES
  /// against the keypair's public key. No mocked/fake cryptography.
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

  /// Internal method to generate a REAL Ed25519 signature synchronously.
  ///
  /// Signs the canonical-JSON payload bytes with the keypair's Ed25519 seed via
  /// `package:ed25519_edwards` (pure-Dart, RFC 8032). The resulting signature
  /// verifies against the keypair's public key and is byte-equal to the async
  /// `cryptography`-based signature over the same input.
  ///
  /// NOTE: This previously emitted a non-cryptographic DJB2-style hash (a
  /// forbidden "mocked cryptography" pattern) — see W6-11. It now uses genuine
  /// Ed25519, consistent with the async path and AGENTS.md.
  static String _generateSignatureSyncInternal(
    ProfileKeypair keypair,
    Map<String, dynamic> payload,
  ) {
    if (keypair.algorithm != KeyAlgorithm.ed25519) {
      throw UnimplementedError(
          'Only Ed25519 is supported for sync test signatures');
    }

    final canonicalJson = _canonicalJsonEncode(payload);
    final payloadBytes = Uint8List.fromList(utf8.encode(canonicalJson));
    final seedBytes = Uint8List.fromList(base64Decode(keypair.privateKey));

    // ed25519_edwards PrivateKey is seed(32) || pub(32) (Go convention) — see
    // lib/rust/native_bridge_web.dart:_ed25519PublicKeyFromSeed. We derive the
    // full private key from the seed so the public-key half is correct and the
    // signature matches the keypair's stored public key.
    final privateKey = ed.newKeyFromSeed(seedBytes);
    final signature = ed.sign(privateKey, payloadBytes);

    return base64Encode(signature);
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
      'slug': 'test-script',
      'title': 'Test Script',
      'description': 'A test script for development',
      'category': 'utility',
      'bundle': 'print("Hello, World!")',
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
