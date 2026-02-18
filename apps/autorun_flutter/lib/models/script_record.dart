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
    this.metadata = const {},
    this.runCount = 0,
    this.lastRunAt,
  })  : assert(emoji == null || emoji.isNotEmpty),
        assert(imageUrl == null || imageUrl.isNotEmpty);

  final String id;
  final String title;
  final String? emoji;
  final String? imageUrl;
  final String luaSource;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;
  final int runCount;
  final DateTime? lastRunAt;

  String? get marketplaceId => metadata['marketplace_id'] as String?;
  String? get marketplaceVersion => metadata['marketplace_version'] as String?;
  String? get marketplaceAuthor => metadata['marketplace_author'] as String?;
  String? get sha256Checksum => metadata['sha256_checksum'] as String?;
  bool get isFromMarketplace => marketplaceId != null;

  ScriptRecord recordRun() {
    return copyWith(
      runCount: runCount + 1,
      lastRunAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'emoji': emoji,
        'imageUrl': imageUrl,
        'luaSource': luaSource,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'metadata': metadata,
        'runCount': runCount,
        'lastRunAt': lastRunAt?.toIso8601String(),
      };

  factory ScriptRecord.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String title = json['title'] as String? ?? '';
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException(
          'ScriptRecord requires non-empty id and title');
    }
    final String luaSource = json['luaSource'] as String? ?? '';
    if (luaSource.isEmpty) {
      throw const FormatException('ScriptRecord requires non-empty luaSource');
    }
    final String? lastRunAtStr = json['lastRunAt'] as String?;
    return ScriptRecord(
      id: id,
      title: title,
      emoji: json['emoji'] as String?,
      imageUrl: json['imageUrl'] as String?,
      luaSource: luaSource,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
      runCount: json['runCount'] as int? ?? 0,
      lastRunAt: lastRunAtStr != null ? DateTime.parse(lastRunAtStr) : null,
    );
  }

  ScriptRecord copyWith({
    String? title,
    String? emoji,
    String? imageUrl,
    String? luaSource,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
    int? runCount,
    DateTime? lastRunAt,
  }) {
    return ScriptRecord(
      id: id,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      imageUrl: imageUrl ?? this.imageUrl,
      luaSource: luaSource ?? this.luaSource,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
      runCount: runCount ?? this.runCount,
      lastRunAt: lastRunAt ?? this.lastRunAt,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
