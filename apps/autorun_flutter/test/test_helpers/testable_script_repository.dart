import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/services/script_signature_service.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'test_identity_factory.dart';
import 'http_response_utils.dart';

/// HTTP client wrapper with timeout to prevent infinite hanging in tests
class _TimeoutClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Duration _timeout = const Duration(seconds: 30);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return await _inner.send(request).timeout(_timeout);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Extended script repository that allows testing different authentication scenarios
class TestableScriptRepository extends ScriptRepository {
  final String baseUrl;
  final http.Client _client;
  final AuthenticationMethod _authMethod;
  final String? _customAuthToken;
  final bool _forceInvalidAuth;
  final KeyAlgorithm _signatureAlgorithm;

  TestableScriptRepository({
    String? baseUrl,
    http.Client? client,
    AuthenticationMethod authMethod = AuthenticationMethod.testToken,
    String? customAuthToken,
    bool forceInvalidAuth = false,
    KeyAlgorithm signatureAlgorithm = KeyAlgorithm.ed25519,
  }) : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
       _client = client ?? _TimeoutClient(),
       _authMethod = authMethod,
       _customAuthToken = customAuthToken,
       _forceInvalidAuth = forceInvalidAuth,
       _signatureAlgorithm = signatureAlgorithm;

  static String _getDefaultBaseUrl() {
    try {
      final portFile = File('/tmp/icp-api.port');
      if (portFile.existsSync()) {
        final port = portFile.readAsStringSync().trim();
        return 'http://127.0.0.1:$port';
      }
    } catch (e) {
      // Fall through to exception below
    }
    throw Exception(
      'API server port file not found at /tmp/icp-api.port. '
      'Please start the API server with: just api-up'
    );
  }

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    _ensureValidAuthentication('persist scripts');

    try {
      for (final script in scripts) {
        final scriptData = await _createAuthenticatedScriptData(script, 'upload');

        final response = await _client.post(
          Uri.parse('$baseUrl/api/v1/scripts'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(scriptData),
        );

        ensureSuccessStatus(
          response: response,
          operation: 'Failed to save script ${script.id}',
        );

        _assertSuccessfulMutation(response, 'persist script ${script.id}');
      }
    } catch (e) {
      throw Exception('Failed to persist scripts: $e');
    }
  }

  Future<String> saveScript(ScriptRecord script) async {
    _ensureValidAuthentication('save script ${script.id}');

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // First check if script exists
        final checkResponse = await _client.get(
          Uri.parse('$baseUrl/api/v1/scripts/${script.id}?includePrivate=true'),
        );

        if (checkResponse.statusCode == 200) {
          // Update existing script
          final updateData = await _createAuthenticatedScriptData(
            script,
            'update',
            scriptId: script.id,
          );

          final response = await _client.put(
            Uri.parse('$baseUrl/api/v1/scripts/${script.id}'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updateData),
          );

          if (response.statusCode != 200 && response.statusCode != 201) {
            throwDetailedHttpException(
              operation: 'Failed to save script ${script.id}',
              response: response,
            );
          }

          _assertSuccessfulMutation(response, 'update script ${script.id}');
          return script.id;
        } else {
          // Create new script
          final scriptData = await _createAuthenticatedScriptData(script, 'upload');

          final response = await _client.post(
            Uri.parse('$baseUrl/api/v1/scripts'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(scriptData),
          );

          if (response.statusCode != 200 && response.statusCode != 201) {
            throwDetailedHttpException(
              operation: 'Failed to save script ${script.id}',
              response: response,
            );
          }

          _assertSuccessfulMutation(response, 'create script ${script.id}');
          final responseData = json.decode(response.body);
          if (responseData['success'] == true && responseData['data'] != null) {
            return responseData['data']['id'] as String;
          }

          return script.id;
        }
      } catch (e) {
        // Don't retry authentication errors or client errors (4xx)
        if (e.toString().contains('401') ||
            e.toString().contains('403') ||
            e.toString().contains('400') ||
            e.toString().contains('404')) {
          rethrow;
        }

        if (attempt == maxRetries - 1) {
          throw Exception('Failed to save script after $maxRetries attempts: $e');
        }

        // Wait before retrying
        await Future.delayed(retryDelay * (attempt + 1));
      }
    }

