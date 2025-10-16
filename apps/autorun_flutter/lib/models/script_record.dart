import 'dart:convert';

class ScriptRecord {
  ScriptRecord({
    required this.id,
    required this.title,
    this.emoji,
    this.imageUrl,
    required this.luaSource,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(emoji == null || emoji.isNotEmpty),
       assert(imageUrl == null || imageUrl.isNotEmpty);

  final String id;
  final String title;
  final String? emoji; // Unicode emoji character, optional
  final String? imageUrl; // Optional remote/local image path
  final String luaSource; // The Lua script source code
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'emoji': emoji,
    'imageUrl': imageUrl,
    'luaSource': luaSource,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ScriptRecord.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String title = json['title'] as String? ?? '';
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('ScriptRecord requires non-empty id and title');
    }
    final String luaSource = json['luaSource'] as String? ?? '';
    if (luaSource.isEmpty) {
      throw const FormatException('ScriptRecord requires non-empty luaSource');
    }
    return ScriptRecord(
      id: id,
      title: title,
      emoji: json['emoji'] as String?,
      imageUrl: json['imageUrl'] as String?,
      luaSource: luaSource,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  ScriptRecord copyWith({
    String? title,
    String? emoji,
    String? imageUrl,
    String? luaSource,
    DateTime? updatedAt,
  }) {
    return ScriptRecord(
      id: id,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      imageUrl: imageUrl ?? this.imageUrl,
      luaSource: luaSource ?? this.luaSource,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
