
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Model for a script template that users can select when creating new scripts
class ScriptTemplate {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String level; // beginner, intermediate, advanced
  final String? _filePath; // Path to the bundle asset
  final List<String> tags;
  final bool isRecommended;
  final String? _initialLuaSource;
  String? _cachedLuaSource;

  ScriptTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.level,
    required this.tags,
    String? filePath,
    String? preloadedLuaSource,
    this.isRecommended = false,
  })  : _filePath = filePath,
        _initialLuaSource = preloadedLuaSource,
        assert(
          preloadedLuaSource == null || preloadedLuaSource.trim().isNotEmpty,
          'preloadedLuaSource for $id cannot be empty',
        );

  /// Bundle source associated with this template.
  /// Throws if the source has not been loaded (fail fast requirement).
  String get luaSource {
    final String? source = _cachedLuaSource ?? _initialLuaSource;
    if (source == null) {
      throw StateError(
        'Bundle source for template "$id" has not been loaded. '
        'Call ScriptTemplates.ensureInitialized() before accessing templates.',
      );
    }
    return source;
  }

  /// Load the bundle source from the provided [AssetBundle].
  Future<void> load(AssetBundle bundle) async {
    if (_cachedLuaSource != null || _initialLuaSource != null) {
      _cachedLuaSource ??= _initialLuaSource;
      return;
    }

    final String? path = _filePath;
    if (path == null || path.trim().isEmpty) {
      throw StateError(
        'Template "$id" is missing an asset file path. '
        'Assign a valid filePath or provide preloadedLuaSource.',
      );
    }

    try {
      final String assetContent = await bundle.loadString(path, cache: false);
      if (assetContent.trim().isEmpty) {
        throw StateError(
          'Bundle source loaded from "$path" for template "$id" is empty.',
        );
      }
      _cachedLuaSource = assetContent;
    } on FlutterError catch (error) {
      throw StateError(
        'Failed to load template asset "$path" for "$id": ${error.message}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptTemplate &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          emoji == other.emoji &&
          level == other.level &&
          _filePath == other._filePath &&
          tags == other.tags &&
          _initialLuaSource == other._initialLuaSource &&
          isRecommended == other.isRecommended;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      description.hashCode ^
      emoji.hashCode ^
      level.hashCode ^
      _filePath.hashCode ^
      _initialLuaSource.hashCode ^
      tags.hashCode ^
      isRecommended.hashCode;
}

/// Built-in script templates available to users
class ScriptTemplates {
  static List<ScriptTemplate> _templates = [];
  static bool _initialized = false;
  static Future<void>? _initialization;

  /// Get all templates after initialization.
  static List<ScriptTemplate> get templates {
    _assertInitialized();
    return _templates;
  }

  /// Ensure templates have been loaded from assets.
  static Future<void> ensureInitialized({AssetBundle? bundle}) {
    if (_initialized) {
      return SynchronousFuture<void>(null);
    }
    _initialization ??= _loadTemplates(bundle ?? rootBundle);
    return _initialization!;
  }

  static Future<void> _loadTemplates(AssetBundle bundle) async {
    final List<ScriptTemplate> templates = [
      ScriptTemplate(
        id: 'hello_world',
        title: 'Hello World',
        description:
            'Simple introduction to TypeScript scripting — a greeting, a counter, and a text field.',
        emoji: '👋',
        level: 'beginner',
        filePath: 'lib/examples/01_hello_world.js',
        tags: ['typescript', 'basic', 'ui', 'state'],
        isRecommended: true,
      ),

      ScriptTemplate(
        id: 'icp_demo',
        title: 'Canister Query Demo',
        description:
            'Query an ICP canister via an effect and format the result with SDK helpers.',
        emoji: '🌐',
        level: 'intermediate',
        filePath: 'lib/examples/02_canister_query.js',
        tags: ['typescript', 'icp', 'blockchain', 'canister'],
        isRecommended: false,
      ),

      ScriptTemplate(
        id: 'advanced_ui',
        title: 'Forms & UI Demo',
        description:
            'Rich TypeScript UI: text fields, toggles, selects, image, sections, and lists.',
        emoji: '🎨',
        level: 'advanced',
        filePath: 'lib/examples/03_forms_and_ui.js',
        tags: ['typescript', 'ui', 'forms', 'advanced'],
        isRecommended: false,
      ),

      ScriptTemplate(
        id: 'typescript_counter',
        title: 'TypeScript Counter',
        description:
            'Get started with TypeScript scripting — a simple counter with init/view/update.',
        emoji: '🟦',
        level: 'beginner',
        filePath: 'lib/examples/05_typescript_counter.js',
        tags: ['typescript', 'basic', 'counter'],
        isRecommended: true,
      ),
    ];
    for (final ScriptTemplate template in templates) {
      await template.load(bundle);
    }
    _templates = templates;
    _initialized = true;
  }

  static ScriptTemplate? getById(String id) {
    _assertInitialized();
    try {
      return templates.firstWhere((template) => template.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<ScriptTemplate> getByLevel(String level) {
    _assertInitialized();
    return templates.where((template) => template.level == level).toList();
  }

  static List<ScriptTemplate> getRecommended() {
    _assertInitialized();
    return templates.where((template) => template.isRecommended).toList();
  }

  static List<ScriptTemplate> search(String query) {
    _assertInitialized();
    final lowerQuery = query.toLowerCase();
    return templates.where((template) {
      return template.title.toLowerCase().contains(lowerQuery) ||
          template.description.toLowerCase().contains(lowerQuery) ||
          template.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'ScriptTemplates.ensureInitialized() must be awaited before accessing templates.',
      );
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _templates = [];
    _initialized = false;
    _initialization = null;
  }
}
