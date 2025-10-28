
import 'dart:io';

/// Model for a script template that users can select when creating new scripts
class ScriptTemplate {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String level; // beginner, intermediate, advanced
  final String? _filePath; // Path to the actual Lua file
  final List<String> tags;
  final bool isRecommended;

  const ScriptTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.level,
    required this.tags,
    String? filePath,
    this.isRecommended = false,
  }) : _filePath = filePath;

  /// Read the Lua source from the actual file at compilation time
  String get luaSource {
    if (_filePath != null) {
      try {
        final file = File(_filePath);
        if (file.existsSync()) {
          return file.readAsStringSync();
        }
      } catch (e) {
        // Fallback to embedded content or empty string if file can't be read
      }
    }
    return '';
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
          isRecommended == other.isRecommended;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      description.hashCode ^
      emoji.hashCode ^
      level.hashCode ^
      _filePath.hashCode ^
      tags.hashCode ^
      isRecommended.hashCode;
}

/// Built-in script templates available to users
class ScriptTemplates {
  static List<ScriptTemplate> _templates = [];
  static bool _initialized = false;

  /// Get all templates (loads from files on first access)
  static List<ScriptTemplate> get templates {
    if (!_initialized) {
      _initializeTemplates();
      _initialized = true;
    }
    return _templates;
  }

  /// Initialize templates - creates all templates with file paths
  static void _initializeTemplates() {
    _templates = [
      ScriptTemplate(
        id: 'hello_world',
        title: 'Hello World',
        description: 'Simple introduction to Lua scripting with basic UI components and state management.',
        emoji: '👋',
        level: 'beginner',
        filePath: 'lib/examples/01_hello_world.lua',
        tags: ['basic', 'ui', 'state'],
        isRecommended: true,
      ),

      ScriptTemplate(
        id: 'data_management',
        title: 'Simple Data Management',
        description: 'Learn how to manage lists of data, implement filtering, and work with user input.',
        emoji: '📋',
        level: 'beginner',
        filePath: 'lib/examples/02_simple_data.lua',
        tags: ['data', 'filtering', 'ui'],
        isRecommended: false,
      ),

      ScriptTemplate(
        id: 'icp_demo',
        title: 'Simple ICP Demo',
        description: 'Make real calls to ICP blockchain canisters and display the results.',
        emoji: '🌐',
        level: 'intermediate',
        filePath: 'lib/examples/03_simple_icp_demo.lua',
        tags: ['icp', 'blockchain', 'canister'],
        isRecommended: false,
      ),

      ScriptTemplate(
        id: 'advanced_ui',
        title: 'Advanced UI Demo',
        description: 'Advanced UI with filtering, sorting, statistics, and complex data visualization.',
        emoji: '🎨',
        level: 'advanced',
        filePath: 'lib/examples/04_advanced_ui_refactored.lua',
        tags: ['ui', 'advanced', 'filtering', 'sorting', 'statistics'],
        isRecommended: false,
      ),
    ];
  }

  static ScriptTemplate? getById(String id) {
    try {
      return templates.firstWhere((template) => template.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<ScriptTemplate> getByLevel(String level) {
    return templates.where((template) => template.level == level).toList();
  }

  static List<ScriptTemplate> getRecommended() {
    return templates.where((template) => template.isRecommended).toList();
  }

  static List<ScriptTemplate> search(String query) {
    final lowerQuery = query.toLowerCase();
    return templates.where((template) {
      return template.title.toLowerCase().contains(lowerQuery) ||
          template.description.toLowerCase().contains(lowerQuery) ||
          template.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}