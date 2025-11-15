import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'test_signature_utils.dart';

/// HTTP client wrapper with timeout to prevent infinite hanging in tests
class _TimeoutClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Duration _timeout = const Duration(seconds: 10);

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

  TestableScriptRepository({
    String? baseUrl,
    http.Client? client,
    AuthenticationMethod authMethod = AuthenticationMethod.testToken,
    String? customAuthToken,
    bool forceInvalidAuth = false,
  }) : baseUrl = baseUrl ?? 'http://localhost:8787',
       _client = client ?? _TimeoutClient(),
       _authMethod = authMethod,
       _customAuthToken = customAuthToken,
       _forceInvalidAuth = forceInvalidAuth;

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    try {
      for (final script in scripts) {
        final scriptData = _createAuthenticatedScriptData(script, 'upload');

        final response = await _client.post(
          Uri.parse('$baseUrl/api/v1/scripts'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(scriptData),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      throw Exception('Failed to persist scripts: $e');
    }
  }

  Future<String> saveScript(ScriptRecord script) async {
    try {
      // First check if script exists
      final checkResponse = await _client.get(
        Uri.parse('$baseUrl/api/v1/scripts/${script.id}?includePrivate=true'),
      );

      if (checkResponse.statusCode == 200) {
        // Update existing script
        final updateData = _createAuthenticatedScriptData(script, 'update');
        updateData['script_id'] = script.id;

        final response = await _client.put(
          Uri.parse('$baseUrl/api/v1/scripts/${script.id}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updateData),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode} - ${response.body}');
        }

        return script.id;
      } else {
        // Create new script
        final scriptData = _createAuthenticatedScriptData(script, 'upload');

        final response = await _client.post(
          Uri.parse('$baseUrl/api/v1/scripts'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(scriptData),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode} - ${response.body}');
        }

        final responseData = json.decode(response.body);
        if (responseData['success'] == true && responseData['data'] != null) {
          return responseData['data']['id'] as String;
        }

        return script.id;
      }
    } catch (e) {
      throw Exception('Failed to save script: $e');
    }
  }

  Future<void> deleteScript(String id) async {
    try {
      final deleteData = _createAuthenticatedDeleteData(id);

      final response = await _client.delete(
        Uri.parse('$baseUrl/api/v1/scripts/$id'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(deleteData),
      );

      if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
        throw Exception('Failed to delete script $id: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to delete script: $e');
    }
  }

  Map<String, dynamic> _createAuthenticatedScriptData(ScriptRecord script, String action) {
    final baseScriptData = {
      'title': script.title,
      'description': script.metadata['description'] ?? '',
      'category': script.metadata['category'] ?? 'Development',
      'tags': script.metadata['tags'] ?? [],
      'lua_source': script.luaSource,
      'author_name': script.metadata['authorName'] ?? 'Anonymous',
      'author_id': script.metadata['authorId'] ?? 'test-author-id',
      'author_principal': script.metadata['authorPrincipal'] ?? '2vxsx-fae',
      'author_public_key': script.metadata['authorPublicKey'] ?? 'test-public-key-for-icp-compatibility',
      'upload_signature': script.metadata['uploadSignature'] ?? 'test-signature',
      'version': script.metadata['version'] ?? '1.0.0',
      'price': script.metadata['price'] ?? 0.0,
      'is_public': script.metadata['isPublic'] ?? false,
    };

    final scriptData = Map<String, dynamic>.from(baseScriptData);
    scriptData['action'] = action;

    // Add authentication based on the method
    switch (_authMethod) {
      case AuthenticationMethod.testToken:
        scriptData['signature'] = _customAuthToken ?? 'test-auth-token';
        break;

      case AuthenticationMethod.realSignature:
        final payload = {
          'action': action,
          ...baseScriptData,
          'timestamp': DateTime.now().toIso8601String(),
        };
        scriptData['signature'] = TestSignatureUtils.generateTestSignature(payload);
        scriptData['timestamp'] = payload['timestamp'];
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

  Map<String, dynamic> _createAuthenticatedDeleteData(String id) {
    final baseDeleteData = {
      'script_id': id,
      'author_principal': '2vxsx-fae',
    };

    switch (_authMethod) {
      case AuthenticationMethod.testToken:
        baseDeleteData['signature'] = _customAuthToken ?? 'test-auth-token';
        break;

      case AuthenticationMethod.realSignature:
        final timestamp = DateTime.now().toIso8601String();
        final payload = {
          'action': 'delete',
          'script_id': id,
          'author_principal': '2vxsx-fae',
          'timestamp': timestamp,
        };
        baseDeleteData['signature'] = TestSignatureUtils.generateTestSignature(payload);
        baseDeleteData['timestamp'] = timestamp;
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
}

enum AuthenticationMethod {
  testToken,
  realSignature,
  invalidToken,
  missingToken,
  malformedToken,
}