    throw Exception('Failed to save script: unknown error');
  }

  Future<void> deleteScript(String id) async {
    _ensureValidAuthentication('delete script $id');

    try {
      final deleteData = await _createAuthenticatedDeleteData(id);

      final response = await _client.delete(
        Uri.parse('$baseUrl/api/v1/scripts/$id'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(deleteData),
      );

      if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
        throwDetailedHttpException(
          operation: 'Failed to delete script $id',
          response: response,
        );
      }
    } catch (e) {
      // Rethrow with original exception details
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _createAuthenticatedScriptData(
    ScriptRecord script,
    String action, {
    String? scriptId,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();

    final List<String> tags = _normalizeTags(script.metadata['tags']);
    final String version = (script.metadata['version'] ?? '1.0.0').toString();

    final baseScriptData = {
      'title': script.title,
      'description': script.metadata['description'] ?? '',
      'category': script.metadata['category'] ?? 'Development',
      'tags': tags,
      'lua_source': script.luaSource,
      'author_name': script.metadata['authorName'] ?? 'Anonymous',
      'author_id': script.metadata['authorId'] ?? 'test-author-id',
      'author_principal': script.metadata['authorPrincipal'] ?? '2vxsx-fae',
      'author_public_key': script.metadata['authorPublicKey'] ?? 'test-public-key-for-icp-compatibility',
      'upload_signature': script.metadata['uploadSignature'] ?? 'test-signature',
      'version': version,
      'price': script.metadata['price'] ?? 0.0,
      'is_public': script.metadata['isPublic'] ?? false,
      'timestamp': timestamp, // Always include timestamp
    };

    final scriptData = Map<String, dynamic>.from(baseScriptData);
    scriptData['action'] = action;
    if (scriptId != null) {
      scriptData['script_id'] = scriptId;
    }

    // Add authentication based on the method
    switch (_authMethod) {
      case AuthenticationMethod.testToken:
        scriptData['signature'] = _customAuthToken ?? 'test-auth-token';
        break;

      case AuthenticationMethod.realSignature:
        // Use real cryptographic signature (Ed25519 or secp256k1)
        final identity = await TestIdentityFactory.getIdentity(_signatureAlgorithm);
        final principal = PrincipalUtils.textFromRecord(identity);

        // Update with real principal and public key
        scriptData['author_principal'] = principal;
        scriptData['author_public_key'] = identity.publicKey;

        // Create signature based on the action type
        final String signature;
        if (action == 'upload') {
          signature = await ScriptSignatureService.signScriptUpload(
            authorIdentity: identity,
            title: scriptData['title'],
            description: scriptData['description'],
            category: scriptData['category'],
            luaSource: scriptData['lua_source'],
            version: scriptData['version'],
            tags: List<String>.from(scriptData['tags'] ?? const <String>[]),
            timestampIso: timestamp,
          );
        } else if (action == 'update') {
          final String? resolvedScriptId = scriptData['script_id'] as String?;
          if (resolvedScriptId == null || resolvedScriptId.isEmpty) {
            throw Exception('script_id is required for authenticated update signing');
          }
          final Map<String, dynamic> signedUpdate =
              await ScriptSignatureService.buildSignedUpdateRequest(
            authorIdentity: identity,
            scriptId: resolvedScriptId,
            updates: scriptData,
            timestampIso: timestamp,
          );
          scriptData
            ..removeWhere((key, _) => signedUpdate.containsKey(key))
            ..addAll(signedUpdate);
          signature = signedUpdate['signature'] as String;
        } else {
          // Default to upload signature for unknown actions
          signature = await ScriptSignatureService.signScriptUpload(
            authorIdentity: identity,
            title: scriptData['title'],
            description: scriptData['description'],
            category: scriptData['category'],
            luaSource: scriptData['lua_source'],
            version: scriptData['version'],
            tags: List<String>.from(scriptData['tags'] ?? const <String>[]),
            timestampIso: timestamp,
          );
        }

        scriptData['signature'] = signature;
        if (action == 'upload') {
          scriptData['upload_signature'] = signature;
        }
        break;

      case AuthenticationMethod.invalidToken:
        scriptData['signature'] = 'invalid-auth-token';
        break;

      case AuthenticationMethod.missingToken:
        // Don't add signature field
        break;

      case AuthenticationMethod.malformedToken:
        scriptData['signature'] = '';
        break;
    }

    if (_forceInvalidAuth) {
      scriptData['author_principal'] = 'invalid-principal';
      scriptData['author_public_key'] = 'invalid-public-key';
    }

    return scriptData;
  }

  Future<Map<String, dynamic>> _createAuthenticatedDeleteData(String id) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    
    final baseDeleteData = {
      'script_id': id,
      'author_principal': '2vxsx-fae',
      'timestamp': timestamp, // Always include timestamp
    };

    switch (_authMethod) {
      case AuthenticationMethod.testToken:
        baseDeleteData['signature'] = _customAuthToken ?? 'test-auth-token';
        break;

      case AuthenticationMethod.realSignature:
        // Use real cryptographic signature (Ed25519 or secp256k1)
        final identity = await TestIdentityFactory.getIdentity(_signatureAlgorithm);
        final principal = PrincipalUtils.textFromRecord(identity);

        // Update with real principal and public key
        baseDeleteData['author_principal'] = principal;
        baseDeleteData['author_public_key'] = identity.publicKey;

        // Create signature using ScriptSignatureService
        final signature = await ScriptSignatureService.signScriptDeletion(
          authorIdentity: identity,
          scriptId: id,
          timestampIso: timestamp,
        );

        baseDeleteData['signature'] = signature;
        break;

      case AuthenticationMethod.invalidToken:
        baseDeleteData['signature'] = 'invalid-auth-token';
        break;

      case AuthenticationMethod.missingToken:
        // Don't add signature field
        break;

      case AuthenticationMethod.malformedToken:
        baseDeleteData['signature'] = '';
        break;
    }

    if (_forceInvalidAuth) {
      baseDeleteData['author_principal'] = 'invalid-principal';
    }

    return baseDeleteData;
  }

  @override
  Future<List<ScriptRecord>> loadScripts() async {
    throw UnimplementedError('loadScripts not implemented for test repository');
  }

  Future<List<ScriptRecord>> getAllScripts() async {
    throw UnimplementedError('getAllScripts not implemented for test repository');
  }

  void dispose() {
    _client.close();
  }

  void _ensureValidAuthentication(String operation) {
    final hasInvalidCredentials = _authMethod == AuthenticationMethod.invalidToken ||
        _authMethod == AuthenticationMethod.missingToken ||
        _authMethod == AuthenticationMethod.malformedToken ||
        _forceInvalidAuth;

    if (hasInvalidCredentials) {
      final reason = _forceInvalidAuth
          ? 'invalid principal or public key'
          : 'authentication method $_authMethod';
      throw Exception('401 Unauthorized: $operation rejected due to $reason');
    }
  }

  void _assertSuccessfulMutation(http.Response response, String operation) {
    if (response.body.isEmpty) {
      return;
    }

    try {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final success = decoded['success'];
        if (success is bool && !success) {
          throwDetailedHttpException(
            operation: 'Failed to $operation',
            response: response,
          );
        }
      }
    } catch (error) {
      // Ignore JSON parsing issues when response is not JSON
    }
  }
}

enum AuthenticationMethod {
  testToken,
  realSignature,
  invalidToken,
  missingToken,
  malformedToken,
}

List<String> _normalizeTags(dynamic rawTags) {
  if (rawTags is List) {
    return rawTags.map((dynamic value) => value.toString()).toList();
  }
  return <String>[];
}
