import 'dart:convert';
import 'dart:typed_data';

/// Utility class for generating test signatures for development/testing
/// This mirrors the TestIdentity functionality from the Cloudflare API
class TestSignatureUtils {
  // Use deterministic keys for testing (compatible with ICP patterns)
  static const String _testPrivateKey = "test-secret-key-for-icp-compatibility";
  static const String _testPublicKey = "test-public-key-for-icp-compatibility";
  static const String _testPrincipal = "2vxsx-fae";

  /// Get test principal
  static String getPrincipal() => _testPrincipal;

  /// Get test public key
  static String getPublicKey() => _testPublicKey;

  /// Get test private key
  static String getPrivateKey() => _testPrivateKey;

  /// Create canonical JSON payload (deterministic ordering)
  /// This mirrors the SignatureVerifier.createCanonicalPayload function
  static String _createCanonicalPayload(Map<String, dynamic> payload) {
    final sortedKeys = payload.keys.toList()..sort();
    final sortedPayload = <String, dynamic>{};

    for (final key in sortedKeys) {
      final value = payload[key];
      if (value != null) {
        sortedPayload[key] = value;
      }
    }

    return json.encode(sortedPayload);
  }

  /// Generate a test signature compatible with the server's test signature verification
  /// This mirrors the server's TestIdentity.generateTestSignature function
  static String generateTestSignature(Map<String, dynamic> payload) {
    try {
      // Create canonical payload exactly as the verifier would
      final canonicalPayload = _createCanonicalPayload(payload);
      final messageBytes = utf8.encode(canonicalPayload);
      final keyBytes = utf8.encode(_testPrivateKey);

      // Use the same deterministic approach as the server's test identity
      int hash = 0;
      for (int i = 0; i < messageBytes.length; i++) {
        hash = ((hash << 5) - hash + messageBytes[i]) | 0;
      }
      for (int i = 0; i < keyBytes.length; i++) {
        hash = ((hash << 5) - hash + keyBytes[i]) | 0;
      }

      // Create deterministic signature bytes based on hash
      final signatureBytes = List<int>.filled(32, 0);
      for (int i = 0; i < 32; i++) {
        signatureBytes[i] = (hash + i) % 256;
      }

      final signatureBase64 = base64.encode(signatureBytes);

      print('Generated test signature: ${signatureBase64.substring(0, 20)}...');
      return signatureBase64;
    } catch (error) {
      print('Failed to generate test signature: $error');
      throw Exception('Test signature generation failed');
    }
  }

  /// Create a complete test script request with valid signature
  /// This mirrors TestIdentity.createTestScriptRequest
  static Map<String, dynamic> createTestScriptRequest({Map<String, dynamic>? overrides}) {
    final timestamp = DateTime.now().toIso8601String();
    final basePayload = {
      'title': 'Test Script',
      'description': 'A test script for development',
      'category': 'utility',
      'lua_source': 'print("Hello, World!")',
      'version': '1.0.0',
      'tags': ['test', 'utility'],
      'author_name': 'Test Author',
      'author_principal': getPrincipal(),
      'author_public_key': getPublicKey(),
      'timestamp': timestamp,
      'is_public': true,
    };

    final payload = {
      'action': 'upload',
      ...basePayload,
    };

    final signature = generateTestSignature(payload);

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
    final payload = {
      'action': 'update',
      'script_id': scriptId,
      'author_principal': getPrincipal(),
      'timestamp': timestamp,
      ...?updates,
    };

    final signature = generateTestSignature(payload);

    return {
      ...updates,
      'author_principal': getPrincipal(),
      'signature': signature,
      'timestamp': timestamp,
      ...?updates,
    };
  }

  /// Create a test delete request with valid signature
  /// This mirrors TestIdentity.createTestDeleteRequest
  static Map<String, dynamic> createTestDeleteRequest(String scriptId) {
    final timestamp = DateTime.now().toIso8601String();
    final payload = {
      'action': 'delete',
      'script_id': scriptId,
      'author_principal': getPrincipal(),
      'timestamp': timestamp,
    };

    final signature = generateTestSignature(payload);

    return {
      'author_principal': getPrincipal(),
      'signature': signature,
      'timestamp': timestamp,
    };
  }
}