import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_repository.dart';

/// Mock script repository for testing purposes
/// Used in widget tests where real HTTP requests are not allowed
class MockScriptRepository extends ScriptRepository {
  final List<ScriptRecord> _scripts = [];
  bool _shouldFail = false;

  /// Configure whether the repository should simulate failures
  void setShouldFail(bool fail) {
    _shouldFail = fail;
  }

  /// Add a script to the mock repository
  void addScript(ScriptRecord script) {
    _scripts.add(script);
  }

  /// Clear all scripts from the mock repository
  void clearScripts() {
    _scripts.clear();
  }

  @override
  Future<List<ScriptRecord>> loadScripts() async {
    if (_shouldFail) throw Exception('Mock repository failure');
    return List.from(_scripts);
  }

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    _scripts.clear();
    _scripts.addAll(scripts);
  }

  /// Additional methods that match MiniflareScriptRepository interface
  Future<List<ScriptRecord>> getPublicScripts() async {
    if (_shouldFail) throw Exception('Mock repository failure');
    return _scripts.where((s) => s.metadata['isPublic'] == true).toList();
  }

  Future<List<ScriptRecord>> getScriptsByCategory(String category) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    return _scripts.where((s) => s.metadata['category'] == category).toList();
  }

  Future<ScriptRecord?> getScriptById(String id, {bool includePrivate = true}) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    try {
      final script = _scripts.firstWhere((s) => s.id == id);
      if (!includePrivate && script.metadata['isPublic'] != true) {
        return null;
      }
      return script;
    } catch (e) {
      return null;
    }
  }

  Future<String> saveScript(ScriptRecord script) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    
    // Generate a mock ID if not present
    if (script.id.isEmpty) {
      final mockScript = ScriptRecord(
        id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
        title: script.title,
        emoji: script.emoji,
        imageUrl: script.imageUrl,
        luaSource: script.luaSource,
        metadata: script.metadata,
        createdAt: script.createdAt,
        updatedAt: script.updatedAt,
      );
      _scripts.add(mockScript);
      return mockScript.id;
    } else {
      // Update existing script
      final index = _scripts.indexWhere((s) => s.id == script.id);
      if (index >= 0) {
        _scripts[index] = script;
      } else {
        _scripts.add(script);
      }
      return script.id;
    }
  }

  Future<void> deleteScript(String id) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    _scripts.removeWhere((s) => s.id == id);
  }

  Future<List<ScriptRecord>> searchScripts(String query) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    final lowerQuery = query.toLowerCase();
    return _scripts.where((s) {
      final title = s.title.toLowerCase();
      final description = (s.metadata['description'] as String? ?? '').toLowerCase();
      final category = (s.metadata['category'] as String? ?? '').toLowerCase();
      return title.contains(lowerQuery) || description.contains(lowerQuery) || category.contains(lowerQuery);
    }).toList();
  }

  Future<int> getScriptsCount() async {
    if (_shouldFail) throw Exception('Mock repository failure');
    return _scripts.length;
  }

  Future<String> publishScript(ScriptRecord script) async {
    if (_shouldFail) throw Exception('Mock repository failure');
    
    // Update script to be public
    final publicScript = ScriptRecord(
      id: script.id.isEmpty ? 'mock_${DateTime.now().millisecondsSinceEpoch}' : script.id,
      title: script.title,
      emoji: script.emoji,
      imageUrl: script.imageUrl,
      luaSource: script.luaSource,
      metadata: {...script.metadata, 'isPublic': true},
      createdAt: script.createdAt,
      updatedAt: DateTime.now(),
    );
    
    // Update or add the script
    final index = _scripts.indexWhere((s) => s.id == publicScript.id);
    if (index >= 0) {
      _scripts[index] = publicScript;
    } else {
      _scripts.add(publicScript);
    }
    
    return publicScript.id;
  }

  Future<List<ScriptRecord>> getAllScripts() async {
    if (_shouldFail) throw Exception('Mock repository failure');
    return List.from(_scripts);
  }

  void dispose() {
    _scripts.clear();
  }
}