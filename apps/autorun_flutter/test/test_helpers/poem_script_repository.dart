import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'test_signature_utils.dart';

/// Repository implementation that uses the Poem API server for end-to-end tests.
class PoemScriptRepository extends ScriptRepository {
  final String baseUrl;
  final http.Client _client;

  PoemScriptRepository({
    String? baseUrl,
    http.Client? client,
  }) : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
       _client = client ?? http.Client();

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
  Future<List<ScriptRecord>> loadScripts() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/api/v1/scripts'));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final Map<String, dynamic> responseData = data['data'];
          if (responseData['scripts'] != null) {
            final List<dynamic> scriptsJson = responseData['scripts'];
            return scriptsJson.map((json) => _scriptFromJson(json)).toList();
          }
        }
        return [];
      } else {
        throw Exception('Failed to load scripts: ${response.statusCode}');
      }
    } catch (e) {
      // For e2e tests, fail if server is not available
      throw Exception('Failed to load scripts: $e');
    }
  }

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    try {
      for (final script in scripts) {
        // Use simplified authorization token for persistScripts
        final baseScriptData = _scriptToApiJson(script);

        // Create the final script data with simple auth token
        final scriptData = Map<String, dynamic>.from(baseScriptData);
        scriptData['signature'] = 'test-auth-token';
        scriptData['action'] = 'upload';


        final response = await _client.post(
          Uri.parse('$baseUrl/api/v1/scripts'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(scriptData),
        );


        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode}');
        }

        _assertSuccessfulMutation(response, 'persist script ${script.id}');
      }
    } catch (e) {
      // For e2e tests, fail if server is not available
      throw Exception('Failed to persist scripts: $e');
    }
  }



  Map<String, dynamic> _scriptToApiJson(ScriptRecord script) {
    // Always generate a fresh timestamp for the API request
    final timestamp = DateTime.now().toUtc().toIso8601String();

    return {
      'title': script.title,
      'description': script.metadata['description'] ?? '',
      'category': script.metadata['category'] ?? 'Development',
      'tags': (script.metadata['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .toList(),
      'lua_source': script.luaSource,
      'author_name': script.metadata['authorName'] ?? 'Anonymous',
      'author_id': script.metadata['authorId'] ?? 'test-author-id',
      'author_principal': script.metadata['authorPrincipal'] ?? '2vxsx-fae',
      'author_public_key': script.metadata['authorPublicKey'] ?? 'test-public-key-for-icp-compatibility',
      'upload_signature': script.metadata['uploadSignature'] ?? 'test-signature',
      'signature': script.metadata['signature'] ?? 'test-signature',
      'timestamp': timestamp,
      'version': (script.metadata['version'] ?? '1.0.0').toString(),
      'price': script.metadata['price'] ?? 0.0,
      'is_public': script.metadata['isPublic'] ?? false,
    };
  }

  ScriptRecord _scriptFromJson(Map<String, dynamic> json) {
    // Handle null or malformed JSON gracefully
    if (json.isEmpty) {
      throw Exception('Empty JSON data');
    }
    
    final id = json['id'];
    final title = json['title'];
    if (id == null || title == null) {
      throw Exception('Missing required fields: id or title');
    }
    
    return ScriptRecord(
      id: id.toString(),
      title: title.toString(),
      luaSource: json['lua_source']?.toString() ?? '',
      metadata: {
        'description': json['description']?.toString() ?? '',
        'category': json['category']?.toString() ?? 'Development',
        'tags': json['tags'] is List ? json['tags'] as List<dynamic> : [],
        'authorName': json['author_name']?.toString() ?? 'Anonymous',
        'version': json['version']?.toString() ?? '1.0.0',
        'price': (json['price'] as num?)?.toDouble() ?? 0.0,
        'isPublic': _parseBool(json['is_public']),
        'downloads': (json['downloads'] as int?) ?? 0,
        'rating': (json['rating'] as num?)?.toDouble() ?? 0.0,
        'reviewCount': (json['review_count'] as int?) ?? 0,
        ...json['metadata'] is Map ? json['metadata'] as Map<String, dynamic> : {},
      },
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }
  
  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1';
    }
    return false;
  }

  /// Additional methods for testing purposes
  Future<ScriptRecord?> getScriptById(String id, {bool includePrivate = true}) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/api/v1/scripts/$id?includePrivate=true'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && 
            data['success'] == true && 
            data['data'] != null &&
            data['data'] is Map<String, dynamic>) {
          return _scriptFromJson(data['data'] as Map<String, dynamic>);
        }
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get script: ${response.statusCode}');
      }
    } catch (e) {
      // For e2e tests, fail if server is not available
      if (e.toString().contains('Connection') || e.toString().contains('SocketException')) {
        throw Exception('Failed to get script: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteScript(String id) async {
    try {
      // Generate proper signature for script deletion
      final deleteData = TestSignatureUtils.createTestDeleteRequest(id);

      final response = await _client.delete(
        Uri.parse('$baseUrl/api/v1/scripts/$id'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(deleteData),
      );

      if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
        throw Exception('Failed to delete script $id: ${response.statusCode}');
      }

      _assertSuccessfulMutation(response, 'delete script $id');
    } catch (e) {
      throw Exception('Failed to delete script: $e');
    }
  }

  Future<List<ScriptRecord>> searchScripts(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/scripts/search?q=${Uri.encodeComponent(query)}')
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final Map<String, dynamic> responseData = data['data'];
          if (responseData['scripts'] != null) {
            final List<dynamic> scriptsJson = responseData['scripts'];
            return scriptsJson.map((json) => _scriptFromJson(json)).toList();
          }
        }
        return [];
      } else {
        return [];
      }
    } catch (e) {
      throw Exception('Failed to search scripts: $e');
    }
  }

  Future<List<ScriptRecord>> getScriptsByCategory(String category) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/scripts/category/${Uri.encodeComponent(category)}')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && 
            data['success'] == true && 
            data['data'] != null &&
            data['data'] is List) {
          final List<dynamic> scriptsJson = data['data'] as List<dynamic>;
          return scriptsJson
              .whereType<Map<String, dynamic>>()
              .map((json) => _scriptFromJson(json))
              .toList();
        }
        return [];
      } else {
        return [];
      }
    } catch (e) {
      // Return empty list instead of throwing for graceful error handling
      return [];
    }
  }

  Future<List<ScriptRecord>> getPublicScripts() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/scripts?public=true')
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final Map<String, dynamic> responseData = data['data'];
          if (responseData['scripts'] != null) {
            final List<dynamic> scriptsJson = responseData['scripts'];
            return scriptsJson.map((json) => _scriptFromJson(json)).toList();
          }
        }
        return [];
      } else {
        return [];
      }
    } catch (e) {
      throw Exception('Failed to get public scripts: $e');
    }
  }

  Future<String> publishScript(ScriptRecord script) async {
    try {
      final updatedScript = ScriptRecord(
        id: script.id,
        title: script.title,
        luaSource: script.luaSource,
        metadata: {...script.metadata, 'isPublic': true},
        createdAt: script.createdAt,
        updatedAt: DateTime.now(),
      );

      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/scripts/${script.id}/publish'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(_scriptToApiJson(updatedScript)),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['id'] as String? ?? script.id;
        }
        throw Exception('Failed to publish script: unexpected response');
      } else {
        throw Exception('Failed to publish script: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to publish script: $e');
    }
  }

  Future<int> getScriptsCount() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/api/v1/scripts/count'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final dynamic countValue = (data['data'] as Map<String, dynamic>)['count'] ??
              (data['data'] as Map<String, dynamic>)['total'] ??
              (data['data'] as Map<String, dynamic>)['scripts_count'];
          if (countValue is int) {
            return countValue;
          }
          if (countValue is num) {
            return countValue.toInt();
          }
          throw Exception('Unexpected count response: ${data['data']}');
        }
        throw Exception('Failed to get scripts count: unexpected response');
      } else {
        throw Exception('Failed to get scripts count: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get scripts count: $e');
    }
  }

  Future<String> saveScript(ScriptRecord script) async {
    try {
      File('poem_debug.log')
          .writeAsStringSync('metadata ${script.id}: ${script.metadata}\n', mode: FileMode.append);

      // First try to check if script exists using a simple GET request
      final checkResponse = await _client.get(
        Uri.parse('$baseUrl/api/v1/scripts/${script.id}?includePrivate=true'),
      );

      File('poem_debug.log').writeAsStringSync(
        'check ${script.id}: ${checkResponse.statusCode}\n',
        mode: FileMode.append,
      );

      if (checkResponse.statusCode == 200) {
        // Generate proper signature for script update using test utilities
        final updateData = TestSignatureUtils.createTestUpdateRequest(script.id, updates: {
          'title': script.title,
          'description': script.metadata['description'] ?? '',
          'category': script.metadata['category'] ?? 'Development',
          'lua_source': script.luaSource,
          'tags': (script.metadata['tags'] as List<dynamic>? ?? const [])
              .map((tag) => tag.toString())
              .toList(),
          'version': (script.metadata['version'] ?? '1.0.0').toString(),
          'price': script.metadata['price'] ?? 0.0,
          'is_public': script.metadata['isPublic'] ?? false,
        });

        if (!updateData.containsKey('version')) {
          throw Exception('Update payload missing version for ${script.id}');
        }


        File('poem_debug.log').writeAsStringSync(
          'update ${script.id}: ${json.encode(updateData)}\n',
          mode: FileMode.append,
        );

        final response = await _client.put(
          Uri.parse('$baseUrl/api/v1/scripts/${script.id}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updateData),
        );


        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode}');
        }

        _assertSuccessfulMutation(response, 'update script ${script.id}');
        return script.id;
      } else {
        // Use simplified authorization token
        final baseScriptData = _scriptToApiJson(script);

        // Create the final script data with simple auth token
        final scriptData = Map<String, dynamic>.from(baseScriptData);
        scriptData['signature'] = 'test-auth-token';
        scriptData['action'] = 'upload';


        final response = await _client.post(
          Uri.parse('$baseUrl/api/v1/scripts'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(scriptData),
        );


        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Failed to save script ${script.id}: ${response.statusCode}');
        }

        _assertSuccessfulMutation(response, 'create script ${script.id}');
        // Return the generated ID from response
        final responseData = json.decode(response.body);
        if (responseData['success'] == true && responseData['data'] != null) {
          return responseData['data']['id'] as String;
        }

        return script.id;
      }
    } catch (e) {
      // For e2e tests, fail if server is not available
      throw Exception('Failed to save script: $e');
    }
  }

  Future<List<ScriptRecord>> getAllScripts() async {
    return loadScripts();
  }

  void dispose() {
    _client.close();
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
          final error = decoded['error'] ?? decoded['message'] ?? decoded['details'] ?? 'unknown error';
          throw Exception('Failed to $operation: ${response.statusCode} - $error');
        }
      }
    } catch (_) {
      // Ignore responses that are not JSON
    }
  }
}
